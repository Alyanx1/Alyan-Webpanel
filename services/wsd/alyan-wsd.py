#!/usr/bin/env python3
"""
Alyan Webpanel — Wire-Speed Asyncio SSH-WebSocket Bridge (alyan-wsd)
Listens on 127.0.0.1:2095 (accepting PROXY protocol v1/v2 from HAProxy),
handles HTTP 101 Switching Protocols for /alyan & custom Injector payloads,
bridges to Dropbear (127.0.0.1:109) with TCP_NODELAY & 64KB zero-stall buffers,
and exports real client IP + byte stats to /run/alyan-wsd-sessions.json.
"""
import asyncio
import base64
import hashlib
import ipaddress
import json
import os
import socket
import struct
import time
from pathlib import Path

LISTEN_HOST = os.environ.get("ALYAN_WSD_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("ALYAN_WSD_PORT", "2095"))
TARGET_HOST = os.environ.get("ALYAN_SSH_TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.environ.get("ALYAN_SSH_TARGET_PORT", "109"))
STATE_FILE = Path("/run/alyan-wsd-sessions.json")

PROXY_V2_SIG = b"\r\n\r\n\x00\r\nQUIT\n"
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def build_101_response(payload: bytes) -> bytes:
    sec_key = None
    if b"\r\n" in payload:
        header_text = payload.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
        for line in header_text.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                if k.strip().lower() == "sec-websocket-key":
                    sec_key = v.strip()
                    break

    resp_lines = [
        "HTTP/1.1 101 Switching Protocols",
        "Upgrade: websocket",
        "Connection: Upgrade",
    ]
    if sec_key:
        sha = hashlib.sha1((sec_key + WS_GUID).encode("utf-8")).digest()
        accept_b64 = base64.b64encode(sha).decode("utf-8")
        resp_lines.append(f"Sec-WebSocket-Accept: {accept_b64}")
    else:
        resp_lines.append("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    resp_lines.append("Server: Alyan-Flame-Edge")
    return ("\r\n".join(resp_lines) + "\r\n\r\n").encode("latin1")

CF_NETWORKS = [
    ipaddress.ip_network(cidr)
    for cidr in (
        "127.0.0.0/8",
        "173.245.48.0/20",
        "103.21.244.0/22",
        "103.22.200.0/22",
        "103.31.4.0/22",
        "141.101.64.0/18",
        "108.162.192.0/18",
        "190.93.240.0/20",
        "188.114.96.0/20",
        "197.234.240.0/22",
        "198.41.128.0/17",
        "162.158.0.0/15",
        "104.16.0.0/13",
        "104.24.0.0/14",
        "172.64.0.0/13",
        "131.0.72.0/22",
        "2400:cb00::/32",
        "2606:4700::/32",
        "2803:f800::/32",
        "2405:b500::/32",
        "2405:8100::/32",
        "2a06:98c0::/29",
        "2c0f:f248::/32",
    )
]

ACTIVE_SESSIONS = {}
RECENT_CLOSED = {}


def normalize_ip(raw: str) -> str | None:
    s = (raw or "").strip().strip("[]")
    if s.lower().startswith("::ffff:"):
        s = s[7:]
    try:
        return str(ipaddress.ip_address(s))
    except ValueError:
        return None


def is_trusted_cdn(ip_str: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip_str)
        if addr.is_loopback:
            return True
        if any(addr in net for net in CF_NETWORKS):
            return True
        if isinstance(addr, ipaddress.IPv4Address):
            s = str(addr)
            if s.startswith(("143.204.", "52.84.", "54.192.", "54.230.", "54.239.", "54.240.", "13.32.", "13.33.", "13.35.", "13.224.", "13.225.", "13.226.", "13.227.", "13.249.", "18.64.", "18.65.", "18.66.", "18.67.", "18.154.", "18.155.", "18.160.", "18.161.", "18.164.", "18.165.", "64.252.", "65.8.", "65.9.", "70.132.", "99.84.", "99.86.", "108.138.", "108.156.", "108.157.", "108.158.", "108.159.", "204.246.", "205.251.")):
                return True
        return False
    except ValueError:
        return False


def tune_socket(writer: asyncio.StreamWriter):
    sock = writer.get_extra_info("socket")
    if sock is not None:
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        except Exception:
            pass
    tr = writer.transport
    if tr is not None:
        try:
            tr.set_write_buffer_limits(high=262144, low=65536)
        except Exception:
            pass


def flush_state_now():
    try:
        now = time.time()
        for k in list(RECENT_CLOSED.keys()):
            if now - RECENT_CLOSED[k].get("closed_at", 0) > 15.0:
                del RECENT_CLOSED[k]
        snapshot = {}
        for port, s in list(RECENT_CLOSED.items()):
            snapshot[port] = {
                "ip": s["ip"],
                "since": s["since"],
                "bytes": s["bytes"],
                "closed": True,
            }
        for port, s in list(ACTIVE_SESSIONS.items()):
            snapshot[port] = {
                "ip": s["ip"],
                "since": s["since"],
                "bytes": s["rx"] + s["tx"],
                "closed": False,
            }
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(snapshot), encoding="utf-8")
        tmp.replace(STATE_FILE)
    except Exception:
        pass


def parse_proxy_header(buf: bytes):
    """Parse HAProxy PROXY v2 or v1 header. Returns (real_ip, remaining_bytes) or None if need more bytes."""
    if buf.startswith(PROXY_V2_SIG):
        if len(buf) < 16:
            return None
        ver_cmd = buf[12]
        fam_proto = buf[13]
        addr_len = struct.unpack("!H", buf[14:16])[0]
        total = 16 + addr_len
        if len(buf) < total:
            return None
        real_ip = "127.0.0.1"
        if (ver_cmd & 0x0F) == 0x01:
            fam = fam_proto >> 4
            if fam == 0x1 and addr_len >= 12:
                real_ip = socket.inet_ntop(socket.AF_INET, buf[16:20])
            elif fam == 0x2 and addr_len >= 36:
                real_ip = socket.inet_ntop(socket.AF_INET6, buf[16:32])
                if real_ip.startswith("::ffff:"):
                    real_ip = real_ip[7:]
        return real_ip, buf[total:]

    if buf.startswith(b"PROXY "):
        idx = buf.find(b"\r\n")
        if idx == -1:
            return None if len(buf) < 108 else ("127.0.0.1", buf)
        parts = buf[:idx].decode("latin1", errors="ignore").split()
        real_ip = parts[2] if len(parts) >= 3 else "127.0.0.1"
        return real_ip, buf[idx + 2:]

    return None, buf


def strip_ws_headers(data: bytes) -> tuple[bool, bytes]:
    if data.startswith(b"SSH-"):
        return False, data
    ssh_idx = data.find(b"SSH-")
    if ssh_idx != -1:
        return True, data[ssh_idx:]
    end_idx = data.find(b"\r\n\r\n")
    if end_idx != -1:
        return True, data[end_idx + 4:]
    return True, b""


async def pipe_stream(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, stat_dict: dict, key: str):
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            stat_dict[key] += len(chunk)
            writer.write(chunk)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle_client(c_reader: asyncio.StreamReader, c_writer: asyncio.StreamWriter):
    tune_socket(c_writer)
    peer = c_writer.get_extra_info("peername")
    real_ip = normalize_ip(peer[0]) if peer else "127.0.0.1"
    real_ip = real_ip or "127.0.0.1"
    local_port = None

    try:
        initial = await asyncio.wait_for(c_reader.read(16384), timeout=12.0)
        if not initial:
            c_writer.close()
            return

        parsed = parse_proxy_header(initial)
        while parsed is None:
            more = await asyncio.wait_for(c_reader.read(4096), timeout=6.0)
            if not more:
                c_writer.close()
                return
            initial += more
            parsed = parse_proxy_header(initial)

        p_ip, payload = parsed
        if p_ip:
            norm_p = normalize_ip(p_ip)
            if norm_p:
                real_ip = norm_p

        if not payload:
            payload = await asyncio.wait_for(c_reader.read(16384), timeout=12.0)
            if not payload:
                c_writer.close()
                return

        if not payload.startswith(b"SSH-") and b"\r\n\r\n" not in payload:
            while b"\r\n\r\n" not in payload and len(payload) < 8192:
                try:
                    more = await asyncio.wait_for(c_reader.read(4096), timeout=3.0)
                    if not more:
                        break
                    payload += more
                except asyncio.TimeoutError:
                    break

        # Unwrap CDN client IP headers ONLY if TCP connection came from Cloudflare / loopback
        if is_trusted_cdn(real_ip) and b"\r\n" in payload and not payload.startswith(b"SSH-"):
            hdr_text = payload.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
            hdr_map = {}
            for line in hdr_text.splitlines()[1:]:
                if ":" in line:
                    k, v = line.split(":", 1)
                    hdr_map[k.strip().lower()] = v.strip()
            for hk in ("cloudfront-viewer-address", "cf-connecting-ip", "true-client-ip", "x-forwarded-for", "x-real-ip"):
                if hk in hdr_map:
                    raw_val = hdr_map[hk]
                    if ":" in raw_val and not raw_val.startswith("["):
                        raw_val = raw_val.split(":", 1)[0]
                    cand = normalize_ip(raw_val.split(",")[0])
                    if cand and cand not in ("127.0.0.1", "::1"):
                        real_ip = cand
                        break

        needs_101, tail = strip_ws_headers(payload)
        if needs_101:
            resp_101 = build_101_response(payload)
            c_writer.write(resp_101)
            await c_writer.drain()

        s_reader, s_writer = await asyncio.wait_for(
            asyncio.open_connection(TARGET_HOST, TARGET_PORT, limit=262144),
            timeout=8.0,
        )
        tune_socket(s_writer)

        sock_info = s_writer.get_extra_info("sockname")
        local_port = str(sock_info[1]) if sock_info else f"anon-{id(c_writer)}"

        stat_entry = {
            "ip": real_ip,
            "since": int(time.time()),
            "rx": len(tail),
            "tx": 0,
        }
        ACTIVE_SESSIONS[local_port] = stat_entry
        flush_state_now()

        if tail:
            if not tail.startswith(b"SSH-") and b"SSH-" in tail:
                tail = tail[tail.find(b"SSH-"):]
            elif not tail.startswith(b"SSH-") and b"\r\n\r\n" in tail:
                tail = tail.split(b"\r\n\r\n")[-1]
            if tail:
                s_writer.write(tail)
                await s_writer.drain()

        await asyncio.gather(
            pipe_stream(c_reader, s_writer, stat_entry, "rx"),
            pipe_stream(s_reader, c_writer, stat_entry, "tx"),
        )
    except Exception:
        try:
            c_writer.close()
        except Exception:
            pass
    finally:
        if local_port and local_port in ACTIVE_SESSIONS:
            st = ACTIVE_SESSIONS.pop(local_port)
            RECENT_CLOSED[local_port] = {
                "ip": st["ip"],
                "since": st["since"],
                "bytes": st["rx"] + st["tx"],
                "closed_at": time.time(),
            }
            flush_state_now()


async def flush_sessions_loop():
    while True:
        flush_state_now()
        await asyncio.sleep(1.5)


async def main():
    server = await asyncio.start_server(
        handle_client,
        LISTEN_HOST,
        LISTEN_PORT,
        backlog=8192,
        limit=262144,
    )
    asyncio.create_task(flush_sessions_loop())
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass

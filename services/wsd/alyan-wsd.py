#!/usr/bin/env python3
"""
Alyan Webpanel — High-Performance Asyncio SSH-WebSocket Bridge (alyan-wsd)
Listens on 127.0.0.1:2095 (accepting PROXY protocol v1/v2 from HAProxy),
handles HTTP 101 Switching Protocols for /alyan & custom Injector payloads,
bridges to Dropbear (127.0.0.1:109), and exports real client IP + byte stats
to /run/alyan-wsd-sessions.json for alyan-guard & Webpanel correlation.
"""
import asyncio
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
HTTP_101_RESPONSE = (
    b"HTTP/1.1 101 Switching Protocols\r\n"
    b"Upgrade: websocket\r\n"
    b"Connection: Upgrade\r\n"
    b"Server: Alyan-Flame-Edge\r\n\r\n"
)

ACTIVE_SESSIONS = {}


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
        if (ver_cmd & 0x0F) == 0x01:  # PROXY command
            fam = fam_proto >> 4
            if fam == 0x1 and addr_len >= 12:  # AF_INET
                real_ip = socket.inet_ntop(socket.AF_INET, buf[16:20])
            elif fam == 0x2 and addr_len >= 36:  # AF_INET6
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
    """
    Detect HTTP upgrade / split injector headers and return (needs_101, ssh_tail_bytes).
    Supports standard GET /alyan HTTP/1.1 as well as split double-payloads before SSH-2.0-.
    """
    if data.startswith(b"SSH-"):
        return False, data

    # Look for end of HTTP header block(s)
    ssh_idx = data.find(b"SSH-")
    if ssh_idx != -1:
        return True, data[ssh_idx:]

    end_idx = data.rfind(b"\r\n\r\n")
    if end_idx != -1:
        return True, data[end_idx + 4:]
    return True, b""


async def pipe_stream(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, stat_dict: dict, key: str):
    try:
        while True:
            chunk = await reader.read(32768)
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
    peer = c_writer.get_extra_info("peername")
    real_ip = peer[0] if peer else "127.0.0.1"
    local_port = None

    try:
        initial = await asyncio.wait_for(c_reader.read(8192), timeout=12.0)
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
            real_ip = p_ip

        # Read HTTP upgrade request if PROXY header arrived in its own packet
        if not payload:
            payload = await asyncio.wait_for(c_reader.read(8192), timeout=12.0)
            if not payload:
                c_writer.close()
                return

        # Extract X-Forwarded-For / CF-Connecting-IP if client came via CDN proxy
        if b"\r\n" in payload and not payload.startswith(b"SSH-"):
            hdr_text = payload.split(b"\r\n\r\n", 1)[0].decode("latin1", errors="ignore")
            for line in hdr_text.splitlines():
                low = line.lower()
                if low.startswith("cf-connecting-ip:") or low.startswith("x-real-ip:"):
                    cand = line.split(":", 1)[1].strip()
                    if cand:
                        real_ip = cand
                        break

        needs_101, tail = strip_ws_headers(payload)
        if needs_101:
            c_writer.write(HTTP_101_RESPONSE)
            await c_writer.drain()

        s_reader, s_writer = await asyncio.wait_for(
            asyncio.open_connection(TARGET_HOST, TARGET_PORT), timeout=8.0
        )
        sock_info = s_writer.get_extra_info("sockname")
        local_port = str(sock_info[1]) if sock_info else f"anon-{id(c_writer)}"

        stat_entry = {
            "ip": real_ip,
            "since": int(time.time()),
            "rx": len(tail),
            "tx": 0,
            "flushed": 0,
        }
        ACTIVE_SESSIONS[local_port] = stat_entry

        if tail:
            # Handle optional second HTTP split header before SSH-2.0-
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
            del ACTIVE_SESSIONS[local_port]


async def flush_sessions_loop():
    while True:
        try:
            tmp = STATE_FILE.with_suffix(".tmp")
            snapshot = {
                port: {
                    "ip": s["ip"],
                    "since": s["since"],
                    "bytes": s["rx"] + s["tx"],
                }
                for port, s in list(ACTIVE_SESSIONS.items())
            }
            tmp.write_text(json.dumps(snapshot), encoding="utf-8")
            tmp.replace(STATE_FILE)
        except Exception:
            pass
        await asyncio.sleep(2.5)


async def main():
    server = await asyncio.start_server(
        handle_client, LISTEN_HOST, LISTEN_PORT, backlog=2048
    )
    asyncio.create_task(flush_sessions_loop())
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass

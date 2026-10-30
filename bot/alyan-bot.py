#!/usr/bin/env python3
"""
Alyan Webpanel — Full Remote User-Management Telegram Bot (bot/alyan-bot.py)
Runs as `alyan-bot.service` (`User=alyan`), communicating with `/usr/local/bin/alyan-ctl`.
Supports interactive Inline Keyboards, step-by-step wizards, and direct slash commands:
  /start, /addssh, /delssh, /renewssh, /addxray, /delxray, /users, /status, /restart
"""
import asyncio
import base64
import html
import json
import os
import urllib.parse
from typing import Any

import httpx

CTL_BIN = "/usr/local/bin/alyan-ctl"

# Per-chat wizard state: chat_id -> {"step": str, "data": dict}
WIZARDS: dict[int, dict[str, Any]] = {}


async def ctl(subcmd: list[str]) -> dict[str, Any]:
    prefix = [CTL_BIN] if os.geteuid() == 0 else ["sudo", "-n", CTL_BIN]
    proc = await asyncio.create_subprocess_exec(
        *prefix,
        "--actor",
        "telegram",
        "--client-ip",
        "telegram-bot",
        *subcmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    out_b, err_b = await asyncio.wait_for(proc.communicate(), timeout=40.0)
    txt = out_b.decode("utf-8", errors="ignore").strip()
    parsed = {}
    if txt:
        try:
            parsed = json.loads(txt.splitlines()[-1])
        except Exception:
            pass
    if proc.returncode != 0:
        raise RuntimeError(parsed.get("error") or err_b.decode("utf-8", errors="ignore").strip() or "Command failed")
    return parsed


def fmt_bytes(b: int | float) -> str:
    val = float(b or 0)
    if val >= 1073741824:
        return f"{val / 1073741824:.2f} GB"
    if val >= 1048576:
        return f"{val / 1048576:.1f} MB"
    return f"{int(val / 1024)} KB"


def build_ssh_card_html(item: dict, domain: str) -> str:
    u = html.escape(item["username"])
    p = html.escape(item["password"])
    d = html.escape(domain)
    exp = html.escape(item["expiry"])
    gb = f"{item['gb_limit']} GB" if item.get("gb_limit", 0) > 0 else "Unlimited"
    ip_cap = f"{item['ip_limit']} IP" if item.get("ip_limit", 0) > 0 else "Unlimited"
    payload = f"GET /alyan HTTP/1.1[crlf]Host: {d}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    return (
        f"🔥 <b>ALYAN SSH ACCOUNT CREATED</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━\n"
        f"👤 <b>Username:</b> <code>{u}</code>\n"
        f"🔑 <b>Password:</b> <code>{p}</code>\n"
        f"🌐 <b>Host / SNI:</b> <code>{d}</code>\n"
        f"📅 <b>Expires:</b> <code>{exp}</code>\n"
        f"📊 <b>Quota / IP:</b> {gb} · {ip_cap}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🔌 <b>Direct SSH:</b> <code>22, 109, 143</code>\n"
        f"🔒 <b>SSH SSL/TLS:</b> <code>443</code>\n"
        f"⚡ <b>SSH WS:</b> <code>80</code> &amp; <code>443</code> (<code>/alyan</code>)\n\n"
        f"📋 <b>HTTP Injector Payload:</b>\n"
        f"<pre>{payload}</pre>"
    )


def build_xray_card_html(item: dict, domain: str) -> str:
    proto = item["proto"]
    u = item["username"]
    uid = item["uuid"]
    tag = urllib.parse.quote(f"Alyan-{u}")
    uris = []
    if proto == "vless":
        uris.append(("VLESS WS TLS (443)", f"vless://{uid}@{domain}:443?encryption=none&security=tls&sni={domain}&type=ws&host={domain}&path=%2Falyan-vless#{tag}-WS"))
        uris.append(("VLESS WS HTTP (80)", f"vless://{uid}@{domain}:80?encryption=none&security=none&type=ws&host={domain}&path=%2Falyan-vless#{tag}-80"))
        uris.append(("VLESS gRPC (443)", f"vless://{uid}@{domain}:443?encryption=none&security=tls&sni={domain}&type=grpc&serviceName=alyan-vless-grpc#{tag}-gRPC"))
        uris.append(("VLESS XHTTP (443)", f"vless://{uid}@{domain}:443?encryption=none&security=tls&sni={domain}&type=xhttp&host={domain}&path=%2Falyan-xhttp#{tag}-XHTTP"))
    elif proto == "vmess":
        for prt, tls in (("443", "tls"), ("80", "")):
            obj = {
                "v": "2", "ps": f"Alyan-{u}-{prt}", "add": domain, "port": prt,
                "id": uid, "aid": "0", "scy": "auto", "net": "ws", "type": "none",
                "host": domain, "path": "/alyan-vmess", "tls": tls, "sni": domain if tls else "",
            }
            b64 = base64.b64encode(json.dumps(obj, separators=(",", ":")).encode()).decode()
            uris.append((f"VMess WS ({prt})", f"vmess://{b64}"))
    elif proto == "trojan":
        uris.append(("Trojan TCP TLS (443)", f"trojan://{uid}@{domain}:443?security=tls&sni={domain}&type=tcp#{tag}-TCP"))
        uris.append(("Trojan WS TLS (443)", f"trojan://{uid}@{domain}:443?security=tls&sni={domain}&type=ws&host={domain}&path=%2Falyan-trojan#{tag}-WS"))
        uris.append(("Trojan gRPC (443)", f"trojan://{uid}@{domain}:443?security=tls&sni={domain}&type=grpc&serviceName=alyan-trojan-grpc#{tag}-gRPC"))

    gb = f"{item['gb_limit']} GB" if item.get("gb_limit", 0) > 0 else "Unlimited"
    lines = [
        f"⚡ <b>ALYAN {proto.upper()} CLIENT CREATED</b>",
        "━━━━━━━━━━━━━━━━━━━━━━",
        f"👤 <b>Client:</b> <code>{html.escape(u)}</code>",
        f"🔑 <b>UUID/Key:</b> <code>{html.escape(uid)}</code>",
        f"📅 <b>Expires:</b> <code>{html.escape(item['expiry'])}</code> · <b>Quota:</b> {gb}",
        "━━━━━━━━━━━━━━━━━━━━━━",
    ]
    for label, link in uris:
        lines.append(f"<b>{html.escape(label)}:</b>\n<code>{html.escape(link)}</code>")
    return "\n\n".join(lines)


def main_menu_kb() -> dict:
    return {
        "inline_keyboard": [
            [
                {"text": "➕ New SSH (/alyan)", "callback_data": "wiz:ssh"},
                {"text": "⚡ New VLESS", "callback_data": "wiz:xray:vless"},
            ],
            [
                {"text": "⚡ New VMess", "callback_data": "wiz:xray:vmess"},
                {"text": "🔒 New Trojan", "callback_data": "wiz:xray:trojan"},
            ],
            [
                {"text": "👥 All Users", "callback_data": "act:users"},
                {"text": "📊 Server Status", "callback_data": "act:status"},
            ],
            [
                {"text": "🔄 Renew SSH", "callback_data": "menu:renewssh"},
                {"text": "🗑 Delete / Lock User", "callback_data": "menu:deluser"},
            ],
            [
                {"text": "♻ Restart Daemons", "callback_data": "menu:restart"},
            ],
        ]
    }


async def send_msg(client: httpx.AsyncClient, token: str, chat_id: int, text: str, kb: dict | None = None):
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }
    if kb:
        payload["reply_markup"] = kb
    await client.post(f"https://api.telegram.org/bot{token}/sendMessage", json=payload)


async def answer_cb(client: httpx.AsyncClient, token: str, cb_id: str, text: str = ""):
    await client.post(
        f"https://api.telegram.org/bot{token}/answerCallbackQuery",
        json={"callback_query_id": cb_id, "text": text},
    )


async def format_status_html() -> str:
    d = await ctl(["overview"])
    cfg = d["cfg"]
    svcs = d["services"]
    svc_lines = []
    for s in svcs:
        dot = "🟢" if s["status"] == "running" else "🔴"
        svc_lines.append(f"{dot} <b>{html.escape(s['name'])}</b> — <code>{html.escape(s['status'])}</code> ({html.escape(s['mem'])})")
    return (
        f"🔥 <b>ALYAN WEBPANEL — LIVE STATUS</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🌐 <b>Domain:</b> <code>{html.escape(cfg['domain'])}</code>\n"
        f"🖥 <b>IP / OS:</b> <code>{html.escape(cfg['ip'])}</code> · {html.escape(cfg['os'])}\n"
        f"⏱ <b>Uptime:</b> {html.escape(cfg['uptime'])} · <b>SSL:</b> {cfg['ssl_days']}d\n"
        f"⚡ <b>CPU:</b> {d['cpu_pct']}% · <b>RAM:</b> {d['ram_pct']}% · <b>Disk:</b> {d['disk_pct']}%\n"
        f"👥 <b>SSH:</b> {d['ssh_total']} ({d['ssh_online']} online) · <b>Xray:</b> {d['xray_total']}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━\n"
        + "\n".join(svc_lines)
    )


async def format_users_html() -> str:
    s_data = await ctl(["ssh-list"])
    x_data = await ctl(["xray-list"])
    lines = ["👥 <b>ALYAN ACCOUNTS OVERVIEW</b>", "━━━━━━━━━━━━━━━━━━━━━━", "<b>SSH / WS (/alyan):</b>"]
    if not s_data["items"]:
        lines.append("<i>No SSH accounts</i>")
    for u in s_data["items"][:25]:
        st = "🔴 disable" if u["status"] == "disabled" else (f"🟢 {u['online']} live" if u["online"] else "⚪ offline")
        qt = f"{fmt_bytes(u['used_bytes'])}/{u['gb_limit']}G" if u["gb_limit"] > 0 else fmt_bytes(u["used_bytes"])
        lines.append(f"• <code>{html.escape(u['username'])}</code> [{st}] — {qt} · exp <code>{u['expiry']}</code>")

    lines.append("\n<b>Xray (VLESS / VMess / Trojan):</b>")
    if not x_data["items"]:
        lines.append("<i>No Xray clients</i>")
    for u in x_data["items"][:25]:
        st = "🟢 online" if u["online"] else "⚪ idle"
        lines.append(f"• <code>{html.escape(u['username'])}</code> ({u['proto'].upper()}) [{st}] — exp <code>{u['expiry']}</code>")
    return "\n".join(lines)


async def handle_wizard_input(client: httpx.AsyncClient, token: str, chat_id: int, text: str) -> bool:
    wiz = WIZARDS.get(chat_id)
    if not wiz:
        return False
    if text.startswith("/"):
        WIZARDS.pop(chat_id, None)
        return False

    step = wiz["step"]
    data = wiz["data"]

    try:
        if step == "ssh_user":
            data["username"] = text.strip()
            wiz["step"] = "ssh_pass"
            await send_msg(client, token, chat_id, f"🔑 Enter password for SSH user <code>{html.escape(data['username'])}</code>:")
            return True
        if step == "ssh_pass":
            data["password"] = text.strip()
            wiz["step"] = "ssh_limits"
            await send_msg(
                client, token, chat_id,
                "📅 Enter <b>Days GB IPLimit</b> separated by spaces (default: <code>30 0 2</code> where 0 = Unlimited):",
            )
            return True
        if step == "ssh_limits":
            parts = text.split()
            days = int(parts[0]) if len(parts) >= 1 else 30
            gb = float(parts[1]) if len(parts) >= 2 else 0.0
            ip_lim = int(parts[2]) if len(parts) >= 3 else 2
            WIZARDS.pop(chat_id, None)
            res = await ctl([
                "ssh-add",
                "--username", data["username"],
                "--password", data["password"],
                "--days", str(days),
                "--gb-limit", str(gb),
                "--ip-limit", str(ip_lim),
            ])
            await send_msg(client, token, chat_id, build_ssh_card_html(res["item"], res["cfg"]["domain"]), main_menu_kb())
            return True

        if step == "xray_user":
            data["username"] = text.strip()
            wiz["step"] = "xray_limits"
            await send_msg(
                client, token, chat_id,
                f"📅 Enter <b>Days GB IPLimit</b> for {data['proto'].upper()} client <code>{html.escape(data['username'])}</code> (e.g. <code>30 0 2</code>):",
            )
            return True
        if step == "xray_limits":
            parts = text.split()
            days = int(parts[0]) if len(parts) >= 1 else 30
            gb = float(parts[1]) if len(parts) >= 2 else 0.0
            ip_lim = int(parts[2]) if len(parts) >= 3 else 2
            WIZARDS.pop(chat_id, None)
            res = await ctl([
                "xray-add",
                "--username", data["username"],
                "--proto", data["proto"],
                "--days", str(days),
                "--gb-limit", str(gb),
                "--ip-limit", str(ip_lim),
            ])
            await send_msg(client, token, chat_id, build_xray_card_html(res["item"], res["cfg"]["domain"]), main_menu_kb())
            return True
    except Exception as exc:
        WIZARDS.pop(chat_id, None)
        await send_msg(client, token, chat_id, f"❌ <b>Error:</b> {html.escape(str(exc))}", main_menu_kb())
        return True

    return False


async def handle_command(client: httpx.AsyncClient, token: str, chat_id: int, text: str):
    parts = text.strip().split()
    cmd = parts[0].lower().split("@")[0]

    if cmd in ("/start", "/menu", "/help"):
        ov = await ctl(["overview"])
        dom = html.escape(ov["cfg"]["domain"])
        prt = ov["cfg"]["panel_port"]
        msg = (
            f"🔥 <b>ALYAN WEBPANEL — TELEGRAM DECK</b>\n"
            f"Host: <code>{dom}</code> · Panel: <code>https://{dom}:{prt}</code>\n\n"
            f"Select an action below or use quick commands:\n"
            f"<code>/addssh user pass 30 0 2</code>\n"
            f"<code>/addxray vless user 30 0 2</code>\n"
            f"<code>/renewssh user 30</code> · <code>/delssh user</code>\n"
            f"<code>/users</code> · <code>/status</code> · <code>/restart</code>"
        )
        await send_msg(client, token, chat_id, msg, main_menu_kb())
        return

    if cmd == "/status":
        await send_msg(client, token, chat_id, await format_status_html(), main_menu_kb())
        return

    if cmd == "/users":
        await send_msg(client, token, chat_id, await format_users_html(), main_menu_kb())
        return

    if cmd == "/addssh":
        if len(parts) >= 3:
            u, p = parts[1], parts[2]
            d = parts[3] if len(parts) >= 4 else "30"
            g = parts[4] if len(parts) >= 5 else "0"
            i = parts[5] if len(parts) >= 6 else "2"
            res = await ctl(["ssh-add", "--username", u, "--password", p, "--days", d, "--gb-limit", g, "--ip-limit", i])
            await send_msg(client, token, chat_id, build_ssh_card_html(res["item"], res["cfg"]["domain"]), main_menu_kb())
        else:
            WIZARDS[chat_id] = {"step": "ssh_user", "data": {}}
            await send_msg(client, token, chat_id, "👤 Enter new <b>SSH Username</b>:")
        return

    if cmd == "/delssh":
        if len(parts) >= 2:
            await ctl(["ssh-del", "--username", parts[1]])
            await send_msg(client, token, chat_id, f"✅ Deleted SSH account <code>{html.escape(parts[1])}</code>.", main_menu_kb())
        else:
            await send_msg(client, token, chat_id, "Usage: <code>/delssh username</code> (or use <b>Delete / Lock User</b> button)", main_menu_kb())
        return

    if cmd == "/renewssh":
        if len(parts) >= 2:
            u = parts[1]
            d = int(parts[2]) if len(parts) >= 3 else 30
            await ctl(["ssh-edit", "--username", u, "--json", json.dumps({"days": d, "reset_quota": True, "status": "active"})])
            await send_msg(client, token, chat_id, f"🔄 Renewed <code>{html.escape(u)}</code> for <b>{d} days</b> (quota reset &amp; enabled).", main_menu_kb())
        else:
            await send_msg(client, token, chat_id, "Usage: <code>/renewssh username 30</code>", main_menu_kb())
        return

    if cmd == "/addxray":
        if len(parts) >= 3:
            pr, u = parts[1].lower(), parts[2]
            d = parts[3] if len(parts) >= 4 else "30"
            g = parts[4] if len(parts) >= 5 else "0"
            i = parts[5] if len(parts) >= 6 else "2"
            res = await ctl(["xray-add", "--username", u, "--proto", pr, "--days", d, "--gb-limit", g, "--ip-limit", i])
            await send_msg(client, token, chat_id, build_xray_card_html(res["item"], res["cfg"]["domain"]), main_menu_kb())
        else:
            WIZARDS[chat_id] = {"step": "xray_user", "data": {"proto": "vless"}}
            await send_msg(client, token, chat_id, "⚡ Enter new <b>VLESS Client Username</b>:")
        return

    if cmd == "/delxray":
        if len(parts) >= 2:
            target = parts[1]
            x_data = await ctl(["xray-list"])
            match = next((x["uuid"] for x in x_data["items"] if x["uuid"] == target or x["username"].lower() == target.lower()), target)
            await ctl(["xray-del", "--uuid", match])
            await send_msg(client, token, chat_id, f"✅ Removed Xray client <code>{html.escape(target)}</code>.", main_menu_kb())
        else:
            await send_msg(client, token, chat_id, "Usage: <code>/delxray username_or_uuid</code>", main_menu_kb())
        return

    if cmd == "/restart":
        svc = parts[1] if len(parts) >= 2 else "all"
        await ctl(["service", svc, "restart"])
        await send_msg(client, token, chat_id, f"♻ Restarted <code>{html.escape(svc)}</code> cleanly!", main_menu_kb())
        return

    await send_msg(client, token, chat_id, "Send /start to open the Alyan Flame Control Panel.", main_menu_kb())


async def handle_callback(client: httpx.AsyncClient, token: str, chat_id: int, cb_id: str, data: str):
    await answer_cb(client, token, cb_id)

    if data == "wiz:ssh":
        WIZARDS[chat_id] = {"step": "ssh_user", "data": {}}
        await send_msg(client, token, chat_id, "👤 Enter new <b>SSH Username</b>:")
        return

    if data.startswith("wiz:xray:"):
        proto = data.split(":")[2]
        WIZARDS[chat_id] = {"step": "xray_user", "data": {"proto": proto}}
        await send_msg(client, token, chat_id, f"⚡ Enter new <b>{proto.upper()} Client Username</b>:")
        return

    if data == "act:status":
        await send_msg(client, token, chat_id, await format_status_html(), main_menu_kb())
        return

    if data == "act:users":
        await send_msg(client, token, chat_id, await format_users_html(), main_menu_kb())
        return

    if data == "menu:renewssh":
        s_data = await ctl(["ssh-list"])
        rows = [[{"text": f"🔄 {u['username']} (+30d)", "callback_data": f"rnw:{u['username']}"}] for u in s_data["items"][:12]]
        rows.append([{"text": "⬅ Back", "callback_data": "back:main"}])
        await send_msg(client, token, chat_id, "Select SSH account to renew (+30 days &amp; unlock):", {"inline_keyboard": rows})
        return

    if data.startswith("rnw:"):
        u = data.split(":", 1)[1]
        await ctl(["ssh-edit", "--username", u, "--json", json.dumps({"days": 30, "reset_quota": True, "status": "active"})])
        await send_msg(client, token, chat_id, f"✅ Renewed <code>{html.escape(u)}</code> (+30 days).", main_menu_kb())
        return

    if data == "menu:deluser":
        s_data = await ctl(["ssh-list"])
        x_data = await ctl(["xray-list"])
        rows = []
        for u in s_data["items"][:8]:
            tog = "🟢 Enable" if u["status"] == "disabled" else "⏸ Disable"
            nxt = "active" if u["status"] == "disabled" else "disabled"
            rows.append([
                {"text": f"{tog} {u['username']}", "callback_data": f"stog:{u['username']}:{nxt}"},
                {"text": f"🗑 SSH {u['username']}", "callback_data": f"sdel:{u['username']}"},
            ])
        for x in x_data["items"][:8]:
            rows.append([{"text": f"🗑 {x['proto'].upper()} {x['username']}", "callback_data": f"xdel:{x['uuid']}"}])
        rows.append([{"text": "⬅ Back", "callback_data": "back:main"}])
        await send_msg(client, token, chat_id, "Manage account lock or delete:", {"inline_keyboard": rows})
        return

    if data.startswith("stog:"):
        _, u, nxt = data.split(":", 2)
        await ctl(["ssh-edit", "--username", u, "--json", json.dumps({"status": nxt})])
        await send_msg(client, token, chat_id, f"✅ SSH <code>{html.escape(u)}</code> → <b>{html.escape(nxt)}</b>", main_menu_kb())
        return

    if data.startswith("sdel:"):
        u = data.split(":", 1)[1]
        await ctl(["ssh-del", "--username", u])
        await send_msg(client, token, chat_id, f"🗑 Deleted SSH user <code>{html.escape(u)}</code>.", main_menu_kb())
        return

    if data.startswith("xdel:"):
        uid = data.split(":", 1)[1]
        await ctl(["xray-del", "--uuid", uid])
        await send_msg(client, token, chat_id, "🗑 Deleted Xray client.", main_menu_kb())
        return

    if data == "menu:restart":
        kb = {
            "inline_keyboard": [
                [
                    {"text": "🔥 Full Stack", "callback_data": "rst:all"},
                    {"text": "HAProxy", "callback_data": "rst:haproxy"},
                ],
                [
                    {"text": "Nginx", "callback_data": "rst:nginx"},
                    {"text": "Dropbear", "callback_data": "rst:dropbear"},
                ],
                [
                    {"text": "WS-Proxy (/alyan)", "callback_data": "rst:alyan-wsd"},
                    {"text": "Xray-Core", "callback_data": "rst:xray"},
                ],
                [{"text": "⬅ Back", "callback_data": "back:main"}],
            ]
        }
        await send_msg(client, token, chat_id, "Select daemon to restart:", kb)
        return

    if data.startswith("rst:"):
        svc = data.split(":", 1)[1]
        await ctl(["service", svc, "restart"])
        await send_msg(client, token, chat_id, f"♻ Restarted <code>{html.escape(svc)}</code>!", main_menu_kb())
        return

    if data == "back:main":
        await send_msg(client, token, chat_id, "🔥 <b>Alyan Webpanel Main Menu</b>", main_menu_kb())


async def main():
    offset = 0
    async with httpx.AsyncClient(timeout=35.0) as client:
        while True:
            try:
                cfg_wrap = await ctl(["bot-config"])
                bot = cfg_wrap.get("cfg", {}).get("bot", {})
                token = str(bot.get("token") or "").strip()
                allowed = {
                    int(x.strip())
                    for x in str(bot.get("admin_id") or "").split(",")
                    if x.strip().lstrip("-").isdigit()
                }
                if not bot.get("enabled") or not token or not allowed:
                    await asyncio.sleep(10.0)
                    continue

                resp = await client.get(
                    f"https://api.telegram.org/bot{token}/getUpdates",
                    params={"offset": offset, "timeout": 25},
                )
                payload = resp.json()
                if not payload.get("ok"):
                    await asyncio.sleep(5.0)
                    continue

                for upd in payload.get("result", []):
                    offset = upd["update_id"] + 1
                    if "callback_query" in upd:
                        cb = upd["callback_query"]
                        uid = cb.get("from", {}).get("id")
                        cid = cb.get("message", {}).get("chat", {}).get("id", uid)
                        if uid not in allowed and cid not in allowed:
                            continue
                        try:
                            await handle_callback(client, token, cid, cb["id"], cb.get("data", ""))
                        except Exception as exc:
                            await send_msg(client, token, cid, f"❌ {html.escape(str(exc))}", main_menu_kb())
                    elif "message" in upd:
                        msg = upd["message"]
                        uid = msg.get("from", {}).get("id")
                        cid = msg.get("chat", {}).get("id", uid)
                        if uid not in allowed and cid not in allowed:
                            continue
                        text = (msg.get("text") or "").strip()
                        if not text:
                            continue
                        if await handle_wizard_input(client, token, cid, text):
                            continue
                        try:
                            await handle_command(client, token, cid, text)
                        except Exception as exc:
                            await send_msg(client, token, cid, f"❌ {html.escape(str(exc))}", main_menu_kb())
            except Exception:
                await asyncio.sleep(5.0)


if __name__ == "__main__":
    asyncio.run(main())

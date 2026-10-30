#!/usr/bin/env python3
"""
Alyan Webpanel — FastAPI Backend Command Deck (panel/app.py)
Runs as unprivileged user `alyan` on 127.0.0.1:7700 behind Nginx TLS.
Executes privileged OS/tunneling mutations exclusively via `sudo -n /usr/local/bin/alyan-ctl`.
"""
import asyncio
import hmac
import json
import os
import secrets
import time
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
SESSION_FILE = BASE_DIR / ".alyan_sessions.json"
SECRET_FILE = BASE_DIR / ".alyan_secret.key"
CTL_BIN = "/usr/local/bin/alyan-ctl"

SESSION_TTL = 86400 * 7  # 7 days
COOKIE_NAME = "alyan_sid"

# Brute-force login rate limiter: ip -> [timestamps]
LOGIN_FAILURES: dict[str, list[float]] = {}
MAX_FAILURES = 8
FAIL_WINDOW = 300.0


def load_or_create_secret() -> bytes:
    try:
        if SECRET_FILE.exists():
            return SECRET_FILE.read_bytes().strip()
        raw = secrets.token_hex(32).encode("utf-8")
        SECRET_FILE.write_bytes(raw)
        os.chmod(SECRET_FILE, 0o600)
        return raw
    except Exception:
        return secrets.token_hex(32).encode("utf-8")


SECRET_KEY = load_or_create_secret()


def load_sessions() -> dict[str, dict[str, Any]]:
    if SESSION_FILE.exists():
        try:
            data = json.loads(SESSION_FILE.read_text(encoding="utf-8"))
            now = time.time()
            return {k: v for k, v in data.items() if v.get("exp", 0) > now}
        except Exception:
            pass
    return {}


def save_sessions(sessions: dict[str, dict[str, Any]]):
    try:
        now = time.time()
        clean = {k: v for k, v in sessions.items() if v.get("exp", 0) > now}
        tmp = SESSION_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(clean), encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(SESSION_FILE)
    except Exception:
        pass


SESSIONS: dict[str, dict[str, Any]] = load_sessions()


def sign_sid(sid: str) -> str:
    sig = hmac.new(SECRET_KEY, sid.encode("utf-8"), "sha256").hexdigest()[:32]
    return f"{sid}.{sig}"


def verify_signed_sid(cookie_val: str | None) -> str | None:
    if not cookie_val or "." not in cookie_val:
        return None
    sid, sig = cookie_val.split(".", 1)
    expected = hmac.new(SECRET_KEY, sid.encode("utf-8"), "sha256").hexdigest()[:32]
    if not hmac.compare_digest(sig, expected):
        return None
    return sid


def client_ip(request: Request) -> str:
    xff = request.headers.get("x-real-ip") or request.headers.get("x-forwarded-for") or ""
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "127.0.0.1"


async def run_ctl(
    subcmd: list[str],
    actor: str = "admin",
    ip: str = "127.0.0.1",
    timeout: float = 35.0,
) -> dict[str, Any]:
    prefix = [CTL_BIN] if os.geteuid() == 0 else ["sudo", "-n", CTL_BIN]
    cmd = [*prefix, "--actor", actor, "--client-ip", ip, *subcmd]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout_b, stderr_b = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Control engine operation timed out")
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail="alyan-ctl binary not installed")

    out_txt = stdout_b.decode("utf-8", errors="ignore").strip()
    err_txt = stderr_b.decode("utf-8", errors="ignore").strip()

    parsed: dict[str, Any] = {}
    if out_txt:
        try:
            parsed = json.loads(out_txt.splitlines()[-1])
        except Exception:
            pass

    if proc.returncode != 0:
        detail = parsed.get("error") or err_txt or "Operation failed"
        code = int(parsed.get("code") or 400)
        raise HTTPException(status_code=code, detail=detail)

    return parsed


def require_session(request: Request) -> dict[str, Any]:
    sid = verify_signed_sid(request.cookies.get(COOKIE_NAME))
    if not sid or sid not in SESSIONS:
        raise HTTPException(status_code=401, detail="Authentication required")
    sess = SESSIONS[sid]
    if sess.get("exp", 0) <= time.time():
        SESSIONS.pop(sid, None)
        save_sessions(SESSIONS)
        raise HTTPException(status_code=401, detail="Session expired")

    if request.method in ("POST", "PATCH", "DELETE", "PUT"):
        csrf_hdr = request.headers.get("x-csrf-token", "")
        if not csrf_hdr or not hmac.compare_digest(csrf_hdr, sess.get("csrf", "")):
            raise HTTPException(status_code=403, detail="Invalid CSRF token — refresh page")
    return sess


app = FastAPI(title="Alyan Webpanel API", docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    resp = await call_next(request)
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "no-referrer"
    if request.url.path.startswith("/api/"):
        resp.headers["Cache-Control"] = "no-store"
    return resp


# ─── Auth Routes ─────────────────────────────────────────────────────────────
@app.get("/api/auth/me")
async def api_auth_me(request: Request):
    sid = verify_signed_sid(request.cookies.get(COOKIE_NAME))
    if not sid or sid not in SESSIONS or SESSIONS[sid].get("exp", 0) <= time.time():
        raise HTTPException(status_code=401, detail="Not signed in")
    sess = SESSIONS[sid]
    data = await run_ctl(["admin-me", "--username", sess["username"]], actor=sess["username"], ip=client_ip(request))
    data["csrf"] = sess["csrf"]
    return data


@app.post("/api/auth/login")
async def api_auth_login(request: Request, response: Response):
    ip = client_ip(request)
    now = time.time()
    recent = [t for t in LOGIN_FAILURES.get(ip, []) if now - t < FAIL_WINDOW]
    LOGIN_FAILURES[ip] = recent
    if len(recent) >= MAX_FAILURES:
        raise HTTPException(status_code=429, detail="Too many failed login attempts. Wait 5 minutes.")

    body = await request.json()
    username = str(body.get("username") or "").strip()
    password = str(body.get("password") or "")
    if not username or not password:
        raise HTTPException(status_code=400, detail="Username and password are required")

    try:
        data = await run_ctl(
            ["admin-login", "--username", username, "--password", password],
            actor="root",
            ip=ip,
        )
    except HTTPException:
        LOGIN_FAILURES.setdefault(ip, []).append(now)
        raise HTTPException(status_code=401, detail="Invalid username or password")

    LOGIN_FAILURES.pop(ip, None)
    sid = secrets.token_urlsafe(24)
    csrf = secrets.token_hex(24)
    SESSIONS[sid] = {
        "username": data["user"]["username"],
        "role": data["user"]["role"],
        "csrf": csrf,
        "exp": now + SESSION_TTL,
    }
    save_sessions(SESSIONS)

    is_https = request.headers.get("x-forwarded-proto", "").lower() == "https" or request.url.scheme == "https"
    response.set_cookie(
        key=COOKIE_NAME,
        value=sign_sid(sid),
        max_age=SESSION_TTL,
        httponly=True,
        secure=is_https,
        samesite="lax",
        path="/",
    )
    data["csrf"] = csrf
    return data


@app.post("/api/auth/logout")
async def api_auth_logout(request: Request, response: Response):
    sid = verify_signed_sid(request.cookies.get(COOKIE_NAME))
    if sid and sid in SESSIONS:
        SESSIONS.pop(sid, None)
        save_sessions(SESSIONS)
    response.delete_cookie(COOKIE_NAME, path="/")
    return {"ok": True}


# ─── Core & Telemetry Routes ─────────────────────────────────────────────────
@app.get("/api/overview")
async def api_overview(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["overview"], actor=sess["username"], ip=client_ip(request))


@app.get("/api/telemetry")
async def api_telemetry(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["telemetry"], actor=sess["username"], ip=client_ip(request))


@app.post("/api/speedtest")
async def api_speedtest(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["speedtest"], actor=sess["username"], ip=client_ip(request), timeout=65.0)


# ─── SSH Accounts Routes ─────────────────────────────────────────────────────
@app.get("/api/ssh")
async def api_ssh_list(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["ssh-list"], actor=sess["username"], ip=client_ip(request))


@app.post("/api/ssh")
async def api_ssh_create(request: Request, sess: dict = Depends(require_session)):
    b = await request.json()
    return await run_ctl(
        [
            "ssh-add",
            "--username", str(b.get("username") or ""),
            "--password", str(b.get("password") or ""),
            "--days", str(int(float(b.get("days") or 30))),
            "--gb-limit", str(float(b.get("gb_limit") or 0)),
            "--ip-limit", str(int(float(b.get("ip_limit") or 0))),
        ],
        actor=sess["username"],
        ip=client_ip(request),
    )


@app.patch("/api/ssh/{username}")
async def api_ssh_edit(username: str, request: Request, sess: dict = Depends(require_session)):
    b = await request.json()
    return await run_ctl(
        ["ssh-edit", "--username", username, "--json", json.dumps(b)],
        actor=sess["username"],
        ip=client_ip(request),
    )


@app.delete("/api/ssh/{username}")
async def api_ssh_delete(username: str, request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["ssh-del", "--username", username], actor=sess["username"], ip=client_ip(request))


# ─── Xray Matrix Routes ──────────────────────────────────────────────────────
@app.get("/api/xray")
async def api_xray_list(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["xray-list"], actor=sess["username"], ip=client_ip(request))


@app.post("/api/xray")
async def api_xray_create(request: Request, sess: dict = Depends(require_session)):
    b = await request.json()
    return await run_ctl(
        [
            "xray-add",
            "--username", str(b.get("username") or ""),
            "--proto", str(b.get("proto") or "vless"),
            "--days", str(int(float(b.get("days") or 30))),
            "--gb-limit", str(float(b.get("gb_limit") or 0)),
            "--ip-limit", str(int(float(b.get("ip_limit") or 0))),
            "--uuid", str(b.get("uuid") or ""),
        ],
        actor=sess["username"],
        ip=client_ip(request),
    )


@app.patch("/api/xray/{uuid}")
async def api_xray_edit(uuid: str, request: Request, sess: dict = Depends(require_session)):
    b = await request.json()
    return await run_ctl(
        ["xray-edit", "--uuid", uuid, "--json", json.dumps(b)],
        actor=sess["username"],
        ip=client_ip(request),
    )


@app.delete("/api/xray/{uuid}")
async def api_xray_delete(uuid: str, request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["xray-del", "--uuid", uuid], actor=sess["username"], ip=client_ip(request))


# ─── Engine, Daemons & Ports Routes ──────────────────────────────────────────
@app.get("/api/engine")
async def api_engine(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["engine"], actor=sess["username"], ip=client_ip(request))


@app.get("/api/service/{svc_id}/logs")
async def api_service_logs(svc_id: str, request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["service", svc_id, "logs"], actor=sess["username"], ip=client_ip(request))


@app.post("/api/service/{svc_id}/{action}")
async def api_service_action(svc_id: str, action: str, request: Request, sess: dict = Depends(require_session)):
    if action not in ("start", "stop", "restart"):
        raise HTTPException(status_code=400, detail="Unsupported service action")
    return await run_ctl(["service", svc_id, action], actor=sess["username"], ip=client_ip(request))


# ─── Settings, Telegram, Admins & Activity List Routes ───────────────────────
@app.post("/api/settings")
async def api_settings(request: Request, sess: dict = Depends(require_session)):
    b = await request.json()
    return await run_ctl(
        ["settings", "--json", json.dumps(b)],
        actor=sess["username"],
        ip=client_ip(request),
        timeout=90.0,
    )


@app.post("/api/telegram/test")
async def api_telegram_test(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["tg-test"], actor=sess["username"], ip=client_ip(request))


@app.get("/api/admins")
async def api_admins_list(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["admin-list"], actor=sess["username"], ip=client_ip(request))


@app.post("/api/admins")
async def api_admins_create(request: Request, sess: dict = Depends(require_session)):
    b = await request.json()
    return await run_ctl(["admin-add", "--json", json.dumps(b)], actor=sess["username"], ip=client_ip(request))


@app.delete("/api/admins/{username}")
async def api_admins_delete(username: str, request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["admin-del", "--username", username], actor=sess["username"], ip=client_ip(request))


@app.get("/api/audit")
async def api_audit(request: Request, sess: dict = Depends(require_session)):
    return await run_ctl(["audit-list"], actor=sess["username"], ip=client_ip(request))


# ─── Static UI Shell Routes ──────────────────────────────────────────────────
NO_CACHE_HEADERS = {"Cache-Control": "no-cache, no-store, must-revalidate"}


@app.get("/")
async def index_page():
    return FileResponse(STATIC_DIR / "index.html", headers=NO_CACHE_HEADERS)


@app.get("/app.css")
async def app_css():
    return FileResponse(STATIC_DIR / "app.css", media_type="text/css", headers=NO_CACHE_HEADERS)


@app.get("/app.js")
async def app_js():
    return FileResponse(STATIC_DIR / "app.js", media_type="application/javascript", headers=NO_CACHE_HEADERS)


if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

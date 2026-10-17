#!/data/data/com.termux/files/usr/bin/python3
"""
Local control panel for the bot: start, stop, restart, status, logs, cache, .env.

Runs inside Termux and serves a small page on 127.0.0.1 so the phone's browser can drive the
same scripts the command line does. Nothing here is a replacement for those scripts - every
action shells out to them, so the panel cannot get out of step with what `run-bot.sh` and
`run-server.sh` actually do.

**Binding matters.** This process can start and stop the bot and write `.env`, which holds the
bot token and the cookie paths. It therefore binds 127.0.0.1 and refuses to listen on any other
interface unless `--host` says so explicitly, in which case a token is required for every
request. A control panel reachable from the LAN without a password is a remote shell.

Stdlib only. Termux's Python has no Flask, and pulling one in for six endpoints is not worth a
dependency that can break on an update.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# --------------------------------------------------------------------------- paths

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
BOT_DIR = PROJECT / "bot"
DATA_DIR = PROJECT / "data"
SCRIPTS = PROJECT / "scripts"
CACHE_DIR = PROJECT / ".cache"
PARSE_CACHE = PROJECT / "parse_cache.json"
LOG_FILE = DATA_DIR / "bot.log"
ENV_FILE = PROJECT / ".env"
ENV_BACKUP_DIR = DATA_DIR / "env-backups"

BOT_PID = DATA_DIR / "bot.pid"
SERVER_PID = DATA_DIR / "bot-api.pid"
INDEX_HTML = HERE / "index.html"

DEFAULT_PORT = 8090
# A single action must not hang the panel. Starting the bot is the slowest at ~6 s.
ACTION_TIMEOUT = 90
LOG_TAIL_MAX = 2000


# --------------------------------------------------------------------------- helpers


def project_version() -> dict:
    """
    The version of the whole manager, read from VERSION.properties at the project root.

    One number covers the app, this panel and the scripts, because they ship together: a fix in
    the panel and a fix in the app are the same release, and numbering them separately would let
    them drift into combinations nobody tested.

    Reading the same file the Android build reads is the point. This panel and the app are the two
    halves of one control surface, and "which version are you running" is the first question when
    one behaves differently from the other - so both answer from one source.

    Returns `{"name": ..., "code": ...}`, with the name "?" if the file is missing or malformed.
    The panel must still start in that case: a missing version is a labelling problem, not a
    reason to refuse to run.
    """
    result = {"name": "?", "code": 0}
    try:
        text = (PROJECT / "VERSION.properties").read_text(encoding="utf-8")
    except OSError:
        return result
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if key == "versionName":
            result["name"] = value
        elif key == "versionCode":
            try:
                result["code"] = int(value)
            except ValueError:
                pass
    return result


def run(cmd: list[str], timeout: int = ACTION_TIMEOUT) -> dict:
    """
    Run a command and return its output.

    Never raises for a non-zero exit: the scripts report problems on stdout, and that text is
    more useful to show than an exception. A timeout is reported distinctly, because "it hung"
    and "it failed" need different responses from the user.
    """
    started = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(PROJECT),
            capture_output=True,
            text=True,
            timeout=timeout,
            env=os.environ.copy(),
        )
        return {
            "ok": proc.returncode == 0,
            "code": proc.returncode,
            "stdout": proc.stdout or "",
            "stderr": proc.stderr or "",
            "seconds": round(time.monotonic() - started, 2),
        }
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "code": None,
            "stdout": "",
            "stderr": f"timed out after {timeout}s",
            "seconds": round(time.monotonic() - started, 2),
        }
    except FileNotFoundError as exc:
        return {
            "ok": False,
            "code": None,
            "stdout": "",
            "stderr": f"not found: {exc}",
            "seconds": round(time.monotonic() - started, 2),
        }


def read_pid(path: Path) -> int | None:
    try:
        value = path.read_text(encoding="utf-8").strip()
        return int(value) if value else None
    except (OSError, ValueError):
        return None


def alive(pid: int | None) -> bool:
    """
    Whether a pid is running.

    `os.kill(pid, 0)` is the portable check, but it raises PermissionError for a process owned
    by someone else - which still means it exists, so that counts as alive.
    """
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


def port_listening(port: int) -> bool:
    """
    Whether something accepts connections on a local port.

    The pid file and the port can disagree - a stale pid file, or a server started by hand - so
    both are reported separately rather than merged.
    """
    import socket

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1.0)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def bot_running() -> tuple[bool, int | None, str]:
    """
    Is the bot up, and how do we know.

    Returns (running, pid, how). The pid file is tried first, then the process list: a bot whose
    pid file was lost or overwritten is still running, and reporting it as stopped would make the
    panel's Stop button do nothing.
    """
    pid = read_pid(BOT_PID)
    if alive(pid):
        return True, pid, "pid file"

    result = run(["/system/bin/sh", "-c",
                  f'pgrep -f "{PROJECT}/bot/bot.py" 2>/dev/null | head -1'], timeout=10)
    candidate = (result["stdout"] or "").strip()
    if candidate.isdigit() and alive(int(candidate)):
        return True, int(candidate), "process list"
    return False, None, "not running"


def server_running(api_port: int) -> tuple[bool, int | None, str]:
    """Is the Bot API server up. The port is the truth; the pid file is a hint."""
    pid = read_pid(SERVER_PID)
    listening = port_listening(api_port)
    if listening:
        return True, pid, "port answers"
    if alive(pid):
        # proot can be alive a moment before the server binds, so this is not called stopped.
        return True, pid, "proot alive, port not up yet"
    return False, None, "not running"


def tail_lines(path: Path, count: int) -> list[str]:
    """
    The last `count` lines, reading backwards in blocks.

    `read_text().splitlines()[-count:]` loads the whole file, and this log grows without bound -
    a 50 MB log would be read in full on every poll of the live view.
    """
    if not path.is_file():
        return []
    block = 8192
    data = b""
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            while size > 0 and data.count(b"\n") <= count:
                step = min(block, size)
                size -= step
                handle.seek(size)
                data = handle.read(step) + data
    except OSError as exc:
        return [f"(cannot read {path}: {exc})"]
    text = data.decode("utf-8", errors="replace")
    return text.splitlines()[-count:]


def disk_usage(path: Path) -> dict:
    try:
        usage = shutil.disk_usage(str(path))
        return {
            "total": usage.total,
            "used": usage.used,
            "free": usage.free,
            "free_h": human(usage.free),
        }
    except OSError:
        return {}


def human(size: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024
    return f"{size:.1f} TB"


def dir_size(path: Path) -> int:
    total = 0
    if not path.exists():
        return 0
    for root, _dirs, files in os.walk(path):
        for name in files:
            try:
                total += (Path(root) / name).stat().st_size
            except OSError:
                pass
    return total


def proxy_state() -> dict:
    """
    Whether the VPN is reachable.

    Worth showing prominently: every download needs it, and when it is down the bot looks broken
    while actually being fine. `~/.proxy-url` is where the bootstrap records it.
    """
    url = ""
    try:
        url = (Path(os.path.expanduser("~")) / ".proxy-url").read_text(encoding="utf-8").strip()
    except OSError:
        pass
    listening = False
    if url:
        match = re.search(r"://(?:\[)?([^\]]+?)(?:\])?:(\d+)", url)
        if match:
            host, port = match.group(1), int(match.group(2))
            if host in {"127.0.0.1", "localhost", "::1"}:
                listening = port_listening(port)
            else:
                listening = port_listening(port)  # best effort
    return {"url": url, "listening": listening, "configured": bool(url)}


def read_env() -> dict:
    """
    The .env as a list of (key, value) pairs plus any comments, with the file's real text.

    Returned raw rather than parsed-and-reformatted: the user is allowed to edit it, and a
    round trip through a parser would drop comments and reorder lines.
    """
    if not ENV_FILE.is_file():
        return {"exists": False, "text": "", "size": 0}
    text = ENV_FILE.read_text(encoding="utf-8", errors="replace")
    return {"exists": True, "text": text, "size": len(text)}


def write_env(text: str) -> dict:
    """
    Replace .env, after a backup and a syntax check.

    The check is deliberately narrow: it rejects a value that looks like it swallowed the next
    line, which is the failure mode that actually breaks the bot. It does not attempt to validate
    the settings themselves.
    """
    if "\x00" in text:
        return {"ok": False, "error": "檔案含有 null 位元組"}

    lines = text.splitlines()
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in stripped:
            return {"ok": False, "error": f"第 {number} 行不是 KEY=VALUE：{line[:60]}"}
        key = stripped.split("=", 1)[0]
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            return {"ok": False, "error": f"第 {number} 行的鍵名不合法：{key[:40]}"}

    ENV_BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    if ENV_FILE.is_file():
        stamp = time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(ENV_FILE, ENV_BACKUP_DIR / f".env.{stamp}")
        # Keep the last 20 only; each is small and an unbounded pile would be its own problem.
        backups = sorted(ENV_BACKUP_DIR.glob(".env.*"))
        for old in backups[:-20]:
            try:
                old.unlink()
            except OSError:
                pass

    temp = ENV_FILE.with_suffix(".env.tmp")
    # LF explicitly: a CRLF .env makes a value end with \r, which broke the server build with
    # `Can't parse as an integer string "30753020"`. Keeping LF here avoids re-creating that.
    temp.write_text(text.replace("\r\n", "\n"), encoding="utf-8", newline="\n")
    temp.replace(ENV_FILE)
    return {"ok": True, "backup": str(ENV_BACKUP_DIR)}


def clear_cache() -> dict:
    """
    Remove the cached downloads and the parse cache.

    Only the contents of `.cache` are removed, not the directory, and every path is checked to be
    inside the project first. Deleting a directory tree whose name came from configuration is how
    a cache-clear turns into data loss.
    """
    removed_files = 0
    freed = 0
    if CACHE_DIR.is_dir():
        for entry in CACHE_DIR.iterdir():
            try:
                resolved = entry.resolve()
                if PROJECT.resolve() not in resolved.parents:
                    continue
                if entry.is_file():
                    freed += entry.stat().st_size
                    entry.unlink()
                    removed_files += 1
                elif entry.is_dir():
                    freed += dir_size(entry)
                    shutil.rmtree(entry)
            except OSError:
                pass

    parse_removed = False
    if PARSE_CACHE.is_file():
        try:
            freed += PARSE_CACHE.stat().st_size
            PARSE_CACHE.unlink()
            parse_removed = True
        except OSError:
            pass

    return {
        "ok": True,
        "files": removed_files,
        "freed": human(freed),
        "parse_cache_removed": parse_removed,
    }


# --------------------------------------------------------------------------- actions


def action_shutdown() -> dict:
    """
    Stop the bot, the server and finally this panel - without the caller seeing a broken connection.

    **The ordering problem this solves.** The request arrives over HTTP from the phone app's
    "stop everything" button. If the panel killed itself while still handling that request, the
    socket would close before the response was written and the app would report a failure for an
    action that actually worked - the worst kind of feedback, because it invites the user to press
    the button again.

    So the work is handed to a detached process that waits two seconds, and this returns
    immediately. `start_new_session=True` is what makes it survive: without it the child is in
    this process's session, and killing the panel takes the child with it, leaving the bot and
    server running with no panel to control them.

    The shutdown itself is `scripts/start-all.sh --stop`, the mirror of the script that starts
    everything, so the order lives in one place rather than being duplicated here.
    """
    script = SCRIPTS / "start-all.sh"
    if not script.is_file():
        return {"ok": False, "error": f"missing {script}"}

    try:
        # The sleep is in the shell rather than in Python so that nothing is left to this process
        # once the handler returns - by the time the delay is over, this interpreter may be gone.
        subprocess.Popen(
            ["bash", "-c", f"sleep 2; exec bash '{script}' --stop"],
            cwd=str(PROJECT),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            env=os.environ.copy(),
        )
    except OSError as exc:
        return {"ok": False, "error": f"could not start the shutdown: {exc}"}

    return {
        "ok": True,
        "stdout": "已開始關閉：機器人 → 伺服器 → 控制面板。\n"
                  "面板會在約 2 秒後停止，之後這個頁面就無法再連線。\n"
                  "要重新啟動，請用 app 的「一鍵啟動服務」。",
        "stderr": "",
        "seconds": 0,
    }


def action_bot(verb: str, api_port: int) -> dict:
    script = SCRIPTS / "run-bot.sh"
    if not script.is_file():
        return {"ok": False, "error": f"missing {script}"}

    if verb == "start":
        return run(["bash", str(script), "--background"])
    if verb == "stop":
        return run(["bash", str(script), "--stop"])
    if verb == "restart":
        stop = run(["bash", str(script), "--stop"])
        time.sleep(2)
        start = run(["bash", str(script), "--background"])
        return {
            "ok": start["ok"],
            "stdout": stop["stdout"] + start["stdout"],
            "stderr": stop["stderr"] + start["stderr"],
            "seconds": stop["seconds"] + start["seconds"],
        }
    return {"ok": False, "error": f"unknown verb {verb}"}


def action_server(verb: str) -> dict:
    script = SCRIPTS / "run-server.sh"
    if not script.is_file():
        return {"ok": False, "error": f"missing {script}"}
    if verb in {"start", "stop", "restart", "status"}:
        # restart is a verb run-server.sh handles itself, so it is passed straight through.
        return run(["bash", str(script), verb], timeout=180)
    return {"ok": False, "error": f"unknown verb {verb}"}


# How long an R2 usage reading is reused. Long enough that the app's polling costs nothing, short
# enough that the number moves while the operator is watching it after clearing space.
R2_USAGE_TTL = 60.0
_r2_usage_cache: dict = {"at": 0.0, "value": None}


# The keys r2_settings() reads. Only these are lifted out of .env: a panel process holding every
# credential in the environment is a wider surface than one holding the five values it needs.
R2_ENV_KEYS = ("R2_ACCOUNT_ID", "R2_ACCESS_KEY", "R2_SECRET_KEY", "R2_BUCKET",
               "R2_PUBLIC_BASE", "R2_FREE_BYTES", "R2_LIMIT_PERCENT")


def _load_env_values() -> int:
    """
    Copy the R2 settings from .env into the environment. Returns how many were set.

    Values already present in the environment are left alone, so an override still overrides.
    Quoting is stripped and inline comments are not - .env is not shell syntax and a value with a
    "#" in it is far more likely to be part of a key than a comment.
    """
    if not ENV_FILE.is_file():
        return 0
    loaded = 0
    try:
        text = ENV_FILE.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if key not in R2_ENV_KEYS or key in os.environ:
            continue
        os.environ[key] = value.strip().strip('"').strip("'")
        loaded += 1
    return loaded


def r2_usage(*, force: bool = False) -> dict:
    """
    How full the R2 bucket is, against the free allowance.

    Returns a dict with a "state" that is always present, so a caller cannot mistake "unknown" for
    "zero": "ok", "unconfigured" or "error". The app shows the reason rather than a figure when it is
    not ok, because a confident 0 GB when the bucket cannot be read is a lie a person would act on.
    """
    now = time.time()
    cached = _r2_usage_cache.get("value")
    if (not force and cached is not None
            and now - _r2_usage_cache.get("at", 0.0) < R2_USAGE_TTL):
        return cached

    result = {"state": "error", "reason": ""}
    try:
        # **The panel never loads .env into the environment**, only reads it as text for the editor,
        # and r2.r2_settings() reads os.environ. So the bucket the bot was uploading to reported as
        # "unconfigured" here - both processes read the same file and only one was looking at it.
        #
        # Parsed rather than done with python-dotenv: this is the process that reports whether a
        # dependency is missing, so it is the worst place to need one. An ImportError would surface
        # as "cannot read the bucket" and send someone to look at Cloudflare.
        #
        # setdefault, so a value already in the environment still wins - which is how the bot's own
        # launch and any manual override keep working.
        _load_env_values()

        # The bot's directory, so its module is found rather than a copy of the settings logic.
        bot_dir = PROJECT / "bot"
        if str(bot_dir) not in sys.path:
            sys.path.insert(0, str(bot_dir))
        import r2

        settings = r2.r2_settings()
        if settings is None:
            result = {"state": "unconfigured", "reason": "R2 未設定"}
        else:
            used, count = r2.bucket_usage(settings, timeout=30.0)
            free = r2.free_bytes()
            cap = r2.limit_bytes()
            percent = (used / free * 100) if free else 0.0
            result = {
                "state": "ok",
                "reason": "",
                "bucket": settings.bucket,
                "public_base": settings.public_base,
                "used": used,
                "used_h": r2.format_bytes(used),
                "objects": count,
                "free": free,
                "free_h": r2.format_bytes(free),
                "limit": cap,
                "limit_h": r2.format_bytes(cap),
                "limit_percent": round(r2.limit_percent()),
                "remaining": max(0, cap - used),
                "remaining_h": r2.format_bytes(max(0, cap - used)),
                "percent": round(percent, 1),
                # What the operator actually needs to know at a glance.
                "full": used >= cap,
            }
    except Exception as exc:  # noqa: BLE001
        # Every failure is reported the same way: the panel says it cannot read it and why. A
        # traceback here would take down the whole status endpoint, which is what the app polls to
        # find out whether anything is wrong in the first place.
        result = {"state": "error", "reason": f"{type(exc).__name__}: {exc}"}

    _r2_usage_cache["at"] = now
    _r2_usage_cache["value"] = result
    return result


def build_status(api_port: int) -> dict:
    bot_up, bot_pid, bot_how = bot_running()
    srv_up, srv_pid, srv_how = server_running(api_port)
    proxy = proxy_state()
    cache_bytes = dir_size(CACHE_DIR)
    version = project_version()
    return {
        # Reported so the app can show which panel it is talking to next to its own version.
        # They come from the same file, so a mismatch means an old APK or a panel that was not
        # restarted after an update - both worth seeing rather than guessing at.
        "version": version,
        "bot": {"running": bot_up, "pid": bot_pid, "how": bot_how},
        "server": {"running": srv_up, "pid": srv_pid, "how": srv_how, "port": api_port},
        "proxy": proxy,
        "disk": disk_usage(PROJECT),
        "cache_bytes": cache_bytes,
        "cache_h": human(cache_bytes),
        # How full the image host is. Cached for R2_USAGE_TTL, because the app polls this endpoint
        # and a bucket listing per poll would be a round trip to Cloudflare every few seconds.
        "r2": r2_usage(),
        "log": {
            "path": str(LOG_FILE),
            "size": LOG_FILE.stat().st_size if LOG_FILE.is_file() else 0,
            "mtime": LOG_FILE.stat().st_mtime if LOG_FILE.is_file() else 0,
        },
        "time": time.time(),
    }


# --------------------------------------------------------------------------- http


class Handler(BaseHTTPRequestHandler):
    server_version = "BotPanel/1.0"
    api_port = 8081
    token = ""

    def log_message(self, fmt, *args):  # noqa: A003 - the base class names it this
        # The default writes every request to stderr, which would flood the panel's own log and
        # drown the errors that matter.
        return

    # ---------------------------------------------------------------- plumbing

    def _authorised(self, query: dict) -> bool:
        if not self.token:
            return True
        supplied = self.headers.get("X-Panel-Token") or (query.get("token", [""])[0])
        return secrets.compare_digest(supplied, self.token)

    def _json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _html(self) -> None:
        if not INDEX_HTML.is_file():
            self._json({"error": f"missing {INDEX_HTML}"}, 500)
            return
        body = INDEX_HTML.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _manifest(self) -> None:
        """
        A web app manifest so the page can be added to the home screen as an icon.

        Without one, "Add to Home screen" creates a bookmark that opens in a browser tab with the
        address bar showing. With `display: standalone` it opens full screen and looks like the
        native app this is meant to stand in for.

        The icon is an inline SVG data URI: an Android launcher accepts SVG in a manifest, and it
        avoids shipping a PNG that would have to be generated and kept in sync.
        """
        icon = (
            "data:image/svg+xml;base64,"
            + __import__("base64").b64encode(
                b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 192 192">'
                b'<rect width="192" height="192" rx="38" fill="#0f1115"/>'
                b'<rect x="40" y="46" width="112" height="76" rx="14" fill="none" '
                b'stroke="#4f8cff" stroke-width="9"/>'
                b'<circle cx="70" cy="84" r="9" fill="#4f8cff"/>'
                b'<circle cx="122" cy="84" r="9" fill="#4f8cff"/>'
                b'<path d="M74 106h44" stroke="#35c07a" stroke-width="9" stroke-linecap="round"/>'
                b'</svg>'
            ).decode("ascii")
        )
        payload = {
            "name": "Bot 控制台",
            "short_name": "Bot",
            "start_url": "/",
            "display": "standalone",
            "background_color": "#0f1115",
            "theme_color": "#0f1115",
            "icons": [
                {"src": icon, "sizes": "192x192", "type": "image/svg+xml", "purpose": "any"},
                {"src": icon, "sizes": "512x512", "type": "image/svg+xml", "purpose": "any"},
            ],
        }
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/manifest+json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}

    # ---------------------------------------------------------------- routes

    def do_GET(self) -> None:  # noqa: N802 - the base class names it this
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        path = parsed.path.rstrip("/") or "/"

        if not self._authorised(query):
            self._json({"error": "unauthorised"}, 401)
            return

        if path == "/":
            self._html()
            return
        if path == "/manifest.webmanifest":
            self._manifest()
            return
        if path == "/api/status":
            self._json(build_status(self.api_port))
            return
        if path == "/api/log":
            try:
                count = min(int(query.get("lines", ["300"])[0]), LOG_TAIL_MAX)
            except ValueError:
                count = 300
            self._json({
                "lines": tail_lines(LOG_FILE, count),
                "size": LOG_FILE.stat().st_size if LOG_FILE.is_file() else 0,
                "mtime": LOG_FILE.stat().st_mtime if LOG_FILE.is_file() else 0,
            })
            return
        if path == "/api/env":
            self._json(read_env())
            return
        self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802 - the base class names it this
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        path = parsed.path.rstrip("/")
        body = self._body()

        if not self._authorised(query):
            self._json({"error": "unauthorised"}, 401)
            return

        if path == "/api/bot/start":
            self._json(action_bot("start", self.api_port))
            return
        if path == "/api/bot/stop":
            self._json(action_bot("stop", self.api_port))
            return
        if path == "/api/bot/restart":
            self._json(action_bot("restart", self.api_port))
            return
        if path == "/api/server/start":
            self._json(action_server("start"))
            return
        if path == "/api/server/stop":
            self._json(action_server("stop"))
            return
        if path == "/api/server/restart":
            self._json(action_server("restart"))
            return
        if path == "/api/cache/clear":
            self._json(clear_cache())
            return
        if path == "/api/shutdown":
            # Answers first, stops afterwards; see action_shutdown for why the order matters.
            self._json(action_shutdown())
            return
        if path == "/api/env":
            text = body.get("text")
            if not isinstance(text, str):
                self._json({"ok": False, "error": "expected {\"text\": \"...\"}"}, 400)
                return
            self._json(write_env(text))
            return
        self._json({"error": "not found"}, 404)


def main() -> int:
    parser = argparse.ArgumentParser(description="Local control panel for the bot")
    parser.add_argument("--host", default="127.0.0.1",
                        help="interface to bind. Anything other than 127.0.0.1 requires a token")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--api-port", type=int, default=8081,
                        help="port the self-hosted Bot API server listens on")
    args = parser.parse_args()

    Handler.api_port = args.api_port

    # Binding anywhere but loopback exposes a start/stop/edit-.env surface to the network, so a
    # token is generated and required. Saying so beats a silent open port.
    if args.host not in {"127.0.0.1", "localhost", "::1"}:
        Handler.token = secrets.token_urlsafe(18)
        print(f"  WARNING: bound to {args.host}, so every request needs ?token=...")
        print(f"  panel token: {Handler.token}")
        print("  Treat this like a password: the panel can read and write .env.")
    print(f"  control panel on http://{args.host}:{args.port}/")
    print(f"  project       {PROJECT}")
    print(f"  bot API port  {args.api_port}")
    print("  Ctrl-C to stop")

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  stopped")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

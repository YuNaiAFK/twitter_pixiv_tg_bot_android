"""Local-only writer for the phone's public image directory."""
import hashlib
import asyncio
import logging
import os
import shutil
import signal
import subprocess
import tempfile
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlsplit

import httpx

MAX_STORAGE = 60_000_000_000
DISK_RESERVE = 2_000_000_000
_lock = threading.Lock()
_usage = None
_repair_lock = threading.Lock()
_repair_after = 0.0
logger = logging.getLogger(__name__)
FETCH_ERRORS = (OSError, ValueError, httpx.HTTPError)


def public_base():
    base = os.getenv("PHONE_IMAGE_PUBLIC_BASE", "").strip().rstrip("/")
    parsed = urlsplit(base)
    if parsed.scheme == "https" and parsed.netloc and not (parsed.username or parsed.query or parsed.fragment):
        return base
    return ""


def _suffix(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return ".gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return ".webp"
    raise ValueError("手機圖床不支援這種圖片格式")


def _store_one(root, name, data, stop_event):
    """Dedup and reserve bytes atomically; network requests never hold this lock."""
    import fcntl

    global _usage
    target = root / name
    with _lock, (root.parent / "phone-image-write.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if stop_event is not None and stop_event.is_set():
            return False
        if not target.is_symlink() and target.is_file():
            return True
        stamp = (root, root.stat().st_mtime_ns)
        if _usage is None or _usage[0] != stamp:
            used = sum(p.stat().st_size for p in root.iterdir()
                       if not p.name.startswith(".") and not p.is_symlink() and p.is_file())
            _usage = stamp, used
        used = _usage[1]
        if used + len(data) > MAX_STORAGE or shutil.disk_usage(root).free < len(data) + DISK_RESERVE:
            return False
        tmp = None
        try:
            with tempfile.NamedTemporaryFile(dir=root, prefix=".incoming-", delete=False) as out:
                tmp = Path(out.name)
                out.write(data)
            if stop_event is not None and stop_event.is_set():
                return False
            tmp.replace(target)
            _usage = (root, root.stat().st_mtime_ns), used + len(data)
            return True
        finally:
            if tmp is not None:
                tmp.unlink(missing_ok=True)


def _ready(base, *, local=False):
    try:
        if local:
            with httpx.Client(trust_env=False, timeout=2) as client:
                response = client.get(base + "/healthz")
        else:
            response = httpx.get(base + "/healthz", timeout=6)
        return response.status_code == 204 and response.headers.get("X-Phone-Image-Host") == "ready"
    except httpx.HTTPError:
        return False


def _restart_tunnel(project):
    # Only signal our own connector, never an unrelated cloudflared or Bot API process.
    for proc in Path("/proc").iterdir():
        if not proc.name.isdecimal():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or (proc / "comm").read_text().strip() != "cloudflared":
                continue
            args = (proc / "cmdline").read_bytes().split(b"\0")
            if b"/tmp/phone-image-host.token" in args:
                os.kill(int(proc.name), signal.SIGTERM)
        except OSError:
            continue
    # The existing launcher uses a lock. Retry briefly if the old proot still holds it.
    for _ in range(3):
        with (project / "data/image-tunnel.log").open("ab") as log:
            child = subprocess.Popen(["bash", str(project / "control/run-image-tunnel.sh")],
                                     stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            return
        time.sleep(1)


def _recover(base, project, stop_event):
    global _repair_after
    if not os.getenv("PREFIX", "").startswith("/data/data/com.termux/"):
        return False
    if stop_event is not None and stop_event.is_set():
        return False
    with _repair_lock:
        if time.monotonic() < _repair_after:
            return _ready(base)
        _repair_after = time.monotonic() + 120
        logger.warning("手機圖床公開入口異常，嘗試自動修復")
        try:
            if not _ready("http://127.0.0.1:8092", local=True):
                subprocess.run(["bash", str(project / "control/run-image-host.sh")],
                               stdin=subprocess.DEVNULL, capture_output=True, check=True, timeout=8)
            if not _ready(base):
                if not (Path.home() / ".phone-image-host.token").is_file():
                    return False
                if stop_event is not None and stop_event.is_set():
                    return False
                _restart_tunnel(project)
            for _ in range(3):
                if stop_event is not None and stop_event.is_set():
                    return False
                if _ready(base):
                    logger.info("手機圖床自動修復成功")
                    return True
                time.sleep(1)
        except (OSError, subprocess.SubprocessError):
            logger.exception("手機圖床自動修復無法完成")
        logger.warning("手機圖床仍不可用，本次交由備援圖床")
        return False


def store_many(urls, *, fetch, stop_event=None, progress=None, workers=1):
    """Return successful image URLs keyed by position; leave remaining images to the caller."""
    base = public_base()
    if not base or not urls:
        return {}
    project = Path(__file__).resolve().parent.parent
    root = project / "data" / "public-images"
    if not _ready(base) and not _recover(base, project, stop_event):
        return {}
    result = {}
    if not root.is_dir():
        return result

    def cancelled():
        return stop_event is not None and stop_event.is_set()

    def load(source):
        if cancelled():
            return None
        try:
            data = fetch(source)
            return hashlib.sha256(data).hexdigest() + _suffix(data), data
        except FETCH_ERRORS:
            return None

    workers = min(4, max(1, workers), len(urls))
    pending = deque()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        sources = iter(urls)

        def submit():
            if not cancelled():
                try:
                    source = next(sources)
                except StopIteration:
                    return
                pending.append(pool.submit(load, source))

        for _ in range(workers):
            submit()
        i = 0
        while pending and not cancelled():
            try:
                entry = pending.popleft().result()
                if entry is not None:
                    name, data = entry
                    if not _store_one(root, name, data, stop_event):
                        break
                    result[i] = f"{base}/{name}"
                    del entry, data
            except OSError:
                pass
            finally:
                if progress is not None:
                    progress(i + 1, len(result))
            i += 1
            submit()
        for future in pending:
            future.cancel()
    return result


def _duration(seconds):
    seconds = int(seconds)
    minutes, seconds = divmod(seconds, 60)
    return f"{minutes} 分 {seconds:02d} 秒" if minutes else f"{seconds} 秒"


async def store_with_progress(urls, *, fetch, edit, stop_event=None, interval=4, workers=1):
    """Update the existing Telegram status, including during slow downloads or lock waits."""
    total = len(urls)
    state = (0, 0)
    started = time.monotonic()

    def report(done, stored):
        nonlocal state
        state = done, stored

    async def update(text):
        try:
            await edit(text)
        except Exception:
            logging.getLogger(__name__).debug("手機圖床進度訊息編輯失敗", exc_info=True)

    def progress_text():
        done, stored = state
        elapsed = time.monotonic() - started
        eta = (f"預估剩餘約 {_duration(max(1, round(elapsed * (total - done) / done)))}"
               if 3 <= done < total else "正在估算剩餘時間")
        filled = 10 * done // max(1, total)
        percent = 100 * done // max(1, total)
        bar = "█" * filled + "░" * (10 - filled)
        return (f"正在存入手機圖床\n已處理 {done}/{total} 張・已存 {stored} 張\n{bar} {percent}% · {done / max(0.1, elapsed):.2f} 張/s\n"
                f"已用 {_duration(elapsed)}・{eta}")

    await update(progress_text())
    job = asyncio.create_task(asyncio.to_thread(store_many, urls, fetch=fetch,
                                                stop_event=stop_event, progress=report, workers=workers))
    while not job.done():
        await asyncio.wait({job}, timeout=interval)
        if not job.done() and not (stop_event is not None and stop_event.is_set()):
            await update(progress_text())
    result = job.result()
    if stop_event is None or not stop_event.is_set():
        elapsed = _duration(time.monotonic() - started)
        remaining = total - len(result)
        detail = f"；剩餘 {remaining} 張交由備援流程處理。" if remaining else "。"
        await update(f"手機圖床已存 {len(result)}/{total} 張，用時 {elapsed}{detail}")
    return result

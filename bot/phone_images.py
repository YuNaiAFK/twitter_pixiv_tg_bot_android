"""Local-only writer for the phone's public image directory."""
import hashlib
import asyncio
import logging
import os
import shutil
import tempfile
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit

import httpx

MAX_STORAGE = 60_000_000_000
DISK_RESERVE = 2_000_000_000
_lock = threading.Lock()


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


def store_many(urls, *, fetch, stop_event=None, progress=None):
    """Return successful image URLs keyed by position; leave remaining images to the caller."""
    base = public_base()
    if not base or not urls:
        return {}
    root = Path(__file__).resolve().parent.parent / "data" / "public-images"
    # A successful HTTPS probe must reach this origin, not a generic CDN 404.
    try:
        response = httpx.get(base + "/healthz", timeout=6)
        if response.status_code != 204 or response.headers.get("X-Phone-Image-Host") != "ready":
            return {}
    except httpx.HTTPError:
        return {}
    import fcntl

    result = {}
    if not root.is_dir():
        return result
    with _lock, (root.parent / "phone-image-write.lock").open("a+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        used = sum(p.stat().st_size for p in root.iterdir() if p.is_file() and not p.is_symlink())
        for i, source in enumerate(urls):
            if stop_event is not None and stop_event.is_set():
                break
            tmp = None
            try:
                data = fetch(source)
                name = hashlib.sha256(data).hexdigest() + _suffix(data)
                target = root / name
                if target.is_symlink() or not target.is_file():
                    if used + len(data) > MAX_STORAGE or shutil.disk_usage(root).free < len(data) + DISK_RESERVE:
                        break
                    with tempfile.NamedTemporaryFile(dir=root, prefix=".incoming-", delete=False) as out:
                        tmp = Path(out.name)
                        out.write(data)
                    if stop_event is not None and stop_event.is_set():
                        break
                    tmp.replace(target)
                    used += len(data)
                result[i] = f"{base}/{name}"
            except (OSError, ValueError, httpx.HTTPError):
                continue
            finally:
                if tmp is not None:
                    tmp.unlink(missing_ok=True)
                if progress is not None:
                    progress(i + 1, len(result))
    return result


def _duration(seconds):
    seconds = int(seconds)
    minutes, seconds = divmod(seconds, 60)
    return f"{minutes} 分 {seconds:02d} 秒" if minutes else f"{seconds} 秒"


async def store_with_progress(urls, *, fetch, edit, stop_event=None, interval=4):
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
        return (f"正在存入手機圖床\n已處理 {done}/{total} 張・已存 {stored} 張\n"
                f"已用 {_duration(elapsed)}・{eta}")

    await update(progress_text())
    job = asyncio.create_task(asyncio.to_thread(store_many, urls, fetch=fetch,
                                                stop_event=stop_event, progress=report))
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

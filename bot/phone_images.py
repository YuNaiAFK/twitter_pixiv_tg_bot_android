"""Local-only writer for the phone's public image directory."""
import hashlib
import os
import shutil
import tempfile
import threading
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


def store_many(urls, *, fetch, stop_event=None):
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
    return result

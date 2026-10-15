"""
Everything the bot needs that differs between Windows and Android.

The core (``bot.py``, ``ehentai.py``, ``pixiv_login.py``, ``tag_translations.py``) is the same
file on both platforms. The differences are confined here, so the core stays portable and the
Windows build is untouched by Android work.

**This file is the Android half.** The Windows project keeps its own inline ``os.name``
branches; nothing here is imported there.

What actually differs, and why each one matters:

===========================  ==========================================================
``system_proxy_url``         Windows reads ``HKCU\\...\\Internet Settings`` from the
                             registry. Android has no such key, so the proxy comes from
                             the environment (Clash for Android sets none by default) or
                             from the usual ``HTTPS_PROXY`` variables.
``detached_interpreter``     On Windows the venv ``python.exe`` is a *launcher* that puts a
                             stray console window on screen. On Android there is no venv
                             launcher and no console, so ``sys.executable`` is right.
``spawn_replacement_process``Windows needs console-creation flags; POSIX needs none, and a
                             detached child should start its own session instead.
``instance_lock``            Windows uses ``msvcrt.locking``; POSIX uses ``fcntl.flock``.
``find_executable``          ``gallery-dl.exe`` on Windows, ``gallery-dl`` elsewhere.
``enable_utf8_console``      A Windows console code page. On Android stdout is already
                             UTF-8 and there is no console to reconfigure.
``admin_hint``               The operator advice names paths and commands that differ.
===========================  ==========================================================

Each function returns a value the core can use unchanged, or an empty/false value meaning
"this does not apply here", so the core needs one call rather than a branch.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

def _is_android() -> bool:
    """
    Whether this is Android, which is not the same question as "is this Linux".

    Checked by a file Android always has and a normal Linux box does not. ``os.name`` is
    ``"posix"`` on Android, so it cannot answer this - and the difference matters for the
    proxy, where Android has neither the Windows registry nor a system-wide environment.
    """
    return Path("/system/build.prop").exists() or bool(os.environ.get("ANDROID_ROOT"))


# Defined after the function above, not before it: a module-level call to something defined
# lower in the file is a NameError at import time, which took out the whole module the first
# time this was written.
PLATFORM = "android" if _is_android() else ("windows" if os.name == "nt" else "posix")


# -------------------- paths --------------------

#: Where the bot's own files live. Overridable so a chroot install can put state on shared
#: storage while the code lives in the chroot.
BASE_DIR = Path(os.environ.get("BOT_BASE_DIR") or Path(__file__).resolve().parent.parent)

#: Writable state. On Android this must be somewhere the app user can write; the project
#: directory inside a chroot qualifies, but ``/sdcard`` needs the storage permission and is
#: slow, so it is not the default.
DATA_DIR = Path(os.environ.get("BOT_DATA_DIR") or (BASE_DIR / "data"))


def ensure_data_dir() -> Path:
    """Create the state directory if it is missing, and return it."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    return DATA_DIR


# -------------------- proxy --------------------

#: Environment variables checked, in order, for an HTTP/SOCKS proxy.
_PROXY_ENV_VARS = (
    "BOT_PROXY",
    "TELEGRAM_PROXY",
    "ALL_PROXY",
    "all_proxy",
    "HTTPS_PROXY",
    "https_proxy",
    "HTTP_PROXY",
    "http_proxy",
)


def system_proxy_url() -> str:
    """
    The proxy to send requests through, or "" for a direct connection.

    **Android has no registry, so this cannot use the Windows path.** On a phone the proxy is
    normally Clash for Android or similar, which either sets no environment variable at all
    (its VPN mode intercepts transparently, and then nothing is needed here) or is configured
    by hand. ``BOT_PROXY`` is checked first because it is this project's own name and the one
    the README tells an operator to set.

    A transparent VPN needs no entry here: the traffic is already redirected, and setting a
    proxy on top of it would send it to a port that is not listening.
    """
    for name in _PROXY_ENV_VARS:
        value = (os.environ.get(name) or "").strip()
        if value:
            # A bare host:port is accepted and treated as SOCKS5, which is what Clash offers.
            if "://" not in value:
                return f"socks5://{value}"
            return value
    return ""


# -------------------- processes --------------------

def detached_interpreter() -> str:
    """
    The interpreter to start background processes with.

    ``sys.executable`` on Android: there is no venv launcher stub as on Windows, so the
    direct answer is also the correct one. The Windows reasoning - that ``.venv\\Scripts\\
    python.exe`` re-executes the real interpreter as a child and puts an empty console window
    on screen - does not apply here.
    """
    return sys.executable


def child_environment(**extra: str) -> dict[str, str]:
    """
    An environment for a child process.

    Android needs ``PYTHONPATH`` just as much as the Windows base-interpreter path does when
    the code lives outside the default ``sys.path`` (a chroot install, or a wrapper script
    that changed directory).
    """
    env = {**os.environ, **extra}
    parts = [p for p in env.get("PYTHONPATH", "").split(os.pathsep) if p]
    for path in sys.path:
        if path and path not in parts and Path(path).is_dir():
            parts.append(path)
    if parts:
        env["PYTHONPATH"] = os.pathsep.join(parts)
    return env


def detached_creation_flags() -> int:
    """
    Creation flags for a process that must outlive its parent.

    Zero, because none of the Windows flags exist on Android. ``start_new_session`` is the
    POSIX equivalent and is passed by the caller through ``Popen``; see
    ``start_detached`` for the whole thing in one place.
    """
    return 0


def start_detached(argv: list[str], *, cwd: Path | None = None) -> subprocess.Popen:
    """
    Start a process that keeps running after this one exits.

    On Android the equivalent of the Windows detachment flags is ``start_new_session=True``,
    which puts the child in its own session so it does not receive the terminal's signals.
    Output goes to ``DEVNULL`` because there is no console, and a pipe nobody reads would
    eventually block the child.
    """
    return subprocess.Popen(
        argv,
        cwd=str(cwd) if cwd else None,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
        env=child_environment(),
    )


def find_executable(explicit: str = "") -> str:
    """
    The gallery-dl command to run.

    ``gallery-dl`` on Android: installed with pip inside the same environment, so it is on
    ``PATH`` as a console script with no ``.exe`` suffix.
    """
    if explicit:
        return explicit
    found = shutil.which("gallery-dl")
    if found:
        return found
    # A pip install into the same interpreter always places it beside python, even when PATH
    # was not set up - which is common in a Termux session started by a service.
    candidate = Path(sys.executable).parent / "gallery-dl"
    if candidate.is_file():
        return str(candidate)
    return "gallery-dl"


# -------------------- console --------------------

def enable_utf8_console() -> bool:
    """
    Reconfigure the console for UTF-8. Returns whether anything was done.

    Nothing on Android: there is no console code page to change, and ``sys.stdout`` is
    already UTF-8. The core calls this unconditionally, so it has to exist and be harmless.
    """
    return False


# -------------------- operator hints --------------------

def admin_hint_tail() -> str:
    """
    The platform-specific end of an operator diagnosis.

    Names the real paths and the real command, because the Windows text points at
    ``.venv\\Scripts\\...``, which does not exist here - an operator following it would be
    sent to a file that is not there.
    """
    return (
        f"1) 重新整理憑證： gallery-dl oauth:pixiv\n"
        f"2) 把 code= 之後的值填入 .env 的 PIXIV_REFRESH_TOKEN\n"
        f"3) 驗證： {sys.executable} {BASE_DIR / 'bot' / 'bot.py'} --check"
    )


def platform_summary() -> str:
    """One line describing this deployment, for the startup log."""
    return f"平台：{PLATFORM}（{sys.platform}/{os.uname().machine if hasattr(os, 'uname') else '?'}）"

# twitter_pixiv_tg_bot — Android

The same Telegram parsing bot as the Windows project, built to run on an Android phone
instead of a PC. Send it an X/Twitter, Pixiv or e-hentai link and it returns the media.

Developed against a **rooted OnePlus 8 Pro on Pixel Experience 13** (AOSP 13, aarch64), but
nothing here is specific to that device.

## This is a separate project

The Windows project is **not modified by anything here**, and this one does not import from it.
They share the same core files by being copied:

| | Windows project | this project |
| --- | --- | --- |
| core (`bot.py`, `ehentai.py`, `pixiv_login.py`, `tag_translations.py`) | yes | yes — a copy |
| `run_local_api.py`, `host_proxy_relay.py`, `list_console_windows.py` | yes | **absent** |
| `verify_boot.py`, `socks5_transport.py`, `install_pillow_offline.py` | yes | **absent** |
| `run.bat`, `docker-compose.yml`, `harden_permissions.ps1` | yes | **absent** |
| launcher | `run.bat` | `scripts/run-bot.sh` |
| server | Docker + `run_local_api.py` | a Linux chroot + `scripts/run-server.sh` |

**The core files are copies, not a shared library.** If a bug is fixed in one, the same fix
has to be applied to the other. That is the price of the two projects being independent, and
it is why both keep the same characterisation suite: 423 checks here, 425 there, and the
difference is exactly the Windows-only assertions that cannot apply.

## What is different, and why

Everything platform-specific lives in `bot/platform_support.py` and in eight guarded spots in
the core. The reasons are worth knowing, because each one was a real failure on one platform:

| concern | Windows | Android |
| --- | --- | --- |
| **proxy** | read from `HKCU\...\Internet Settings` | **no registry**; environment only (`BOT_PROXY` first) |
| **interpreter for children** | `sys._base_executable`, because the venv launcher opens a stray console window | `sys.executable`; no launcher, no console |
| **detaching a process** | `DETACHED_PROCESS \| CREATE_NO_WINDOW` | `start_new_session=True` |
| **file locking** | `msvcrt.locking` | `fcntl.flock` |
| **gallery-dl name** | on `PATH` as `gallery-dl.exe` | no extension, beside the interpreter |
| **console encoding** | code page needs fixing | already UTF-8 |
| **operator advice** | names `.venv\Scripts\...` | names the real interpreter and directory |

`.env` is read from the **project root first**, then from `bot/`, so an operator edits one file
at the top level rather than hunting inside a package directory.

## Deploying it

### 0. Read the probe first

```bash
bash scripts/probe-device.sh
```

It changes nothing. It reports what the kernel actually offers — namespaces, cgroups,
overlayfs, SELinux state — and that output decides which path below is realistic. **Paste it
when asking for help.**

### 1. Install

In Termux:

```bash
pkg install git
git clone <this project> ~/twitter_pixiv_tg_bot
cd ~/twitter_pixiv_tg_bot
bash scripts/setup-termux.sh
```

That installs Python and the packages, creates `.env` from the example, and then **builds the
self-hosted Bot API server** inside a Debian chroot. The build is the slow part — **20 to 60
minutes on a phone**, and it compiles TDLib. Run it on a charger.

For a bot without the 2000 MB limit:

```bash
bash scripts/setup-termux.sh --no-server
```

### 2. Configure

Edit `.env` at the project root:

```
BOT_TOKEN=<from @BotFather>
ADMIN_USER_IDS=<your numeric id, from /id in the bot>
TELEGRAM_API_ID=<from my.telegram.org>
TELEGRAM_API_HASH=<from my.telegram.org>
TELEGRAM_API_BASE=http://127.0.0.1:8081
TELEGRAM_LOCAL=1
```

Put credential files in `cookies/` — `twitter.txt` and `ehentai.txt`, in **Netscape cookie
format**. `gallery-dl --cookies-from-browser` is deliberately not used: Android's kernel
blocks `ptrace` by default, so reading a browser's cookie database cannot work. Plain cookie
files are the only reliable route, and they are what this project has always used.

### 3. Run

```bash
bash scripts/run-bot.sh                 # foreground, Ctrl-C to stop
bash scripts/run-bot.sh --background    # survives the session ending
bash scripts/run-bot.sh --status
bash scripts/run-bot.sh --stop
```

```bash
bash scripts/run-server.sh start|stop|restart|status|logs
```

## About the two Android-only problems

**The CPU sleeping.** This is the single most common reason a phone-hosted bot "stops
working" — the process is alive and polling has silently stopped. `run-bot.sh` takes a Termux
wake lock on start and releases it on exit, including on a crash. Without `termux-api`
installed it warns rather than pretending.

**The system killing the process.** Android reclaims memory aggressively. Two things help:

- disable battery optimisation for Termux (Settings → Apps → Termux → Battery → Unrestricted)
- run it with `--background`, so it is not tied to a terminal that may be closed

A wake lock does not survive a reboot. To restart the bot automatically, use Termux:Boot and
put `bash ~/twitter_pixiv_tg_bot/scripts/run-bot.sh --background` in `~/.termux/boot/`.

## About the 2000 MB upload limit

Telegram's public API caps an upload at **50 MB**. A self-hosted Bot API server raises it to
**2000 MB**, and `TELEGRAM_LOCAL=1` makes the bot hand Telegram a *path* instead of uploading
bytes — which also removes the upload time entirely.

`MAX_UPLOAD_MB=45` is the default precisely so the bot works either way: without a server,
files stay inside the 50 MB public limit and nothing fails. With a server, raise it.

The server is one process listening on `127.0.0.1:8081`. **Proxy note:** on the Windows project
the server runs in Docker and needs a host relay to reach the proxy, because a container
cannot see loopback. In a chroot there is no such boundary, so **no relay is needed here** —
that is why `host_proxy_relay.py` has no Android equivalent.

If `BOT_PROXY` is unset and Clash for Android is running in **VPN mode**, leave it unset: the
traffic is already redirected, and pointing the bot at a proxy port would break a working
setup. Set `BOT_PROXY` only for Clash's *proxy mode* (a listening SOCKS port):

```
BOT_PROXY=127.0.0.1:7890
```

A bare `host:port` is accepted and treated as SOCKS5.

## What is not covered

- **Docker is not used and not required.** The probe reports whether this kernel could run it;
  the chroot path reaches the same 2000 MB without it. If the probe shows overlayfs and
  cgroups are present, Docker is an option, but this project does not depend on it.
- **`termux-api` is a separate install** for the wake lock. `pkg install termux-api` plus the
  Termux:API app from F-Droid.
- **The test suite runs on a desktop, not on the phone.** It needs `pytest`-free plain Python
  and takes minutes; on a phone it is easier to run it before copying changes across.


## The proxy form matters more than it looks

`apt` and `pip` **cannot use a SOCKS proxy**, and both report it in a way that blames something
else:

    $ apt-get update
    Unsupported proxy configured: socks5://127.0.0.1:10808
    E: The repository 'https://packages-cf.termux.dev/apt/termux-main stable Release'
       does not have a Release file.

That message names the **repository**, so it reads as a broken or unreachable mirror. Every
Termux mirror was in fact serving its Release file correctly - verified from a PC on the same
network, all five answering `200` with identical 13134-byte content - while `apt` failed on all
of them. The SOCKS line is the only real clue, and it appears **above** the error.

`pip` says it differently:

    ERROR: Could not install packages due to an OSError: Missing dependencies for SOCKS support.

pip needs PySocks to speak SOCKS, and installing PySocks needs pip. Neither message says "use
the HTTP form", which is the fix for both.

### What the bootstrap does now

| file | form | why |
| --- | --- | --- |
| `~/.proxy-url` | **HTTP** | what `apt` and `pip` need, and what `~/.bashrc` reads |
| `~/.proxy-url-socks` | SOCKS, if offered | for tools that prefer it |
| `apt.conf.d/95proxy` | **HTTP** | apt reads this file, not the environment, for its own transport |
| `http_proxy` / `all_proxy` in the shell | HTTP | so every child gets a usable form |

**`apt.conf.d/95proxy` outranks the environment variables**, so leaving a SOCKS value there
keeps breaking apt no matter what `.bashrc` says. That is exactly what happened here: changing
`.bashrc` and `~/.proxy-url` to HTTP changed nothing, because the file still held the old
value from the first run.

### If apt ever reports a missing Release file

Check the proxy before the mirror:

    cat $PREFIX/etc/apt/apt.conf.d/95proxy
    cat ~/.proxy-url

Both must say `http://`. A terminal-only fix is overwritten on the next run; the file is what
matters.

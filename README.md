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


## The self-hosted Bot API server on Android

Raises the upload limit from 50 MB to 2000 MB. The bot is the same either way; this is an
optional step, and until it is done `TELEGRAM_LOCAL` must stay `0`.

### What it takes

A Debian chroot through `proot-distro`, with `telegram-bot-api` compiled from source. TDLib is
the bulk of it: about **40 minutes** on an 8-core phone at `-j2`, plus ~1.1 GB for the rootfs
and build tree. The result is a 45 MB binary at
`$PREFIX/var/lib/proot-distro/containers/botapi/rootfs/usr/local/bin/telegram-bot-api`.

### The binary cannot be run directly

    $ .../containers/botapi/rootfs/usr/local/bin/telegram-bot-api
    cannot execute: required file not found

Its interpreter is `/lib/ld-linux-aarch64.so.1`, which is Debian's glibc loader. Android has
`/system/bin/linker64` instead. The message never mentions the loader, so it reads like a
missing file. It has to go through:

    proot-distro login botapi -- /usr/local/bin/telegram-bot-api ...

`run-server.sh` does this. It also tries both rootfs layouts, because **proot-distro 5.x moved
it** from `installed-rootfs/<name>` to `containers/<name>/rootfs` - checking only the old one
reported "binary missing" for a binary that was there.

`--dir` is validated with `realpath` and the server refuses to start unless the directory
already exists; it will not create it. `run-server.sh` creates it first, and passes its **chroot**
path (`/root/telegram-bot-api`), not its Termux path - `/data/data/com.termux/...` does not
exist inside the container.

### The loopback is shared

Measured from the Termux app: a listener started inside the chroot on `0.0.0.0:8099` accepted a
connection from Termux, so the bot reaches `127.0.0.1:8081` from outside the container without
any forwarding.

**Do not test this through `su`.** A process started with `su 10209` is in the SELinux domain
`u:r:magisk:s0`, where creating a socket fails with `PermissionError` / `socket: Permission
denied`. Every network test run that way reports a broken network. Three separate investigations
concluded "the VPN was killed", "the VPN is unreachable from the chroot" and "the chroot is
network-isolated" for exactly this reason, and all three were wrong. Network checks must run from
the Termux app.

### Building it

`proot-distro` needs **no root**: it implements chroot and mount with ptrace inside a userspace
process. `su` is actively harmful here, because it moves the process into a domain that cannot
read Termux's own directories.

The chroot does not inherit Termux's proxy configuration - it has its own apt - so
`setup-termux.sh` writes the HTTP proxy form into `apt.conf.d` inside the container and into
git's system config. The HTTP form is required: **apt rejects SOCKS outright** and reports it as
`does not have a Release file`, naming a repository that is working fine.

`PKG_CONFIG_PATH` must also be scrubbed. Left set, pkg-config answers with **Termux's** OpenSSL,
CMake records `-isystem /data/data/com.termux/files/usr/include`, and the build then compiles
Android/bionic headers with Debian's gcc - which fails inside `sqlite3.c` with errors about
`memccpy` and `strcasecmp`, files that have nothing to do with sqlite.

### Running it

    bash scripts/run-server.sh start|stop|status|restart|logs

Then in `.env`:

    TELEGRAM_API_BASE=http://127.0.0.1:8081
    TELEGRAM_LOCAL=1
    MAX_UPLOAD_MB=2000
    BOT_PROXY=http://127.0.0.1:10808

`BOT_PROXY` is worth setting even though the shell usually has one: the bot's own HTTP client
does not read the shell environment, and without it Twitter, Pixiv and e-hentai downloads fail.

### After a reboot

Both services have to come back, **server first**. `scripts/boot-services.sh` does that, waits
for the VPN, and waits for the server to bind before starting the bot. Install it with the
Termux:Boot app:

    mkdir -p ~/.termux/boot
    cp scripts/boot-services.sh ~/.termux/boot/10-bot.sh
    chmod +x ~/.termux/boot/10-bot.sh

Termux:Boot must be opened once after installation, and **both Termux and the VPN app must be
exempt from battery optimisation**, or Android kills them.


## Control panel

A local web page for starting, stopping and restarting the bot and the server, watching the log,
clearing the cache and editing `.env`, so the phone does not need a terminal for routine work.

    bash control/run-panel.sh start      # then open http://127.0.0.1:8090/
    bash control/run-panel.sh status
    bash control/run-panel.sh stop

In Chrome, **menu -> Add to Home screen** turns it into an app-like icon: the manifest sets
`display: standalone`, so it opens full screen with no address bar, and it works offline because
everything is served from inside the phone.

### It is a thin layer, deliberately

Every button shells out to `run-bot.sh` or `run-server.sh`. The panel does not reimplement
starting the bot, so it cannot drift out of step with what those scripts do - and whatever the
panel can do, the command line can still do when the panel is not running.

### Why it binds 127.0.0.1

The panel can read and write `.env`, which holds the bot token, and can start and stop the bot.
Reachable from the LAN without a password, that is a remote shell. It therefore binds loopback
and **refuses to listen anywhere else unless `--host` says so**, in which case a token is
generated and required on every request:

    bash control/run-panel.sh start              # loopback, no token
    PANEL_HOST=0.0.0.0 bash control/run-panel.sh start   # token printed, must be supplied

### Not part of the boot script

`~/.termux/boot/10-bot.sh` starts the bot and the server only. The panel is wanted when someone
is there to look at it; leaving an HTTP service running for no reason is a habit worth not
forming. Start it when needed.

### The guards that matter

  - **`.env` writes are validated and backed up.** A line without `=`, an illegal key name or a
    null byte is rejected, and the previous file is copied to `data/env-backups/` first (last 20
    kept). Line endings are forced to LF: a CRLF `.env` gives a value a trailing `\r`, which once
    made the server build fail with `Can't parse as an integer string "30753020"`.
  - **Cache clearing stays inside the project.** Each path is resolved and checked to be under
    the project root before removal, and only the contents of `.cache` are deleted, not the
    directory.
  - **The log is tailed, not loaded.** The file grows without bound, so it is read backwards in
    blocks; reading it in full on every poll would get slower every day.
  - **The bot's running state is not taken from the pid file alone.** A stale pid file is how the
    Stop button quietly stops working, so the process list is checked too.


## The Android control app

A native app for the same actions as the control panel: start, stop and restart the bot and the
server, watch the log, clear the cache. `app/` holds it; the APK is built with:

    powershell -File app/build.ps1            # -Install to also push it to the device
    powershell -File app/build.ps1 -Clean -Install

### It talks to the control panel, not to Termux

Starting the bot means running `run-bot.sh` inside Termux, and an ordinary app cannot do that:
`com.termux.RUN_COMMAND` requires `allow-external-apps=true` in Termux's properties, and reading
Termux's log directly is impossible because `/data/data/com.termux/files/home` is not readable by
another package. The panel already runs inside Termux and already exposes exactly these actions,
so it is the interface.

**The consequence is stated in the UI rather than hidden**: if the panel is not running the app
cannot do anything, and it shows a banner naming the command to start it instead of an empty
screen that looks broken.

    bash control/run-panel.sh start     # required before the app can do anything

### Built without Gradle

Gradle plus the Android Gradle Plugin is roughly 500 MB of downloads and a first build that
spends minutes resolving dependencies. This app is one activity with no library dependencies, so
`build.ps1` drives the toolchain underneath AGP directly: `aapt2` compile and link, `javac`, `d8`,
`zipalign`, `apksigner`. The APK is 37 KB.

The SDK it needs is 541 MB:

    sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

### Two traps that cost real time

**`d8` 8.2.2 crashes on anonymous inner classes compiled by javac 21.** Not on this class
specifically - a five-line `new Runnable() { ... }` reproduces it:

    Error in .../MainActivity$1.class:
    java.lang.NullPointerException: Cannot invoke "String.length()" because "<parameter1>" is null

A lambda compiles to `invokedynamic` with no `$1` class file, and a *named* nested class is
handled fine; only the anonymous form breaks. So there are no anonymous inner classes in this
app. The obvious replacement - a field initialised with a lambda that reschedules itself - does
not compile either, because Java rejects a field initialiser that refers to the field being
initialised. `this::pollOnce` avoids both problems.

**PowerShell turns a native command's stderr into a terminating error** when
`$ErrorActionPreference = "Stop"`. `keytool` writes its progress to stderr, so a *successful*
key generation aborted the build. `keytool` and `apksigner` are therefore invoked through
`cmd /c`, and by full path - going through `cmd` does not inherit PowerShell's PATH additions, so
a bare `apksigner` was "not recognized".


## The commands you have to run by hand: none

The app can start everything itself, so there is normally nothing to type in Termux.

Pressing **一鍵啟動服務** sends a `com.termux.RUN_COMMAND` intent, which makes Termux run
`scripts/start-all.sh` - the same script the boot script uses. The app then polls until the panel
answers and the card disappears on its own, so it also detects a command you ran by hand.

### The two things that must be in place

Both are set up once and survive; the app reports whichever is missing rather than appearing to do
nothing.

**1. Termux must allow external apps.** Without it the intent is refused:

    bash scripts/enable-external-apps.sh

**Termux must then be restarted** - it reads `~/.termux/termux.properties` once at startup. The
script says so when it finishes.

**2. The app must hold `com.termux.permission.RUN_COMMAND`.** It requests it at runtime; a fresh
install resets the grant, and adb can restore it without a dialog:

    adb shell pm grant com.yunai.botpanel com.termux.permission.RUN_COMMAND

### The trap that made this look like a permission problem

`startService` returned `null` and nothing happened, with the permission granted and the service
declared `exported=true`:

    W/ActivityManager: Unable to start service Intent { act=com.termux.RUN_COMMAND
      cmp=com.termux/.app.RunCommandService } U=0: not found
    startService returned null

"not found" for a service that exists. **Android 11 (API 30) package visibility**: an app sees only
its own packages unless it asks for more, so the service was invisible. The identical intent worked
from a root shell, because root is exempt from the filter - which is what sent the investigation
after permissions for several rounds.

The fix is three lines in the manifest:

    <queries>
        <package android:name="com.termux" />
    </queries>

`<queries>` rather than `QUERY_ALL_PACKAGES`: this app wants exactly one package and says so.
Visibility and permission are separate mechanisms, and only one of them was the problem.

### If it still does not work

Every card has a **顯示手動指令** button, which shows the commands to type. The same scripts are
reachable either way - the app is a convenience, not a replacement.

    bash ~/twitter_pixiv_tg_bot/scripts/start-all.sh          # everything, in order
    bash ~/twitter_pixiv_tg_bot/scripts/start-all.sh --status  # report only
    bash ~/twitter_pixiv_tg_bot/scripts/start-all.sh --restart # stop, then start


## Download the APKs

Everything needed is attached to the [latest release](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/latest):

| file | size | what it is |
| --- | --- | --- |
| `bot-panel.apk` | 45 KB | the control app, built from `app/` |
| `termux.apk` | 108.6 MB | Termux itself (0.118.3, the F-Droid build) |
| `termux-api.apk` | 3.8 MB | Termux:API - provides `termux-wake-lock` |
| `termux-boot.apk` | 25 KB | Termux:Boot - starts the services at boot |

    adb install -r bot-panel.apk
    adb install -r termux.apk
    adb install -r termux-api.apk
    adb install -r termux-boot.apk

**Termux itself is 108.6 MB**, which is over GitHub's 100 MB per-file limit for a repository file,
so it lives in the release rather than in `apk/`. The three smaller ones are in both places; see
[apk/README.md](apk/README.md).

Each release keeps the `bot-panel.apk` from that version, so an older build can still be
fetched if a newer one misbehaves. The three Termux APKs are identical in every release.

Two things an installer cannot do, both required before the app can start anything:

    adb shell pm grant com.yunai.botpanel com.termux.permission.RUN_COMMAND

and, once, from inside Termux:

    bash ~/twitter_pixiv_tg_bot/scripts/enable-external-apps.sh


## Stopping everything

The **電源 → 全部關閉（含面板）** button stops the bot, then the server, then the panel itself,
and reports what to do next. The panel's page has the same button.

It is in its own section, away from the other tools, because everything else on that screen is
recoverable from that screen - stop the bot and the button beside it starts it again. This one
ends the app's own usefulness, since the panel is what goes away last.

### Why the panel answers before it dies

The request arrives over HTTP and the panel is one of the things being stopped. Killing it while
still handling the request would close the socket before the response was written, and the app
would report a failure for an action that worked - the worst kind of feedback, because it invites
the user to press the button again.

So the work is handed to a **detached** process that waits two seconds, and the handler returns
immediately. Measured: the response arrives in 13 ms, the server is gone by the time it is read,
and the panel itself exits two seconds later.

`start_new_session=True` is what makes the child survive. Without it the child shares the panel's
session, killing the panel takes the child with it, and the bot and server are left running with
no panel to control them.

### Nothing is typed to get back

`POST /api/shutdown` is the same path as pressing the button, and recovery is the **一鍵啟動服務**
card, which sends `com.termux.RUN_COMMAND` and does not need the panel to be alive. Verified as a
full cycle: shut down, confirm every process and both ports are gone, then start again from the
intent alone.

    bash scripts/start-all.sh --stop      # the same thing from a terminal
    bash scripts/start-all.sh --status    # report only

`--stop` reverses the startup order for the mirror-image reason: the bot is stopped before the
server it depends on, and the panel goes last so a control surface exists until the very end.


## Credits

[CREDITS.md](CREDITS.md) lists every project this is built on - Termux and its companion apps,
proot-distro, the Python libraries, TDLib, the Android build tools - with a link to each
project's own page, the version that was in use, and what it does here.

These are the pages to go to if you are rebuilding this:

| | |
| --- | --- |
| Termux | <https://github.com/termux/termux-app> · <https://termux.dev> · [F-Droid](https://f-droid.org/packages/com.termux/) |
| Termux:API | <https://github.com/termux/termux-api> · [F-Droid](https://f-droid.org/packages/com.termux.api/) |
| Termux:Boot | <https://github.com/termux/termux-boot> · [F-Droid](https://f-droid.org/packages/com.termux.boot/) |
| python-telegram-bot | <https://github.com/python-telegram-bot/python-telegram-bot> · <https://python-telegram-bot.org> |
| gallery-dl | <https://github.com/mikf/gallery-dl> |
| httpx | <https://github.com/encode/httpx> |
| Pillow | <https://github.com/python-pillow/Pillow> |
| Telegram Bot API server | <https://github.com/tdlib/telegram-bot-api> |
| TDLib | <https://github.com/tdlib/td> |
| proot-distro | <https://github.com/termux/proot-distro> |
| Android SDK | <https://developer.android.com/studio#command-line-tools-only> |
| Eclipse Temurin JDK | <https://adoptium.net> |

Nothing here is bundled except the APKs in `apk/`, and this project is not affiliated with any of
those projects.


## Versioning

The app, the panel and the scripts carry **one version**, kept in
[`VERSION.properties`](VERSION.properties). The app shows its own version and the panel's side by
side in its header, both read from that one file, so a mismatch is visible instead of a mystery.

    powershell -File app/build.ps1 -Bump            # 1.3 -> 1.4   (a new feature)
    powershell -File app/build.ps1 -Bump -Fix       # 1.3 -> 1.3.1 (a fix only)
    powershell -File app/build.ps1                  # build at the current version

**Bump it whenever a feature changes.** `-Bump` rewrites `VERSION.properties` before building, so
a failed build still leaves the number bumped. The build also warns when the app's sources have
changed since the last bump - not an error, since rebuilding after a failure is legitimate, but
the reminder is the point.

[VERSIONS.md](VERSIONS.md) lists what each version contained and where the number is used.


## Publishing a release

**Create a new release. Never rename one, and never delete one.** A release is a published
artifact - someone may have downloaded it or be running it, and GitHub gives no undo.

[`tools/release.ps1`](tools/release.ps1) makes the right thing one command:

    ./tools/release.ps1 -List        # every release, its assets and download counts
    ./tools/release.ps1 -Verify      # check nothing is missing and /releases/latest is right
    ./tools/release.ps1 -Create      # publish the version in VERSION.properties

It contains **no code that renames or deletes a release**, and `-Create` refuses when the version
already has one. A tool that cannot express the request cannot make the mistake - and that mistake
was made once here, with a single `PATCH` that looked harmless.

Run `-Verify` after anything that touches releases. See
[VERSIONS.md](VERSIONS.md#publishing-a-release) for what each check covers and what the API does
if you go around the script.


## Versions

| version | release | what changed |
| --- | --- | --- |
| **1.3.1** | [v1.3.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.3.1) | a fix: 重新生成 crashed on any gallery whose cover had loaded. See below |
| **1.3** | [v1.3](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.3) | one version number for the manager; the stop-everything button |
| **1.0** | [v1.0](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.0) | first release |

Full history and the bump rules are in [VERSIONS.md](VERSIONS.md).

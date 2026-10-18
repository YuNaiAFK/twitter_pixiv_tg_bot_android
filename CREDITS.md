# Credits and upstream projects

Everything this project is built on, with a link to each project's own page and the version that
was actually in use when it was written. Nothing here is bundled except the three APKs in `apk/`;
everything else is fetched from these sources.

If you are rebuilding this, these are the pages to go to.

## Android applications

| project | page | version used | what it does here |
| --- | --- | --- | --- |
| **Termux** | <https://github.com/termux/termux-app> · <https://termux.dev> | 0.118.3 | the whole runtime - Python, the bot, the panel |
| **Termux:API** | <https://github.com/termux/termux-api> | 0.53.0 (`1002`) | `termux-wake-lock`, which keeps the CPU awake during long uploads |
| **Termux:Boot** | <https://github.com/termux/termux-boot> | 0.8.1 (`1000`) | runs `~/.termux/boot/10-bot.sh` at startup |
| **F-Droid** | <https://f-droid.org> | - | where those three are installed from |

**Install them from F-Droid, not the Play Store.** The Play Store Termux was deprecated and cannot
install the companion apps. F-Droid also verifies signatures and delivers updates.

    https://f-droid.org/packages/com.termux/
    https://f-droid.org/packages/com.termux.api/
    https://f-droid.org/packages/com.termux.boot/

Termux is **108.6 MB**, over GitHub's limit for a repository file, so it is attached to the
[latest release](../../releases/latest) instead of living in `apk/`. The other two are in both
places; see [apk/README.md](../apk/README.md).

## Termux packages

Installed by `scripts/setup-termux.sh` with `pkg install`.

| package | page | version used |
| --- | --- | --- |
| Python | <https://www.python.org> | 3.14.6 |
| pip | <https://pip.pypa.io> | 26.2.1 |
| Git | <https://git-scm.com> | 2.56.0 |
| Clang / LLVM | <https://clang.llvm.org> | 21.1.8 |
| GNU Make | <https://www.gnu.org/software/make> | 4.4.1 |
| proot-distro | <https://github.com/termux/proot-distro> | 5.10.0 |
| proot | <https://github.com/termux/proot> | 5.1.107.96 |
| libjpeg-turbo | <https://github.com/libjpeg-turbo/libjpeg-turbo> | for Pillow |
| libpng | <http://www.libpng.org> | for Pillow |
| FreeType | <https://freetype.org> | for Pillow |
| OpenSSL | <https://www.openssl.org> | for pip and httpx |

**proot-distro deserves a note**, because it is doing unusual work here: it installs a full Debian
userspace inside Termux without root, and `scripts/run-server.sh` uses it to run a Linux-only
aarch64 binary on Android. The loopback interface is shared with Termux, which is what lets the
bot reach the server on `127.0.0.1:8081`.

## Python libraries

Installed with `pip` into Termux's Python.

| library | page | version used | what it does here |
| --- | --- | --- | --- |
| **python-telegram-bot** | <https://github.com/python-telegram-bot/python-telegram-bot> · <https://python-telegram-bot.org> | 22.8 | the entire Telegram side |
| **httpx** | <https://github.com/encode/httpx> | 0.28.1 | all HTTP, including through the SOCKS proxy |
| **Pillow** | <https://github.com/python-pillow/Pillow> | 12.3.0 | reading image dimensions, building albums |
| **gallery-dl** | <https://github.com/mikf/gallery-dl> | 1.32.16 | used as a library for Pixiv and Twitter extraction |
| python-dotenv | <https://github.com/theskumar/python-dotenv> | - | reading `.env` |
| certifi | <https://github.com/certifi/python-certifi> | 2026.07.22 | CA bundle for httpx |

`gallery-dl` is GPLv2. This project does not redistribute it - `pip install` fetches it from PyPI -
but if you redistribute a bundled build, that licence applies to it.

## Tag translation data

| project | page | what it does here |
| --- | --- | --- |
| **EhTagTranslation/Database** | <https://github.com/EhTagTranslation/Database> | the 14,206-entry tag dictionary behind `bot/tag_translations.py` |
| **OpenCC** | <https://github.com/BYVoid/OpenCC> | Simplified to Traditional conversion, `s2twp` |
| **EHWiki** | <https://ehwiki.org> | the tag documentation that database translates |

**`bot/tag_translations.py` is a derived work and is licensed CC BY-NC-SA 3.0**, not under this
project's own terms. It is generated from the EhTagTranslation database by
[`tools/build_tag_translations.py`](tools/build_tag_translations.py); the upstream text is itself a
translation of EHWiki's tag pages, redistributed under the same licence and carrying the GNU Free
Documentation License for the descriptive text.

The non-commercial clause is what makes this compatible with a personal bot and incompatible with
selling access to it. If you run this commercially, that file is the one to look at.

**Two things the builder does that a text editor cannot**, both of which matter for what a reader
sees:

- converts Simplified to Traditional with OpenCC's ``s2twp`` rather than ``s2t``. Character mapping
  alone leaves ``打印机`` as 打印機 instead of 印表機 - vocabulary is part of a translation, not just
  characters.
- resolves the namespace conflict. The same raw name appears in several namespaces with different
  meanings: ``angel`` is 天使 as a female tag and 安吉爾 as a character, ``akagi`` is a kanmusu and
  also a surname. The bot looks a tag up by value alone, so one has to win - and it should be the
  descriptive tag, which appears on galleries of every kind, not a character name that happens to
  share the spelling.

**`artist` and `group` are deliberately not included.** They are 30,000 entries whose "translation" is
the Chinese spelling of a pen name - longer than the Roman one and not what anyone searches by.

## The self-hosted Bot API server

| project | page | what it does here |
| --- | --- | --- |
| **telegram-bot-api** | <https://github.com/tdlib/telegram-bot-api> | the local Bot API server on `127.0.0.1:8081` |
| **TDLib** | <https://github.com/tdlib/td> | what telegram-bot-api is built on |
| Telegram Bot API reference | <https://core.telegram.org/bots/api> | the API itself |

Both are under the **Boost Software License 1.0**.

**Why a local server at all:** Telegram's public API caps uploads at 50 MB. A self-hosted server on
the same machine accepts up to **2000 MB** and can be handed a *file path* instead of bytes, so a
large archive is never read into memory. That is the entire reason `TELEGRAM_LOCAL=1` exists in
`.env`.

The server is **compiled from source** by `scripts/setup-termux.sh`, inside the Debian chroot,
because TDLib needs a Linux toolchain. That is why proot-distro is here.

## Android build tools

Only needed to rebuild `app/bot-panel.apk`.

| tool | page | version used |
| --- | --- | --- |
| Android SDK command-line tools | <https://developer.android.com/studio#command-line-tools-only> | latest |
| Android platform-tools (`adb`) | <https://developer.android.com/tools/releases/platform-tools> | - |
| Android SDK Platform | <https://developer.android.com/about/versions/14> | android-34 |
| Android SDK Build-Tools | <https://developer.android.com/tools/releases/build-tools> | 34.0.0 |
| **D8 / R8** | <https://r8.googlesource.com/r8> | ships with build-tools 34.0.0 |
| **Eclipse Temurin JDK** | <https://adoptium.net> | 21.0.12 |

All Apache License 2.0 except the JDK, which is GPLv2 with the Classpath Exception.

`app/build.ps1` drives `aapt2`, `javac`, `d8`, `zipalign` and `apksigner` directly instead of
through Gradle, which avoids roughly 500 MB of Gradle and Android Gradle Plugin downloads for an
app with no library dependencies.

**D8 8.2.2 has a bug worth knowing about** if you rebuild: it crashes with an internal
`NullPointerException` on the class file `javac` 21 produces for an **anonymous inner class**. The
app has none for that reason; see the main README.

## Services this bot talks to

| service | page |
| --- | --- |
| Telegram | <https://telegram.org> |
| Telegraph | <https://telegra.ph> · <https://telegra.ph/api> |
| X (Twitter) | <https://x.com> |
| Pixiv | <https://www.pixiv.net> |
| E-Hentai | <https://e-hentai.org> · <https://exhentai.org> |
| Hentai@Home | <https://e-hentai.org/hentaiathome.php> |

**On `hath.network`**, which appears in the code: it is the Hentai@Home peer network that serves
E-Hentai's full-size images, and the bot resolves gallery links to it so that Telegraph gets
public URLs instead of ones that need a cookie. It is a content network, not a project with a
page - and its **HTTPS is broken** while HTTP works, which is why nothing links to it directly.
The link above is the project page for the software behind it.

**This project is not affiliated with any of them.** It reads pages the same way a browser does,
using your own cookies. Your use of each service is governed by that service's own terms - in
particular, E-Hentai's galleries require an account with sufficient GP, and Pixiv's refresh token
is tied to your account.

## The phone this was built and tested on

| | |
| --- | --- |
| device | OnePlus 8 Pro (`IN2020`), arm64-v8a |
| Android | 13 (SDK 33), Pixel Experience |
| root | Magisk |
| VPN | v2rayNG in proxy-only mode on `127.0.0.1:10808` |

Not a requirement - any arm64 Android with 4 GB free and a working proxy should do. It is recorded
because several of the problems in the README are specific to it, especially SELinux.

## Licence

This project's own code is in this repository. Everything above belongs to its authors under the
licence each project states.

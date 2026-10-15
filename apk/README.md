# APKs

Everything needed to put this project on a phone, kept here so a fresh machine does not have to
re-download all of it.

| file | size | what it is |
| --- | --- | --- |
| `bot-panel.apk` | ~40 KB | the control app built from `app/` in this repository |
| `termux-boot.apk` | ~25 KB | Termux:Boot - runs `~/.termux/boot/*.sh` at startup |
| `termux-api.apk` | ~3.8 MB | Termux:API - provides `termux-wake-lock`, which holds the CPU awake |

## Termux itself is not here, and why

`Termux` is **108.6 MB**, which is over GitHub's 100 MB per-file limit for a repository file, so it
cannot be committed. It is available from the projects that build it:

| app | source |
| --- | --- |
| Termux | <https://f-droid.org/packages/com.termux/> |
| Termux:API | <https://f-droid.org/packages/com.termux.api/> |
| Termux:Boot | <https://f-droid.org/packages/com.termux.boot/> |

**Install the F-Droid builds, not the Play Store ones.** The Play Store version was deprecated, and
it cannot install the companion apps.

The copies here are the F-Droid builds as downloaded during this project's setup:

| file | version | originally from |
| --- | --- | --- |
| `termux-api.apk` | 0.53.0 (`versionCode 1002`) | `https://f-droid.org/repo/com.termux.api_1002.apk` |
| `termux-boot.apk` | 0.8.1 (`versionCode 1000`) | `https://f-droid.org/repo/com.termux.boot_1000.apk` |

F-Droid remains the better source for those two as well - it verifies signatures and delivers
updates. They are included only so this repository is self-contained.

## Installing

    adb install -r bot-panel.apk
    adb install -r termux-api.apk
    adb install -r termux-boot.apk

`bot-panel.apk` needs two things that an installer cannot set up, both covered in the main
README:

    adb shell pm grant com.yunai.botpanel com.termux.permission.RUN_COMMAND

and, from inside Termux once:

    bash ~/twitter_pixiv_tg_bot/scripts/enable-external-apps.sh

**Rebuilding `bot-panel.apk`** produces a different signature only if `app/debug.keystore` is
removed; Android refuses to update an app in place when the signing key changes, so keeping that
file is what lets a rebuild install over the existing one.

# Versions

The bot manager - the Android app, the control panel and the scripts behind them - carries **one
version number**, kept in [`VERSION.properties`](VERSION.properties).

One number rather than three, because they ship together: a change in the panel and a change in
the app are the same release, and numbering them apart would let them drift into combinations
nobody tested. The app shows its own version and the panel's side by side, both read from that one
file, so a mismatch is visible rather than a mystery.

## The rule

**Bump it whenever a feature changes.**

| part | when |
| --- | --- |
| **Major** | something changes how it is used, or the panel API breaks so an old app cannot drive a new panel |
| **Minor** | a new feature, or a visible change in behaviour |
| **Patch** | a fix with no new capability |

    powershell -File app/build.ps1 -Bump            # 1.3 -> 1.4  (a feature)
    powershell -File app/build.ps1 -Bump -Fix       # 1.3 -> 1.3.1 (a fix)
    powershell -File app/build.ps1                  # build at the current version

`-Bump` rewrites `VERSION.properties` before building, so a failed build still leaves the number
bumped rather than half-applied. The build also **warns** when the app's sources have changed since
the last bump - not an error, because rebuilding after a failure is legitimate, but the reminder is
the point.

`versionCode` is Android's own counter and must increase every time: Android refuses to install an
APK whose `versionCode` is not greater than the installed one, so it is what makes
`adb install -r` work at all.

## Releases

| version | tag | what changed |
| --- | --- | --- |
| **1.3** | - | the version itself: shown in the app's header, reported by the panel, and one number for everything. `VERSION.properties` becomes the only place it is written, and `build.ps1 -Bump` maintains it |
| **1.2** | - | **全部關閉（含面板）** - stop the bot, the server and finally the panel. The panel answers before it exits, so the app sees success rather than a dropped connection |
| **1.1** | [v1.0 released before this](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.0) | the start-services card, so the app can start everything over `RUN_COMMAND` without anyone opening Termux. The log follows its newest line instead of sitting wherever it was |
| **1.0** | [v1.0](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.0) | first release: status cards, bot and server control, live log, clear cache, `.env` editor |

**The `v1.0` release tag predates this file.** Tags and the version in `VERSION.properties` are
separate things: the tag marks a published download, the version says what is inside any build.
From 1.3 on they are kept in step - a release is tagged `v<versionName>`.

## Where the number is used

| place | how it gets the number |
| --- | --- |
| `VERSION.properties` | the source, edited by `-Bump` |
| the APK's `versionName` / `versionCode` | `build.ps1` passes them to `aapt2 link` |
| the app's header | read from its own package metadata at runtime |
| the panel's `/api/status` | read from the same file at request time |
| the panel's own display | the app shows it beside its own version |

`AndroidManifest.xml` deliberately carries **no** `versionCode` or `versionName`, so there is
exactly one place the number lives and no way for the manifest and the file to disagree.

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

| version | release | what changed |
| --- | --- | --- |
| **1.3.1** | [v1.3.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.3.1) | **a fix, no new capability.** 重新生成 crashed on any gallery whose cover had loaded - `update_result_message` handed `link_preview_options` to both `edit_caption` and `edit_text`, and only the latter accepts it. `TypeError` is not a `TelegramError`, so it escaped the handler as 處理更新時發生未預期錯誤, eleven times in one log. The test doubles took `**kwargs` and so accepted what the real method refuses, which is why it shipped; they now enforce the installed library's signature |
| **1.3** | [v1.3](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.3) | the version itself: shown in the app's header, reported by the panel, one number for everything. `VERSION.properties` becomes the only place it is written and `build.ps1 -Bump` maintains it |
| **1.2** | - | **全部關閉（含面板）** - stop the bot, the server and finally the panel. Answered before it exits, so the app sees success rather than a dropped connection |
| **1.1** | - | the start-services card, so the app can start everything over `RUN_COMMAND` without anyone opening Termux. The log follows its newest line instead of sitting wherever it was |
| **1.0** | [v1.0](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.0) | first release: status cards, bot and server control, live log, clear cache, `.env` editor |

1.1 and 1.2 were never published as releases - they existed only as commits. Their changes are in
v1.3.

## Publishing a release

**Create a new release. Never rename one, and never delete one.**

A release is a published artifact. Someone may have downloaded it, linked to it, or be running it
right now. Renaming or deleting one breaks those links, and GitHub gives no undo. The downloads
and any discussion attached to it are gone.

[`tools/release.ps1`](tools/release.ps1) exists so that the right thing is one command and the
wrong thing is not expressible:

    ./tools/release.ps1 -List       # every release, its assets and their download counts
    ./tools/release.ps1 -Verify      # check nothing is missing and /releases/latest is correct
    ./tools/release.ps1 -Create      # publish the version in VERSION.properties
    ./tools/release.ps1 -Create -Draft

    # the one destructive operation, needing the tag and the name spelled out:
    ./tools/release.ps1 -ReplaceAsset bot-panel.apk -OnRelease v1.3

**The script contains no code that renames or deletes a release.** `-Create` refuses when the
version already has one, and says what to do instead. That is not politeness - a tool that cannot
express the request cannot make the mistake, and the mistake was made once here with a PATCH that
looked harmless.

### Why `apk/bot-panel.apk` is committed as well as attached

Every release keeps the `bot-panel.apk` built at that version, so an older build stays fetchable if
a newer one misbehaves - and so the build survives the release.

That is not hypothetical. When v1.0's release was lost, the tag still pointed at the old commit and
`apk/bot-panel.apk` was in the tree, so the exact APK could be restored from git history and
verified by hash after re-uploading:

    recovered from git:  948CF900BD63071D74D67A5E26A3A744A5A364787F99218E98FF34AA02526E07
    downloaded again:    948CF900BD63071D74D67A5E26A3A744A5A364787F99218E98FF34AA02526E07

A release is not a backup. It is a copy of something that also lives in the repository.

`-Verify` is worth running after anything that touches releases. It checks that every release still
has its four assets, that none of them is a truncated upload, that each release's tag still exists,
and that `/releases/latest` resolves to the version in `VERSION.properties`.

### What not to do, and why

| do not | what happens |
| --- | --- |
| `PATCH /releases/{id}` with `tag_name` | GitHub accepts it, moves the release, **and removes the old tag's release page.** This is how v1.0 was lost |
| `DELETE /releases/{id}` | irreversible; assets, download counts and links all go |
| `DELETE /releases/assets/{id}` without re-uploading | the release is left with a missing file, which `-Verify` will report |
| release with an existing `tag_name` **and** `target_commitish` | HTTP 422. The docs say `target_commitish` is ignored when the tag exists; the request is actually rejected |

If a release really must be withdrawn, mark it as a **pre-release** instead - it drops out of
`/releases/latest` and stays downloadable. Deleting is the last resort, not the first.

### Publishing by hand

The script is a convenience; the sequence it performs is:

    git tag -a v1.4 -m "..."           # tag first
    git push origin v1.4
    # POST /repos/{owner}/{repo}/releases  {"tag_name": "v1.4", ...}   # no target_commitish
    # upload each asset to uploads.github.com
    # PATCH /releases/{id}  {"make_latest": "true"}

**And one about `/releases/latest`, which the README links to.** It resolves by *publication
time*, not by version number:

    PATCH /releases/{id}  {"make_latest": "true"}     # say which one is newest

Rebuilding an old release gives it a newer `published_at` than the current one, so it silently
becomes "latest" and `/releases/latest` starts handing out the old build. That happened here:
recreating v1.0 to restore it made `latest` point at v1.0, so the README's download link would
have led anyone to the version from before the one-tap start existed. Set `make_latest` on the real
newest release after any rebuild, and check `/releases/latest` rather than assuming.

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

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
| **1.3** | [v1.3](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.3) | the version itself: shown in the app's header, reported by the panel, one number for everything. `VERSION.properties` becomes the only place it is written and `build.ps1 -Bump` maintains it |
| **1.2** | - | **全部關閉（含面板）** - stop the bot, the server and finally the panel. Answered before it exits, so the app sees success rather than a dropped connection |
| **1.1** | - | the start-services card, so the app can start everything over `RUN_COMMAND` without anyone opening Termux. The log follows its newest line instead of sitting wherever it was |
| **1.0** | [v1.0](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.0) | first release: status cards, bot and server control, live log, clear cache, `.env` editor |

1.1 and 1.2 were never published as releases - they existed only as commits. Their changes are in
v1.3.

## Publishing a release

**Create a new release. Never rename one.**

Each release carries the `bot-panel.apk` built at that version, so an older build stays fetchable
if a newer one misbehaves. The three Termux APKs are identical in every release and are re-uploaded
only so that each release stands alone.

    git tag -a v1.4 -m "..."
    git push origin v1.4
    # then POST /repos/{owner}/{repo}/releases with tag_name v1.4, and upload the assets

**Renaming a release's tag moves the release and deletes the old tag's release page.** The API
accepts `tag_name` on a PATCH and does exactly that, silently:

    PATCH /releases/{id}  {"tag_name": "v1.3"}     # v1.0's release page is now gone

That is how the v1.0 release was lost once. The tag itself survived - `refs/tags/v1.0` still
pointed at the old commit - so the release could be rebuilt, and its app APK recovered from git
history and verified by hash. It is why the build output is committed under `apk/` as well as
attached to the release.

Two more things about that API, both learned the hard way:

  - **`target_commitish` returns 422 when the tag already exists.** The documentation says it is
    ignored; in practice the request is rejected. Omit it once the tag is pushed, and pass it only
    when the release should create the tag.
  - **GitHub cannot replace an asset.** Updating one means DELETE, then POST the new file. The
    download URL keeps working because it is keyed by the release and the asset name.

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

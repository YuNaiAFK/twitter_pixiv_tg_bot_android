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
| **1.22.4** | [v1.22.4](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.22.4) | exviewer 結果新增取消，只隱藏按鈕、不改訊息。 |
| **1.22.3** | [v1.22.3](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.22.3) | exviewer 結果提供官方壓縮包下載，頻道發布規則不變。 |
| **1.22.2** | [v1.22.2](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.22.2) | 已授權群組可取用 exviewer，頻道發布仍僅限管理員私聊。 |
| **1.22.1** | [v1.22.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.22.1) | 頻道去重改用持久化增量索引，避免每次重讀歷史。 |
| **1.22** | [v1.22](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.22) | 管理員私聊優先取用 exviewer 的既有 EH 預覽，不帶轉發標頭，並確認是否發布至頻道。 |
| **1.21** | [v1.21](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.21) | Twitter／EH 發布至頻道前，檢查歷史訊息的來源與隱藏連結，重複則不發送。 |
| **1.20.3** | [v1.20.3](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.20.3) | 修正原標題建頁失敗：改以短網址建立後恢復原標題，保留全部圖片。 |
| **1.20.2** | [v1.20.2](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.20.2) | 恢復 Android 專用啟動路徑，保留 EH 快取、儲存重試與發布條件修正；請使用此版取代 1.20.1。 |
| **1.20.1** | [v1.20.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.20.1) | 修正 Telegraph 快取與儲存失敗重試，發布選項僅限顯示圖成功。 |
| **1.20** | [v1.20](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.20) | EH Telegraph 完成後獨立確認發布至 EH 頻道，與 Twitter 分開設定。 |
| **1.19** | [v1.19](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.19) | e-hentai Telegraph 僅保留雙標題與圖片，完成訊息改用第一頁大圖封面。 |
| **1.18** | [v1.18](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.18) | 新增 7z／RAR 圖片壓縮檔支援，私聊與群組入口同步辨識並串流解壓。 |
| **1.17** | [v1.17](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.17) | 本機檔案製作 Telegraph 限 bot 管理員，非管理員靜默且不顯示製作指令；一般連結解析不變。 |
| **1.16** | [v1.16](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.16) | Twitter 來源改為超連結文字；本機檔案製作沿用單則操作訊息，完成時原地轉成封面。 |
| **1.15** | [v1.15](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.15) | 群組以 /publish 回覆 ZIP／CBZ 啟動製作，沿用私聊設定與確認流程；直接圖片製作仍限私聊。 |
| **1.14** | [v1.14](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.14) | Telegraph 標題下方加入製作日期、自訂文字與連結，依發送者記憶並供下次自動套用。 |
| **1.13** | [v1.13](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.13) | 管理員私聊解析 X／Twitter 後可確認傳送到頻道，5 分鐘未操作預設不傳送；一般使用者不顯示按鈕。 |
| **1.12** | [v1.12](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.12) | 本機檔案製作限私聊，接收後先選擇是否上傳；作者、E站可各別設定超連結或保留普通文字。 |
| **1.11.1** | [v1.11.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.11.1) | 本機檔案完成訊息附上排序後第一張圖片作為封面，保留標題與即時預覽連結。 |
| **1.11** | [v1.11](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.11) | 新增本機圖片／ZIP／CBZ 上傳，使用 /publish 統一產生 1280px R2 圖片與依檔名排序的 Telegraph；支援取消、去重及失敗重試。 |
| **1.10.4** | [v1.10.4](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.10.4) | 補上 MTProto GIF 文件參照快取，重送不再重傳整檔；參照過期先刷新，必要時才重新上傳。 |
| **1.10.3** | [v1.10.3](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.10.3) | /grant 成功提示顯示五秒後自動刪除，只清除 bot 回覆；保留原始指令與寫入失敗警告。 |
| **1.10.2** | [v1.10.2](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.10.2) | 完整匿名管理員支援，並避免撤銷未授權群組時更動全域限制模式。 |
| **1.10.1** | [v1.10.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.10.1) | 辨識本群匿名管理員，支援不帶參數的 /grant 與 /revoke 管理本群授權；不授予全域管理權限。 |
| **1.10** | [v1.10](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.10) | Pixiv GIF 改用 MTProto，保留 .gif 檔名與內容，以一般文件 MIME 及強制文件旗標傳送；已由管理員實際確認桌面端顯示檔名、大小與下載按鈕。 |
| **1.9.2** | [v1.9.2](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.9.2) | Pixiv 文件模式改為直接依來源網址強制套用，不受呼叫端傳入的媒體類型參數影響，GIF 也固定走文件傳送。 |
| **1.9.1** | [v1.9.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.9.1) | Pixiv 的靜態圖片、GIF 與影片一律以文件傳送，ZIP 合成後的 GIF 及快取重送也相同；關閉自動媒體類型偵測。文件相簿重試仍保留檔名與文件模式；GIF 文件過大時回報失敗，保留原始尺寸。 |
| **1.9** | [v1.9](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.9) | 訊息自動清理只刪除 bot 的處理提示；R2 上傳失敗時通知並自動重試，三輪失敗後讓使用者選擇繼續或停止，停止後中止該次 e-hentai 解析；相同內容不重複上傳。Pixiv 檔名改為「作品名稱_作品ID_p頁碼_畫師ID_畫師暱稱」，並修正 Ugoira ZIP 被忽略的問題：依影格資料轉為原始尺寸、完整影格的 GIF 後直接傳送，支援新格式快取。完整說明見 [v1.9 更新說明](docs/releases/v1.9.md)。 |
| **1.8** | [v1.8](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.8) | **the tag dictionary is regenerated from a database that is current to the day**, and a gallery now shows its present tags rather than a cached set.  
**Dictionary:** 14,206 → **14,324** entries. Upstream [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database) was cloned at HEAD `4f4ab9d` (2026-11-03) and re-parsed: 118 new tags, 19 translation corrections, none removed. The corrections are the interesting half - `epsilon` was 伊普西龍 and is now 艾普西隆, `cid kagenou` was 暗影 and is now 希德·卡蓋諾（暗影）, because upstream maps the name rather than the alias.  
**And the build tool was broken against a fresh clone.** Upstream moved the tables into a `database/` subdirectory; the tool still read them from the repository root and raised `FileNotFoundError: _ehtags/character.md`. It now accepts either layout, because the layout is theirs to change and a month-old checkout still uses the old one.  
**Tags themselves were stale for a different reason**, fixed in the same release: the metadata cache was six hours, so a gallery edited minutes ago kept its previous tag list - measured in the log as `命中畫廊快取（2853 秒前）`, forty-seven minutes, no refresh. `GALLERY_META_TTL_SECONDS` now defaults to 0 - every parse re-reads the facts - while the sweep, the Telegraph page and the R2 URLs are still reused, which is where the time actually goes |
| **1.7** | [v1.7](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.7) | **the 梯子 card stopped lying about a working VPN.** It said 未設定 in red while FlClash was running in TUN mode and every download worked, because `proxy_state()` read `~/.proxy-url` and stopped - a file the v2rayNG bootstrap writes, which FlClash does not use and TUN mode does not need, since the tunnel redirects every packet and a proxy setting would *break* it. **Three states now, and only one of them is a fault:** `proxy` (a local proxy that is listening), `tun` (a VPN tunnel exists - working, nothing to tell the tools), `none` (neither, and downloads will fail). The old code could only express one working state, so a healthy TUN setup was painted red.  
**Detecting the tunnel took three attempts, and the first two are worth recording.** `/sys/class/net` is the obvious answer and is denied - as are `/proc/net/dev`, `/proc/net/route` and `socket.if_nameindex()` - inside `u:r:untrusted_app_27`, which is the domain the panel and every RUN_COMMAND script run in. `ifconfig -a` ships with Termux and asks the kernel through ioctl instead of those files, so it works: it even warns "cannot open /proc/net/dev (Permission denied). Limited output" and then lists tun0 correctly anyway. Cached for 30 s so the app's polling does not spawn a process every time.  
Also fixed: the panel on the phone was still v1.5 and reported that version next to the app's own, because `VERSION.properties` had never been deployed - the same omission as in 1.5, found the same way |
| **1.6** | [v1.6](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.6) | **the e-hentai reply is a tag list now, and the dictionary behind it is real.** One line per namespace - `語言: #漢語`, `女性: #獸耳 #蘿莉 #褲襪` - then the title, the source link and the rating. The table went from 410 hand-written entries to **14,206** generated from [EhTagTranslation/Database](https://github.com/EhTagTranslation/Database), converted Simplified to Traditional with OpenCC's `s2twp` rather than `s2t` (character mapping alone leaves 打印机 as 打印機 instead of 印表機). The hand-written table had facts wrong, not just omissions: `touhou` when e-hentai calls it `touhou project`, `anal` rendered as 肛交 when e-hentai splits it into `anal` (爆肛) and `anal intercourse` (肛交).  
**The Telegraph page is now embedded in the 預覽 line** - the title itself is the link - so the separate `📄 Telegraph：<url>` block is gone. That needed HTML parse mode, which the bot had never used, and therefore escaping on every field. **And the label follows the fact:** `名稱` when there is no page yet, because the first reply is a menu and calling that line 預覽 promises something that cannot be clicked.  
**A security pass that found 25 real vulnerabilities.** `pip-audit` against the phone's installed set: Pillow 12.3.0 carried 24 CVEs, one CRITICAL - a heap overflow in `ImagingJpegDecode` reached through `Image.thumbnail()` -> `draft()`, which is this bot's exact code path, with attacker-controlled input. certifi shipped a root whose intermediate keys were compromised and revoked. Both upgraded, Pillow built from source on the phone. Then a second layer: `Image.open(formats=...)` so the EPS/XBM/PDF decoders - where those bugs cluster and which this bot never needs - are never entered at all, because `Image.open` dispatches on magic bytes and a file named `.jpg` beginning with `%!PS` would otherwise reach Ghostscript.  
**`/audit`**, so the same check can be run from a phone: administrator-only, no new dependency (it queries OSV directly, which is what pip-audit queries), 22 packages in 2.3 seconds. A failed check says so rather than rendering as 沒有發現已知漏洞 - that is the one mistake that matters there.  
Also: the adult-content notices are gone, the log's leftover thread dumps are cleaned out, and the README was rewritten in Traditional Chinese with a section on the image host it never mentioned |
| **1.5** | [v1.5](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.5) | **the app and the panel show how full the R2 image host is.** A card with the used and total, what remains, the object count and a bar that goes amber at 80% and red at the ceiling - because "8.9 GB / 10 GB" in neutral white does not say whether that is a problem, and the reason to show a quota at all is to see how close it is. The panel reads the bucket itself (cached for a minute, since the app polls every few seconds) and reports a *state* rather than a figure when it cannot: a confident "0 GB used" while the bucket is unreachable is a number someone would act on, and clearing space that is not short costs them their images. Also fixed: the panel never loaded `.env` into its environment, so it reported a bucket the bot was actively uploading to as unconfigured |
| **1.4** | [v1.4](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.4) | **page images are copied into Cloudflare R2, so they stop expiring.** e-hentai's embedded links are signed with a keystamp and every image on a page fails together when it lapses - which is what 重新生成 existed to work around. An object in R2 has no such link. Four things went with it: **the regenerate path now hosts on R2 too**, which it did not, so pressing the button used to rebuild the page with fresh links that expired again hours later; **the Telegraph · 原圖 mode is removed**, because it embedded the full-resolution files - about 2 GB per gallery, uploaded to R2 - to show what the display page already shows, and 歸檔 is how the originals are obtained; **a cached page is verified by reading the page's own images**, every one of them rather than a three-URL sample that called a page healthy if a single URL loaded; and **`.env` paths are resolved against the project directory**, which is what made `/cache clear` refuse the cache's real location |
| **1.3.1** | [v1.3.1](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.3.1) | **a fix, no new capability.** 重新生成 crashed on any gallery whose cover had loaded - `update_result_message` handed `link_preview_options` to both `edit_caption` and `edit_text`, and only the latter accepts it. `TypeError` is not a `TelegramError`, so it escaped the handler as 處理更新時發生未預期錯誤, eleven times in one log. The test doubles took `**kwargs` and so accepted what the real method refuses, which is why it shipped; they now enforce the installed library's signature |
| **1.3** | [v1.3](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.3) | the version itself: shown in the app's header, reported by the panel, one number for everything. `VERSION.properties` becomes the only place it is written and `build.ps1 -Bump` maintains it |
| **1.2** | - | **全部關閉（含面板）** - stop the bot, the server and finally the panel. Answered before it exits, so the app sees success rather than a dropped connection |
| **1.1** | - | the start-services card, so the app can start everything over `RUN_COMMAND` without anyone opening Termux. The log follows its newest line instead of sitting wherever it was |
| **1.0** | [v1.0](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/tag/v1.0) | first release: status cards, bot and server control, live log, clear cache, `.env` editor |

1.1 and 1.2 were never published as releases - they existed only as commits. Their changes are in
v1.3.

先前未發布的 1.8.1 訊息清理修正已併入 v1.9。

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

# v1.23

- EH 解析優先掃描已設定的 EH 頻道，相同連結直接無來源複製既有結果。
- 共用發布查重的增量索引；未命中或讀取失敗仍走 exviewer／正常解析。
- 保留官方壓縮包、取消按鈕與僅限管理員私聊的頻道發布選項。

# v1.23.1

- EH 命中既有頻道結果後，隱藏該頻道的傳送按鈕。
- 沒有其他可發布頻道時，不再額外傳送發布提示。

# v1.23.2

- EH 一般選單五分鐘未操作，自動刪除 bot 選單訊息。
- 從頻道或 exviewer 取得的解析，五分鐘未操作只隱藏按鈕並保留內容。
- 授權使用者按過按鈕即取消計時；不影響原始連結與進行中的停止／R2 重試按鈕。

# v1.23.3

- EH 訊息來自綁定頻道（含討論群自動轉貼）或 @exviewer_bot 時，靜默略過。
- 比對 Telegram 的原始來源、發送者及 inline bot；不以訊息文字猜測來源。
- 在授權提示、冷卻及解析之前攔截，不產生回覆。

# v1.24

- Twitter 敏感貼文的圖片、影片及 GIF 使用 Telegram 遮罩。
- 分級隨快取保存，相簿與降級重試保留遮罩；未知分級與舊快取也加遮罩。
- 無法以遮罩發送時提示略過，不降級成未遮罩文件；Pixiv 文件模式不變。

# v1.24.1

- 單檔解析直接修改第一則進度訊息成媒體／文件，包含 Pixiv GIF 及快取結果。
- 多檔保留相簿及原有文件形式，成功後移除進度訊息，不再另發完成通知。
- 保留遮罩、原檔名、MTProto 文件快取及頻道發布；部分失敗仍保留必要提示。

# v1.24.2

- 修復單檔編輯原訊息時的 `media not found`：正確設定 multipart 附件參照。
- 新增圖片、影片、動畫與文件的實際請求序列化檢查。

# v1.24.3

- 沿用 exviewer 前檢查 Telegraph 頁面及全部內嵌圖片。
- 頁面失效、無圖片、壞圖、逾時或檢查失敗時，改走原本 EH 解析，不傳送失效預覽。

# v1.25

- Telegraph 製作及重新生成排除兩份已確認畫廊的廣告頁。
- 2051305/d1969d0ee2：第 36～41 頁；2000612/54a53baa2d：第 38～42 頁。
- 先過濾再上傳 R2；略過這兩份的頻道及 exviewer 結果，舊頁快取於下次製作更新。
- 僅限已確認畫廊，不是泛用圖片廣告辨識；官方壓縮包內容不變。

# v1.25.1

- 僅有 other:extraneous ads（外部廣告）標籤時才啟用已確認頁面排除。
- 無標籤時不過濾圖片，也不因廣告規則略過頻道／exviewer 既有結果。
- 過濾狀態隨快取記錄，標籤移除後下次製作會恢復完整頁面。

# v1.26

- 重寫 EH 去廣告：僅含外部廣告標籤時，以已確認圖片樣本及本機 OCR 判斷，不再按畫廊 ID／固定頁碼刪除。
- 三份已確認廣告共 18 個圖片特徵；真實畫廊 3650545 驗證保留 26 頁、排除第 27～33 頁。
- 圖片檢查失敗、無可靠候選或刪除比例異常時，R2 上傳前停止，避免再次發布未確認結果。
- Windows 與 Termux 使用 Tesseract；中英文官方模型及授權隨專案附上，Termux 安裝腳本加入相應依賴。

# v1.26.1

- 外部廣告辨識僅檢查末段最多 10 張圖片；第 1～3 張一律不取圖、不辨識、不排除。
- 無外部廣告標籤、或作品只有三張以下時，不進行廣告圖片檢查。

# v1.26.2

- 修復廣告檢查讀取已過期圖片網址時的 HTTP 403 失敗。
- 來源回傳 401／403／404／410 時，強制刷新圖片清單並再檢查一次；仍失敗就停止，不上傳、不建頁。
- 維持只檢查末十張、前三張保留及外部廣告標籤門檻。

# v1.26.3

- 修復 exviewer 的 Telegraph 圖片使用 /file/... 相對網址時，被誤判為沒有圖片的問題。
- 支援根目錄相對、路徑相對及協定相對的圖片來源；仍檢查圖片有效性並排除不安全格式。

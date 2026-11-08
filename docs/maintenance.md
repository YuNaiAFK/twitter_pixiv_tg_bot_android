# 維護與疑難排解（Android）

[回到 README](../README.md)

- [快取策略](#快取策略)
- [R2 圖床與免費額度](#r2-圖床與免費額度)
- [標籤翻譯](#標籤翻譯)
- [e-hentai 解析流程](#e-hentai-解析流程)
- [疑難排解](#疑難排解)
- [Android 特有的問題](#android-特有的問題)
- [套件漏洞檢查](#套件漏洞檢查)
- [更新標籤字典](#更新標籤字典)
- [版本與發佈](#版本與發佈)
- [編輯 PowerShell 腳本](#編輯-powershell-腳本)
- [兩個專案的關係](#兩個專案的關係)
- [致謝](#致謝)
- [授權](#授權)

## 快取策略

**這裡只有一件事值得記住：便宜的事每次重做，昂貴的事才複用。**

| 資料 | 成本 | 策略 |
| --- | --- | --- |
| 標題、tag、評分 | **1 個請求** | **每次都重讀**（`GALLERY_META_TTL_SECONDS=0`）|
| 掃描到的圖片網址 | **每頁 1 個，50 頁 = 50 個** | 2 小時（`GALLERY_URL_TTL_SECONDS`）|
| Telegraph 頁面網址 | 建立一個新頁面 | 永久，直到條目過期 |
| R2 圖片網址 | 每張重新計算雜湊 | 永久，直到條目過期 |
| Twitter／Pixiv 檔案 | 重新下載 | 14 天（`CACHE_STALE_SECONDS`）|
| 官方歸檔 ZIP | 幾十 MB 的下載 | 8 GB 上限內 |

> **這一層分開是有代價換來的。** 原本 `CACHE_STALE_SECONDS`（14 天）管整個 payload，
> 所以 e-hentai 上編輯過的 tag 要**兩週**才會出現。改成 6 小時的 metadata TTL 之後仍然不夠 ——
> log 顯示一本 47 分鐘前快取的本子（`命中畫廊快取（2853 秒前）`）照樣顯示舊標籤。
> **省下的是「一個請求」，而代價是一個錯誤的答案，那不是節省。**

**畫廊的頁面圖片從來不存到本機** —— 解析時每一張直接串流到 R2。
`.cache` 裡的檔案全部屬於 Twitter／Pixiv；e-hentai 只有官方歸檔會落在磁碟上。

## R2 圖床與免費額度

e-hentai 的內嵌圖片網址是用 `keystamp` 簽章的，**時效一過，整個頁面的圖片會一起失效** ——
這正是「重新生成」按鈕存在的理由。

**圖片會被複製到 Cloudflare R2**，那裡的物件沒有這種時效。頁面上的網址因此變成
`https://img.example.com/...`，不會再過期。

**上傳前會用 SHA-256 內容雜湊檢查重複檔案**。相同內容即使檔名、副檔名不同，也會沿用既有 R2 網址；
舊版帶副檔名的物件同樣會被辨識。同一批或不同畫廊同時出現相同圖片時，也會共用物件。
新物件使用 `galleries/ab/cd/<sha256>`，並以 [R2 條件式上傳](https://developers.cloudflare.com/r2/api/s3/api/#conditional-operations)
防止其他程序同時建立相同檔案。無法完成重複檔案檢查時，會交給自動重試流程處理。

**R2 免費額度是每月 10 GB 儲存空間**（對外流量免費、讀取在額度內免費），
所以儲存是唯一可能產生帳單的部分。一本畫廊的顯示圖約 **30 MB**，大約可以放三百本。

**上限設在額度的 95%（9.5 GB），而不是額度本身。** 儲存是按月、按物件存在的時間計費，
所以剛好用到 10 GB、一週後才刪掉，那個月仍然超額。

兩道檢查，因為它們回答不同的問題：

| 時機 | 檢查 | 為什麼 |
| --- | --- | --- |
| **下載任何東西之前** | 桶裡已經存了多少 | 已經滿了就**直接拒絕** —— 抓 30 MB 下來才決定不上傳是浪費 |
| **每張圖片上傳前** | 已存 + 這張是否超額 | 第一道無法知道要上傳多少 —— 那只有下載了才知道 |

**檢查在寫入之前執行** —— 已經上傳的就是已經計費的。

用量是**詢問桶本身**，不是本地計數器：本地計數在你第一次從 Cloudflare 儀表板刪東西時就會漂移。
讀不到用量或圖片上傳失敗時，機器人會自動重試；每次只重傳失敗的圖片。連續失敗 3 次後，
會詢問發起解析的使用者要停止本次 e-hentai 解析，或再重試 3 次。選擇停止後不會繼續建立 Telegraph 頁面；
15 分鐘未選擇時，也會停止本次解析。

額度用完時會通知管理員，因為達到上限是代替操作者做的決定，而結果是頁面少了一些圖片。

**App 與面板都會顯示目前用量** —— 已用／總量、剩餘、物件數，以及一條 80% 轉黃、達到上限轉紅的進度條。

## 標籤翻譯

e-hentai 的標籤會翻譯成繁體中文（台灣）：

```
語言: #漢語 #翻譯
原作: #絕區零
角色: #貓宮又奈 #哲_|_華茲
藝術家: #nito
女性: #貓女 #黑皮 #獸耳 #蘿莉
```

**14,324 條**，由 [`tools/build_tag_translations.py`](../tools/build_tag_translations.py) 從
[EhTagTranslation/Database](https://github.com/EhTagTranslation/Database) 產生。
目前對應上游 commit `4f4ab9d`（2026-11-03）。

**兩個轉換都是必要的：**

1. **簡體轉繁體用 `s2twp` 而不是 `s2t`。** `s2t` 只映射字符，所以「打印机」會變成「打印機」而不是
   「印表機」—— **字符轉換不是翻譯。** `s2twp` 連詞彙一起轉，那才是台灣實際讀到的東西。
2. **圖示標記會被剝掉。** 名稱欄可能是 `![贝合图标](https://...)贝合`，直接切分會把 img 標籤
   留在變成 hashtag 的字串中間。

**artist 與 group 刻意不收。** 那兩者有 30,000 條，而它們的「翻譯」是筆名的羅馬拼音 ——
`endou hiroto` 變成「遠藤弘土」，沒有人會那樣搜尋，而且比原本的字串更長。
其餘十個命名空間才是讀者真正受益於中文的部分。

**同一個名字在不同命名空間有不同意思** —— `angel` 是女性的「天使」也是角色的「安吉爾」。
機器人只用值查表，所以只能留一個，而留的應該是**通用的描述性標籤**，不是剛好同名的角色名。
因此最特定的（character）先解析、最通用的（female）最後 —— **最後寫入的勝出。**

**要更新字典見[更新標籤字典](maintenance.md#更新標籤字典)。**

## e-hentai 解析流程

```
使用者傳連結
   │
   ├─ 讀 metadata（1 個請求）        ← 每次都重讀，tag 才會是新的
   │
   └─ 回覆四個按鈕
        │
        ├─ 瀏覽（Telegraph）
        │    ├─ 掃描每一頁的圖片網址     ← 貴，快取 2 小時
        │    ├─ 上傳到 R2                ← 可停止
        │    └─ 建立／更新 Telegraph 頁面
        │
        ├─ 歸檔（縮圖／原圖）
        │    ├─ 向 e-hentai 要官方 ZIP 連結
        │    ├─ 下載（分段並行，可停止）   ← 快取 8 GB 內
        │    └─ 上傳到 Telegram
        │
        └─ 重新生成
             └─ 檢查頁面圖片是否還活著，壞掉就修，原連結不變
```

**「重新生成」保留原連結**，因為它的目的就是修復那個連結裡的圖片，
而不是產生一個新的東西讓使用者重新分享。

**同一本再送一次會沿用既有的頁面** —— 這就是 `GALLERY_CACHE` 存在的理由，
關掉它會讓第二次送出產生第二個頁面。

## 疑難排解

| 症狀 | 先檢查什麼 |
| --- | --- |
| **圖片顯示不出來** | 按「重新生成」。keystamp 過期了 |
| **tag 不更新** | 確認 `GALLERY_META_TTL_SECONDS=0`，看 log 有沒有「畫廊資料已過期」|
| **中文標籤不對或缺** | 更新字典，見[更新標籤字典](maintenance.md#更新標籤字典) |
| **停止按鈕沒反應** | 面板會顯示「目前沒有進行中的下載」嗎？那代表當時沒有可停的工作 |
| **下載全部失敗在 `Connection refused`** | 梯子切成 TUN 了，把 `BOT_PROXY` 註解掉 |
| **`apt` 說找不到 Release 檔** | 檢查 `apt.conf.d/95proxy` 是不是 `http://` |
| **App 顯示「找不到面板」** | `bash control/run-panel.sh start` |
| **App 的按鈕按了沒反應** | 權限與 `allow-external-apps` 都設好了嗎？（見[手機 App](setup.md#手機-app)）|
| **機器人開機後死掉** | 梯子當時還沒起來。看 log 有沒有「等待 Telegram」 |
| **面板的「梯子」顯示紅字** | 真的沒有 VPN 隧道也沒有代理埠 —— 開梯子 |

## Android 特有的問題

### CPU 休眠

這是手機版機器人「停止運作」最常見的原因 —— 行程還活著，但輪詢已經悄悄停了。
`run-bot.sh` 啟動時會向 Termux 取得喚醒鎖定，結束時釋放（包含當掉的情況）。
沒有安裝 `termux-api` 時它會**警告**，而不是假裝成功。

### 系統殺掉行程

Android 會積極回收記憶體。兩件事有幫助：

- 對 Termux 關閉電池最佳化（設定 → 應用程式 → Termux → 電池 → 不受限制）
- 用 `--background` 執行，這樣它不會綁在可能被關掉的終端機上

### 喚醒鎖定不會撐過重新開機

用 Termux:Boot，把 `bash ~/twitter_pixiv_tg_bot/scripts/boot-services.sh` 放進 `~/.termux/boot/`。

**而且開機時網路通常還沒好** —— 梯子需要幾秒到一分鐘。`boot-services.sh` 會等，
機器人本身也會用 `wait_for_telegram()` 確認 Telegram 真的連得上，**才宣告自己啟動**。
這修掉了一個真實的故障：開機時 VPN 還沒起來，機器人啟動後死於 `telegram.error.TimedOut`，
而 log 卻說「機器人已啟動」。

### 平台差異來自真實的失敗

所有平台相關的程式碼都集中在 `bot/platform_support.py`，以及核心裡八個有防護的點：

| 項目 | Windows | Android |
| --- | --- | --- |
| **代理** | 從 `HKCU\...\Internet Settings` 讀取 | **沒有登錄檔**；只讀環境變數 |
| **子行程的解譯器** | `sys._base_executable`，因為 venv 啟動器會多開一個主控台視窗 | `sys.executable` |
| **分離行程** | `DETACHED_PROCESS \| CREATE_NO_WINDOW` | `start_new_session=True` |
| **檔案鎖定** | `msvcrt.locking` | `fcntl.flock` |
| **gallery-dl 名稱** | `gallery-dl.exe` 在 `PATH` 上 | 沒有副檔名，放在解譯器旁邊 |
| **主控台編碼** | 需要修正代碼頁 | 已經是 UTF-8 |

## 套件漏洞檢查

**管理員指令 `/audit`。** 把目前裝的每一個套件拿去問 [OSV](https://osv.dev)
（`pip-audit` 背後查的同一個資料庫），回報有問題的套件、修復版本，以及可以直接複製的升級指令。

```
🔍 套件漏洞檢查

檢查 22 個套件，沒有發現已知漏洞。

資料來源：OSV（https://osv.dev）
```

有問題時：

```
檢查 22 個套件，發現 2 個已知漏洞：

• certifi 2026.7.22 — 2 個
  修復於 2026.10.19
  GHSA-6q48-6c7w-9gw2, PYSEC-2026-4320

升級方式（在 Termux 執行）：
python -m pip install -U certifi
```

**不裝新依賴。** `pip-audit` 是開發工具、自帶依賴樹，而它查的就是 OSV —— 所以這裡直接用 bot 已經有的
`httpx` 查。健康的安裝只花**一個**請求（`querybatch`），只有真的有問題才會多抓細節。

**失敗與乾淨是兩回事。** 查不到（代理掛掉、OSV 連不上）會明確說「這不代表沒有漏洞」，
不會回一句看起來很安心的「沒有發現漏洞」—— 那是這裡唯一真正要避免的錯誤。

## 更新標籤字典

```bash
# 1. 取得上游資料庫
git clone --depth 1 https://github.com/EhTagTranslation/Database.git ../_ehtags

# 2. 重新產生
python tools/build_tag_translations.py
```

輸出會列出每個命名空間的條數、新增與變更的數量。

> **這個工具曾經對全新的 clone 是壞的。** 上游把表格搬進了 `database/` 子目錄，
> 而工具還讀根目錄，於是 `FileNotFoundError: _ehtags/character.md`。
> **所以「更新字典」其實很久沒跑過 —— 不是沒更新，是跑不動。**
>
> 現在兩種佈局都接受，因為佈局是上游專案的事，而上個月的 checkout 還是舊的。

改完記得同步到另一個專案（見[兩個專案的關係](maintenance.md#兩個專案的關係)），然後升版。

## 版本與發佈

App、面板與腳本**共用一個版本號**，記錄在 [`VERSION.properties`](../VERSION.properties)。
App 的標題列會把自己的版本與面板的版本並排顯示，**所以版本不一致是可見的，而不是謎團。**

```powershell
powershell -File app/build.ps1 -Bump            # 1.8 -> 1.9   （新功能）
powershell -File app/build.ps1 -Bump -Fix       # 1.8 -> 1.8.1 （只有修正）
powershell -File app/build.ps1                  # 用目前版本建置
```

**只要功能有變動就升版。** `-Bump` 會在建置**之前**改寫 `VERSION.properties`，
所以建置失敗時版本號仍然是升過的。

[VERSIONS.md](../VERSIONS.md) 列出每個版本包含什麼。

### 發佈 release

> ### **建立新的 release。永遠不要改名，永遠不要刪除。**
>
> Release 是已發佈的產物 —— 可能有人已經下載或正在跑它，而且 **GitHub 沒有復原功能。**

```powershell
./tools/release.ps1 -List        # 每個 release、它的資產與下載次數
./tools/release.ps1 -Verify      # 檢查有沒有缺東西、/releases/latest 對不對
./tools/release.ps1 -Create      # 發佈 VERSION.properties 裡的版本
```

**它裡面沒有任何會改名或刪除 release 的程式碼**，而且 `-Create` 在該版本已經有 release 時會拒絕。
**一個無法表達那個請求的工具，就不可能犯那個錯** —— 而那個錯這裡犯過一次，
用的是單一個看起來無害的 `PATCH`。

**任何動到 release 的操作之後，請執行 `-Verify`。**

Android 功能或行為修改完成後，除了提交並推送 `main`，也要升版、重新建置 APK、將產物同步到 `apk/bot-panel.apk`，更新 `VERSIONS.md` 與繁體中文更新說明，再建立對應版本的 Release 並執行 `-Verify`。上傳完成後確認 `/releases/latest` 指向新版，並核對附件的版本、大小與 SHA-256；連接手機時也要同步程式、版本檔與 APK。只有原始碼提交完成，尚未建立新版 Release，不算完成 Android 發佈。

## 編輯 PowerShell 腳本

> ### **`app/build.ps1` 與 `tools/release.ps1` 必須保留 UTF-8 BOM。**

Windows PowerShell 5.1 —— 也就是 `powershell` 執行的那個 —— 會把沒有 BOM 的 `.ps1` 當成 ANSI 讀取。
檔案裡如果有破折號、省略號或任何中文，就會被逐位元組解碼成系統代碼頁，而**失敗不是外觀問題**：

```
The string is missing the terminator: ".
Missing closing '}' in statement block or type definition.
```

**指著完全正確的行。** `pwsh` 跑同一個檔案卻很高興，因為 PowerShell 7 預設讀 UTF-8，
**所以這個錯誤會一直活到有人用 `powershell` 為止。**

```bash
python tools/check_encodings.py          # 驗證
python tools/check_encodings.py --fix    # 修復
```

**任何改寫這些檔案的工具都可能弄掉 BOM** —— Python 裡一個普通的 `Path.write_text(..., "utf-8")` 就會。

## 兩個專案的關係

**Windows 是主專案，Android 是移植版本。** 兩者各自執行，不在執行時互相匯入；共用功能須在兩個專案同步維護：

| | Windows 專案 | 本專案 |
| --- | --- | --- |
| 核心（`bot.py`、`ehentai.py`、`pixiv_login.py`、`tag_translations.py`）| 有 | 有 —— 複製品 |
| `run_local_api.py`、`host_proxy_relay.py`、`run.bat`、Docker | 有 | **沒有** |
| 啟動器 | `run.bat` | `scripts/run-bot.sh` |
| 伺服器 | Docker + `run_local_api.py` | Linux chroot + `scripts/run-server.sh` |

> **核心檔案是複製品，不是共用函式庫。** 在一邊修好的 bug，另一邊必須手動套用同樣的修正。
> 兩邊都保留同一套特性測試正是為了這件事 —— **Android 482 項、Windows 468 項**，
> 差的那幾項是無法套用的平台專屬斷言。

## 致謝

[CREDITS.md](../CREDITS.md) 列出了本專案建立的每一個專案 —— Termux 與它的 companion apps、
proot-distro、Python 函式庫、TDLib、Android 建置工具 —— 附上各自專案頁面的連結、
當時使用的版本，以及它在這裡做什麼。

| | |
| --- | --- |
| Termux | <https://github.com/termux/termux-app> · <https://termux.dev> · [F-Droid](https://f-droid.org/packages/com.termux/) |
| Termux:API | <https://github.com/termux/termux-api> · [F-Droid](https://f-droid.org/packages/com.termux.api/) |
| Termux:Boot | <https://github.com/termux/termux-boot> · [F-Droid](https://f-droid.org/packages/com.termux.boot/) |
| python-telegram-bot | <https://github.com/python-telegram-bot/python-telegram-bot> · <https://python-telegram-bot.org> |
| gallery-dl | <https://github.com/mikf/gallery-dl> |
| httpx | <https://github.com/encode/httpx> |
| Pillow | <https://github.com/python-pillow/Pillow> |
| Cloudflare R2（boto3）| <https://developers.cloudflare.com/r2/> · <https://github.com/boto/boto3> |
| **EhTagTranslation/Database** | <https://github.com/EhTagTranslation/Database> |
| **OpenCC** | <https://github.com/BYVoid/OpenCC> |
| Telegram Bot API server | <https://github.com/tdlib/telegram-bot-api> |
| TDLib | <https://github.com/tdlib/td> |
| proot-distro | <https://github.com/termux/proot-distro> |
| Android SDK | <https://developer.android.com/studio#command-line-tools-only> |
| Eclipse Temurin JDK | <https://adoptium.net> |

**除了 `apk/` 裡的 APK 之外，這裡沒有任何東西是打包進來的**，本專案也不隸屬於上述任何專案。

## 授權

本專案自己的程式碼沒有宣告授權條款。

> **`bot/tag_translations.py` 是衍生作品，授權為 CC BY-NC-SA 3.0**，不是本專案自己的條款。
> 它由 [`tools/build_tag_translations.py`](../tools/build_tag_translations.py) 從 EhTagTranslation 資料庫產生
> （14,324 筆），上游文本本身又是 EHWiki 標籤頁面的翻譯，以相同授權再散布。
>
> **非商業條款正是它與個人使用相容、與拿來收費不相容的原因。**

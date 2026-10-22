# twitter_pixiv_tg_bot — Android

與 Windows 專案相同的 Telegram 解析機器人，但改成跑在** Android 手機**上而不是電腦。
傳給它 X/Twitter、Pixiv 或 e-hentai 的連結，它會回傳媒體檔案。

本專案在**已 root 的 OnePlus 8 Pro（Pixel Experience 13，AOSP 13，aarch64）**上開發，
但程式碼本身沒有任何一處綁定這台裝置。

---

## 目錄

- [這是獨立專案](#這是獨立專案)
- [功能與平台差異](#功能與平台差異)
- [部署](#部署)
  - [0. 先跑探測腳本](#0-先跑探測腳本)
  - [1. 安裝](#1-安裝)
  - [2. 設定](#2-設定)
  - [3. 執行](#3-執行)
- [Android 特有的兩個問題](#android-特有的兩個問題)
- [關於 2000 MB 上傳上限](#關於-2000-mb-上傳上限)
- [代理的格式比看起來重要](#代理的格式比看起來重要)
- [自架 Bot API 伺服器](#自架-bot-api-伺服器)
- [控制面板](#控制面板)
- [Android 控制 App](#android-控制-app)
- [必須手動執行的指令：沒有](#必須手動執行的指令沒有)
- [下載 APK](#下載-apk)
- [全部關閉](#全部關閉)
- [套件漏洞檢查：`/audit`](#套件漏洞檢查audit)
- [圖片圖床與免費額度](#圖片圖床與免費額度)
- [致謝](#致謝)
- [版本](#版本)
- [發佈 release](#發佈-release)
- [編輯 PowerShell 腳本](#編輯-powershell-腳本)

---

## 這是獨立專案

**Windows 專案不會被這裡的任何東西改動**，本專案也不從它匯入任何東西。兩者靠**複製**共用同一份核心檔案：

| | Windows 專案 | 本專案 |
| --- | --- | --- |
| 核心（`bot.py`、`ehentai.py`、`pixiv_login.py`、`tag_translations.py`） | 有 | 有 —— 複製品 |
| `run_local_api.py`、`host_proxy_relay.py`、`list_console_windows.py` | 有 | **沒有** |
| `verify_boot.py`、`socks5_transport.py`、`install_pillow_offline.py` | 有 | **沒有** |
| `run.bat`、`docker-compose.yml`、`harden_permissions.ps1` | 有 | **沒有** |
| 啟動器 | `run.bat` | `scripts/run-bot.sh` |
| 伺服器 | Docker + `run_local_api.py` | Linux chroot + `scripts/run-server.sh` |

> **核心檔案是複製品，不是共用函式庫。** 在一邊修好的 bug，另一邊必須手動套用同樣的修正。
> 這是兩個專案各自獨立的代價，也是兩邊都保留同一套特性測試的原因 —— 這裡 423 項、那邊 425 項，
> 差的那兩項正好是無法套用的 Windows 專屬斷言。
> （目前：Android 475 項、Windows 462 項。）

---

## 功能與平台差異

所有平台相關的程式碼都集中在 `bot/platform_support.py`，以及核心裡八個有防護的點。理由值得知道，
因為每一項都對應一次真實的失敗：

| 項目 | Windows | Android |
| --- | --- | --- |
| **代理** | 從 `HKCU\...\Internet Settings` 讀取 | **沒有登錄檔**；只讀環境變數（`BOT_PROXY` 優先） |
| **子行程的解譯器** | `sys._base_executable`，因為 venv 啟動器會多開一個主控台視窗 | `sys.executable`；沒有啟動器、沒有主控台 |
| **分離行程** | `DETACHED_PROCESS \| CREATE_NO_WINDOW` | `start_new_session=True` |
| **檔案鎖定** | `msvcrt.locking` | `fcntl.flock` |
| **gallery-dl 名稱** | 在 `PATH` 上叫 `gallery-dl.exe` | 沒有副檔名，放在解譯器旁邊 |
| **主控台編碼** | 需要修正代碼頁 | 已經是 UTF-8 |
| **給操作者的提示** | 指向 `.venv\Scripts\...` | 指向真正的解譯器與目錄 |

`.env` **先讀專案根目錄**，再讀 `bot/`，所以操作者只要編輯最上層那一個檔案，不必進到套件目錄裡找。

---

## 部署

### 0. 先跑探測腳本

```bash
bash scripts/probe-device.sh
```

**它不會改變任何東西。** 它只回報核心實際提供什麼 —— namespace、cgroup、overlayfs、SELinux 狀態 ——
而那份輸出決定下面哪一條路徑可行。**遇到問題時請把它貼出來。**

### 1. 安裝

在 Termux 裡：

```bash
pkg install git
git clone <本專案> ~/twitter_pixiv_tg_bot
cd ~/twitter_pixiv_tg_bot
bash scripts/setup-termux.sh
```

這會安裝 Python 與相關套件、從範例建立 `.env`，然後**在 Debian chroot 裡建置自架的 Bot API 伺服器**。
建置是最慢的部分 —— **手機上要 20 到 60 分鐘**，而且會編譯 TDLib。**請插著電源跑。**

如果不需要 2000 MB 上限：

```bash
bash scripts/setup-termux.sh --no-server
```

### 2. 設定

編輯專案根目錄的 `.env`：

```
BOT_TOKEN=<向 @BotFather 取得>
ADMIN_USER_IDS=<你的數字 id，在 bot 裡用 /id 取得>
TELEGRAM_API_ID=<向 my.telegram.org 取得>
TELEGRAM_API_HASH=<向 my.telegram.org 取得>
TELEGRAM_API_BASE=http://127.0.0.1:8081
TELEGRAM_LOCAL=1
```

把登入憑證放進 `cookies/` —— `twitter.txt` 與 `ehentai.txt`，格式為 **Netscape cookie**。

> **刻意不使用 `gallery-dl --cookies-from-browser`。** Android 核心預設封鎖 `ptrace`，
> 所以讀取瀏覽器的 cookie 資料庫根本不可能運作。純 cookie 檔案是唯一可靠的方式，
> 也是本專案一直以來使用的方式。

### 3. 執行

```bash
bash scripts/run-bot.sh                 # 前景執行，Ctrl-C 停止
bash scripts/run-bot.sh --background    # 關掉工作階段也不會停
bash scripts/run-bot.sh --status
bash scripts/run-bot.sh --stop
```

```bash
bash scripts/run-server.sh start|stop|restart|status|logs
```

---

## Android 特有的兩個問題

**CPU 休眠。** 這是手機版機器人「停止運作」最常見的原因 —— 行程還活著，但輪詢已經悄悄停了。
`run-bot.sh` 啟動時會向 Termux 取得喚醒鎖定，結束時釋放（包含當掉的情況）。
沒有安裝 `termux-api` 時它會**警告**，而不是假裝成功。

**系統殺掉行程。** Android 會積極回收記憶體。兩件事有幫助：

- 對 Termux 關閉電池最佳化（設定 → 應用程式 → Termux → 電池 → 不受限制）
- 用 `--background` 執行，這樣它不會綁在可能被關掉的終端機上

**喚醒鎖定不會撐過重新開機。** 要讓機器人自動重啟，請用 Termux:Boot，
把 `bash ~/twitter_pixiv_tg_bot/scripts/run-bot.sh --background` 放進 `~/.termux/boot/`。

---

## 關於 2000 MB 上傳上限

Telegram 公開 API 的單次上傳上限是 **50 MB**。自架 Bot API 伺服器可以提高到 **2000 MB**，
而 `TELEGRAM_LOCAL=1` 讓機器人把**路徑**交給 Telegram 而不是上傳位元組 —— 連上傳時間都省掉了。

`MAX_UPLOAD_MB=45` 是預設值，正是為了讓機器人在兩種情況下都能運作：沒有伺服器時，
檔案維持在 50 MB 公開上限內，不會有任何東西失敗。有伺服器時再把它調高。

伺服器是一個監聽 `127.0.0.1:8081` 的行程。

> **代理注意事項：** Windows 專案的伺服器跑在 Docker 裡，需要一個主機轉送才能連到代理，
> 因為容器看不到 loopback。在 chroot 裡沒有這種邊界，所以**這裡不需要任何轉送** ——
> 這就是 `host_proxy_relay.py` 沒有 Android 對應版本的原因。

如果 `BOT_PROXY` 沒有設定，而 Clash for Android 跑在 **VPN 模式**，**就讓它保持未設定**：
流量已經被重新導向了，把機器人指向代理埠反而會弄壞一個能用的設定。
只有在 Clash 的**代理模式**（一個監聽中的 SOCKS 埠）才需要設定：

```
BOT_PROXY=127.0.0.1:7890
```

單獨的 `host:port` 會被接受，並當作 SOCKS5 處理。

### 沒有涵蓋的部分

- **不使用 Docker，也不需要 Docker。** 探測腳本會回報這個核心能不能跑它；
  chroot 路徑不用它也能達到同樣的 2000 MB。如果探測結果顯示有 overlayfs 與 cgroup，
  Docker 是一個選項，但本專案不依賴它。
- **`termux-api` 需要另外安裝**（為了喚醒鎖定）。`pkg install termux-api`，
  再加上 F-Droid 上的 Termux:API 應用程式。
- **測試套件在桌機上跑，不在手機上跑。** 它需要不依賴 `pytest` 的純 Python，
  而且要跑幾分鐘；在手機上，先跑完再複製變更過去會比較容易。

---

## 代理的格式比看起來重要

`apt` 與 `pip` **都不能用 SOCKS 代理**，而且兩者回報錯誤的方式都會把責任推給別的東西：

```
$ apt-get update
Unsupported proxy configured: socks5://127.0.0.1:10808
E: The repository 'https://packages-cf.termux.dev/apt/termux-main stable Release'
   does not have a Release file.
```

那段訊息點名的是**儲存庫**，所以讀起來像是鏡像站壞了或連不上。但實際上**每一個 Termux 鏡像
都在正常提供它的 Release 檔** —— 從同一網段的電腦驗證過，五個全部回 `200`、內容都是
13134 位元組 —— 而 `apt` 對每一個都失敗。**那行 SOCKS 才是唯一的線索，而它在錯誤訊息的上面。**

`pip` 的說法不一樣：

```
ERROR: Could not install packages due to an OSError: Missing dependencies for SOCKS support.
```

pip 需要 PySocks 才能講 SOCKS，而安裝 PySocks 又需要 pip。**兩則訊息都沒有說「改用 HTTP 格式」，
而那正是兩者的解法。**

### 啟動腳本現在做的事

| 檔案 | 格式 | 原因 |
| --- | --- | --- |
| `~/.proxy-url` | **HTTP** | `apt` 與 `pip` 需要的格式，也是 `~/.bashrc` 讀的 |
| `~/.proxy-url-socks` | SOCKS（若有提供） | 給偏好 SOCKS 的工具 |
| `apt.conf.d/95proxy` | **HTTP** | apt 為自己的傳輸讀這個檔案，而不是讀環境變數 |
| shell 裡的 `http_proxy` / `all_proxy` | HTTP | 讓每個子行程都拿到可用的格式 |

**`apt.conf.d/95proxy` 的優先順序高於環境變數**，所以在那裡留著 SOCKS 值，
不管 `.bashrc` 怎麼寫都會繼續讓 apt 失敗。這正是這裡發生過的事：把 `.bashrc` 與 `~/.proxy-url`
改成 HTTP 完全沒用，因為那個檔案還留著第一次執行時的舊值。

### 如果 apt 又說找不到 Release 檔

**先檢查代理，再檢查鏡像站：**

```bash
cat $PREFIX/etc/apt/apt.conf.d/95proxy
cat ~/.proxy-url
```

兩者都必須是 `http://`。**只在終端機裡修正會被下一次執行覆蓋掉；那個檔案才是關鍵。**

---

## 自架 Bot API 伺服器

把上傳上限從 50 MB 提高到 2000 MB。機器人本身兩種情況都一樣；這是選用步驟，
**在完成之前 `TELEGRAM_LOCAL` 必須保持 `0`。**

### 需要什麼

透過 `proot-distro` 的 Debian chroot，加上從原始碼編譯的 `telegram-bot-api`。
TDLib 佔了大半：在 8 核心手機上用 `-j2` 大約 **40 分鐘**，另外 rootfs 與建置目錄約需 1.1 GB。
結果是 `$PREFIX/var/lib/proot-distro/containers/botapi/rootfs/usr/local/bin/telegram-bot-api`
一個 45 MB 的執行檔。

### 這個執行檔不能直接跑

```
$ .../containers/botapi/rootfs/usr/local/bin/telegram-bot-api
cannot execute: required file not found
```

它的解譯器是 `/lib/ld-linux-aarch64.so.1`，那是 Debian 的 glibc 載入器。Android 用的是
`/system/bin/linker64`。**訊息從來沒提到載入器，所以讀起來像是檔案不見了。** 它必須透過：

```
proot-distro login botapi -- /usr/local/bin/telegram-bot-api ...
```

`run-server.sh` 就是做這件事。它也會嘗試兩種 rootfs 佈局，因為 **proot-distro 5.x 把它搬走了** ——
從 `installed-rootfs/<name>` 移到 `containers/<name>/rootfs`。只檢查舊路徑的話，
會對一個明明存在的執行檔回報「binary missing」。

`--dir` 會用 `realpath` 驗證，而且伺服器在目錄不存在時**拒絕啟動 —— 它不會幫你建立**。
`run-server.sh` 會先建立它，並傳入它的 **chroot** 路徑（`/root/telegram-bot-api`），
而不是 Termux 路徑 —— `/data/data/com.termux/...` 在容器裡並不存在。

### loopback 是共用的

從 Termux 應用程式實測：在 chroot 裡啟動一個監聽 `0.0.0.0:8099` 的服務，
Termux 可以連上它，所以機器人從容器外面連 `127.0.0.1:8081` 不需要任何轉送。

> ### ⚠️ 不要透過 `su` 測試這件事
>
> 用 `su 10209` 啟動的行程會落在 SELinux 網域 `u:r:magisk:s0`，在那裡建立 socket 會失敗，
> 回報 `PermissionError` / `socket: Permission denied`。**每一個用這種方式跑的網路測試都會回報網路壞了。**
>
> 三次獨立的調查分別得出「VPN 被殺了」、「VPN 從 chroot 連不到」、「chroot 被網路隔離」的結論，
> 全都是因為這個原因，而且**三次都錯了**。網路檢查必須從 Termux 應用程式執行。

### 建置它

`proot-distro` **不需要 root**：它在使用者空間行程裡用 ptrace 實作 chroot 與 mount。
`su` 在這裡反而有害，因為它會把行程移到一個讀不到 Termux 自己目錄的網域。

chroot 不會繼承 Termux 的代理設定 —— 它有自己的 apt —— 所以 `setup-termux.sh` 會把 HTTP 代理格式
寫進容器內的 `apt.conf.d`，以及 git 的系統設定。**HTTP 格式是必要的：apt 直接拒絕 SOCKS**，
並回報成 `does not have a Release file`，點名一個運作正常的儲存庫。

`PKG_CONFIG_PATH` 也必須清掉。留著的話，pkg-config 會回答 **Termux 的** OpenSSL，
CMake 會記下 `-isystem /data/data/com.termux/files/usr/include`，然後建置就會用 Debian 的 gcc
去編譯 Android/bionic 的標頭檔 —— 結果在 `sqlite3.c` 裡失敗，錯誤訊息是 `memccpy` 與 `strcasecmp`，
**跟 sqlite 一點關係都沒有的檔案。**

### 執行它

```bash
bash scripts/run-server.sh start|stop|status|restart|logs
```

然後在 `.env` 裡：

```
TELEGRAM_API_BASE=http://127.0.0.1:8081
TELEGRAM_LOCAL=1
MAX_UPLOAD_MB=2000
BOT_PROXY=http://127.0.0.1:10808
```

`BOT_PROXY` 值得設定，即使 shell 通常已經有一個：**機器人自己的 HTTP 用戶端不會讀 shell 環境變數**，
沒有它的話 Twitter、Pixiv 與 e-hentai 的下載都會失敗。

### 重新開機後

兩個服務都必須回來，而且**伺服器要先起**。`scripts/boot-services.sh` 會做這件事，
它會等 VPN 就緒、等伺服器綁定埠之後才啟動機器人。用 Termux:Boot 安裝它：

```bash
mkdir -p ~/.termux/boot
cp scripts/boot-services.sh ~/.termux/boot/10-bot.sh
chmod +x ~/.termux/boot/10-bot.sh
```

Termux:Boot 安裝後必須開啟一次，而且 **Termux 與 VPN 應用程式都必須免除電池最佳化**，
否則 Android 會把它們殺掉。

---

## 控制面板

一個本機網頁，用來啟動、停止、重啟機器人與伺服器，查看記錄、清除快取、編輯 `.env` ——
讓手機做日常操作時不需要終端機。

```bash
bash control/run-panel.sh start      # 然後開啟 http://127.0.0.1:8090/
bash control/run-panel.sh status
bash control/run-panel.sh stop
```

在 Chrome 裡用**選單 → 加到主畫面**就會變成類應用程式圖示：manifest 設定了
`display: standalone`，所以它會全螢幕開啟、沒有網址列，而且因為所有東西都從手機內部提供，
**它可以離線運作**。

### 它是刻意做得很薄的一層

**每一個按鈕都是去呼叫 `run-bot.sh` 或 `run-server.sh`。** 面板不重新實作啟動機器人，
所以它不可能跟那些腳本的行為脫節 —— 而且面板能做的事，在面板沒跑的時候用命令列一樣能做完。

### 為什麼只綁定 127.0.0.1

面板可以讀寫 `.env`（裡面有 bot token），也可以啟動與停止機器人。**在沒有密碼的情況下從區網可達，
那就等於一個遠端 shell。** 所以它綁定 loopback，並**拒絕監聽其他地方，除非 `--host` 這樣說** ——
那種情況下會產生一個 token，且每個請求都必須附上：

```bash
bash control/run-panel.sh start                        # loopback，不需要 token
PANEL_HOST=0.0.0.0 bash control/run-panel.sh start     # 會印出 token，之後必須提供
```

### 不在開機腳本裡

`~/.termux/boot/10-bot.sh` 只啟動機器人與伺服器。**面板是在有人要看著它的時候才需要的** ——
沒有理由地讓一個 HTTP 服務一直跑著，是一種不值得養成的習慣。需要時再啟動它。

### 真正重要的防護

- **`.env` 的寫入會驗證並備份。** 沒有 `=` 的行、不合法的鍵名、null 位元組都會被拒絕，
  而且舊檔案會先複製到 `data/env-backups/`（保留最後 20 份）。換行字元強制為 LF ——
  **CRLF 的 `.env` 會讓值尾巴帶著 `\r`**，這曾經讓伺服器建置失敗，錯誤是
  `Can't parse as an integer string "30753020"`。
- **清除快取只會在專案內部進行。** 每個路徑都會先解析、確認在專案根目錄之下才會刪除，
  而且只刪 `.cache` 的內容，不刪目錄本身。
- **記錄是用 tail 讀的，不是整份載入。** 那個檔案會無上限成長，所以是以區塊從尾端往回讀；
  每次輪詢都讀整份會一天比一天慢。
- **機器人的執行狀態不是只看 pid 檔。** **過期的 pid 檔正是「停止」按鈕悄悄失效的原因**，
  所以行程列表也會一併檢查。

---

## Android 控制 App

一個原生應用程式，提供與控制面板相同的動作：啟動、停止、重啟機器人與伺服器、查看記錄、清除快取。
程式碼在 `app/`，APK 用以下指令建置：

```powershell
powershell -File app/build.ps1            # 加上 -Install 也會推到裝置上
powershell -File app/build.ps1 -Clean -Install
```

### 它跟控制面板溝通，不是跟 Termux

啟動機器人意味著要在 Termux 裡跑 `run-bot.sh`，而一般應用程式做不到：
`com.termux.RUN_COMMAND` 需要在 Termux 的 properties 裡設 `allow-external-apps=true`，
而直接讀 Termux 的記錄也不可能，因為 `/data/data/com.termux/files/home` 對其他套件不可讀。
面板已經跑在 Termux 裡、也已經剛好提供這些動作，所以它就是那個介面。

> **這個後果是寫在介面裡而不是藏起來的：** 面板沒在跑的時候，App 什麼都不能做，
> 它會顯示一個橫幅、寫出啟動用的指令，而不是一個看起來壞掉的空白畫面。

```bash
bash control/run-panel.sh start     # App 能做任何事之前必須先執行這個
```

### 不用 Gradle 建置

Gradle 加上 Android Gradle Plugin 大約要下載 500 MB，而且第一次建置要好幾分鐘解析依賴。
這個 App 只有一個 activity、沒有任何函式庫依賴，所以 `build.ps1` 直接驅動 AGP 底下的工具鏈：
`aapt2` 編譯與連結、`javac`、`d8`、`zipalign`、`apksigner`。**APK 只有 37 KB。**

它需要的 SDK 是 541 MB：

```bash
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

### 兩個花了真實時間的陷阱

**`d8` 8.2.2 在 javac 21 編譯的匿名內部類別上會當掉。** 不是這個類別特別 ——
五行 `new Runnable() { ... }` 就能重現：

```
Error in .../MainActivity$1.class:
java.lang.NullPointerException: Cannot invoke "String.length()" because "<parameter1>" is null
```

lambda 會編譯成 `invokedynamic`，不會產生 `$1` 類別檔；**具名**的巢狀類別也沒問題；
只有匿名形式會壞。所以這個 App 裡沒有任何匿名內部類別。

最直覺的替代方案 —— 用 lambda 初始化一個會重新排程自己的欄位 —— 也編譯不過，
因為 Java 拒絕一個參考到「正在被初始化的欄位」的欄位初始化式。**`this::pollOnce` 同時避開了這兩個問題。**

**當 `$ErrorActionPreference = "Stop"` 時，PowerShell 會把原生程式的 stderr 變成終止性錯誤。**
`keytool` 把進度寫到 stderr，所以一次**成功**的金鑰產生把建置中止了。
因此 `keytool` 與 `apksigner` 都改走 `cmd /c`，而且用完整路徑 ——
**透過 `cmd` 不會繼承 PowerShell 的 PATH 增補**，所以單寫 `apksigner` 會變成「找不到」。

---

## 必須手動執行的指令：沒有

App 可以自己啟動所有東西，所以正常情況下 Termux 裡沒有任何要打的字。

按下 **一鍵啟動服務** 會送出一個 `com.termux.RUN_COMMAND` intent，讓 Termux 執行
`scripts/start-all.sh` —— 與開機腳本用的是同一支。App 接著會持續輪詢，直到面板回應、
卡片自己消失，所以**它也會偵測到你手動執行的指令**。

### 必須就緒的兩件事

兩者都只需要設定一次、而且會持續生效；**缺少哪一個，App 會回報出來，而不是看起來什麼都不做。**

**1. Termux 必須允許外部應用程式。** 沒有這個，intent 會被拒絕：

```bash
bash scripts/enable-external-apps.sh
```

**然後 Termux 必須重新啟動** —— 它在啟動時只讀一次 `~/.termux/termux.properties`。
腳本執行完會提醒這件事。

**2. App 必須持有 `com.termux.permission.RUN_COMMAND`。** 它會在執行時請求；
**全新安裝會重設授權**，而 adb 可以在沒有對話框的情況下恢復它：

```bash
adb shell pm grant com.yunai.botpanel com.termux.permission.RUN_COMMAND
```

### 讓這件事看起來像權限問題的陷阱

在權限已授予、服務也宣告 `exported=true` 的情況下，`startService` 回傳 `null`，什麼都沒發生：

```
W/ActivityManager: Unable to start service Intent { act=com.termux.RUN_COMMAND
  cmp=com.termux/.app.RunCommandService } U=0: not found
startService returned null
```

**對一個存在的服務說「not found」。** 這是 **Android 11（API 30）的套件可見性**：
一個應用程式只看得到自己的套件，除非它主動要求更多，所以那個服務是**看不見的**。
**一模一樣的 intent 從 root shell 執行卻成功**，因為 root 不受那個過濾器限制 ——
**這正是讓調查往權限方向追了好幾輪的原因。**

解法是 manifest 裡的三行：

```xml
<queries>
    <package android:name="com.termux" />
</queries>
```

用 `<queries>` 而不是 `QUERY_ALL_PACKAGES`：**這個 App 只想要一個套件，而且它把這件事說出來。**
可見性與權限是兩套不同的機制，而當時只有其中一個是問題。

### 如果還是不行

每張卡片都有一個 **顯示手動指令** 按鈕，會顯示可以打的指令。同樣的腳本兩條路都通 ——
**App 是便利，不是替代品。**

```bash
bash ~/twitter_pixiv_tg_bot/scripts/start-all.sh           # 全部，照順序
bash ~/twitter_pixiv_tg_bot/scripts/start-all.sh --status   # 只回報
bash ~/twitter_pixiv_tg_bot/scripts/start-all.sh --restart  # 先停，再起
```

---

## 下載 APK

需要的東西都附在 [最新的 release](https://github.com/YuNaiAFK/twitter_pixiv_tg_bot_android/releases/latest) 上：

| 檔案 | 大小 | 是什麼 |
| --- | --- | --- |
| `bot-panel.apk` | 49 KB | 控制 App，由 `app/` 建置 |
| `termux.apk` | 108.6 MB | Termux 本體（0.118.3，F-Droid 版） |
| `termux-api.apk` | 3.8 MB | Termux:API —— 提供 `termux-wake-lock` |
| `termux-boot.apk` | 25 KB | Termux:Boot —— 開機時啟動服務 |

```bash
adb install -r bot-panel.apk
adb install -r termux.apk
adb install -r termux-api.apk
adb install -r termux-boot.apk
```

**Termux 本體是 108.6 MB**，超過 GitHub 對單一檔案 100 MB 的上限，所以它放在 release 裡而不是
`apk/` 裡。另外三個兩邊都有；詳見 [apk/README.md](apk/README.md)。

**每個 release 都保留該版本的 `bot-panel.apk`**，所以新版本出問題時還是能取得舊的建置。
三個 Termux APK 在每個 release 裡都完全相同。

有兩件事安裝程式做不到，而兩件都必須完成，App 才能啟動任何東西：

```bash
adb shell pm grant com.yunai.botpanel com.termux.permission.RUN_COMMAND
```

以及，在 Termux 裡執行一次：

```bash
bash ~/twitter_pixiv_tg_bot/scripts/enable-external-apps.sh
```

---

## 全部關閉

**電源 → 全部關閉（含面板）** 會先停機器人、再停伺服器、最後停面板自己，並回報接下來該做什麼。
面板的網頁也有同樣的按鈕。

**它被放在獨立的一區、遠離其他工具**，因為那個畫面上的其他東西都能從那個畫面復原 ——
停了機器人，旁邊的按鈕就能再啟動它。**而這一個結束了 App 自己的用處**，因為面板是最後消失的東西。

### 為什麼面板會先回應才死掉

請求是透過 HTTP 進來的，而面板本身就是被停止的東西之一。**在還處理著請求的時候把它殺掉，
會在回應寫出之前就關掉 socket**，App 就會對一個成功的動作回報失敗 ——
**那是最糟的一種回饋，因為它會誘使使用者再按一次。**

所以工作被交給一個**分離**的行程，它會等兩秒，而處理函式立刻回傳。
實測：回應在 13 毫秒內送達、讀到的時候伺服器已經消失、面板自己則在兩秒後結束。

**`start_new_session=True` 是讓子行程活下來的關鍵。** 沒有它，子行程會共用面板的工作階段，
殺掉面板就會把子行程一起帶走，機器人與伺服器就會留在沒有面板可以控制的狀態。

### 要回來不需要打任何字

`POST /api/shutdown` 與按按鈕是同一條路徑，而復原靠的是 **一鍵啟動服務** 卡片，
它會送出 `com.termux.RUN_COMMAND`、**不需要面板活著**。已驗證為完整循環：
關閉、確認每個行程與兩個埠都不在了、然後只靠 intent 再啟動一次。

```bash
bash scripts/start-all.sh --stop      # 從終端機做同樣的事
bash scripts/start-all.sh --status    # 只回報
```

`--stop` 以鏡像的理由反轉啟動順序：**先停機器人，再停它依賴的伺服器**，
而面板最後才走，這樣控制介面會一直存在到最後一刻。

---

## 套件漏洞檢查：`/audit`

**管理員指令。** 把目前裝的每一個套件拿去問 [OSV](https://osv.dev)（`pip-audit` 背後查的同一個資料庫），
回報有問題的套件、修復版本，以及可以直接複製的升級指令。

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

## 圖片圖床與免費額度

e-hentai 的內嵌圖片網址是用 `keystamp` 簽章的，**時效一過，整個頁面的圖片會一起失效** ——
這正是「重新生成」按鈕存在的理由。

**圖片會被複製到 Cloudflare R2**，那裡的物件沒有這種時效。頁面上的網址因此變成
`https://img.ginka.uk/...`，不會再過期。

### 額度上限

R2 免費額度是**每月 10 GB 儲存空間**（對外流量免費、讀取在額度內免費），所以儲存是唯一可能產生帳單的部分。
一本畫廊的顯示圖約 **30 MB**，大約可以放三百本。

**上限設在額度的 95%（9.5 GB），而不是額度本身。** 儲存是按月、按物件存在的時間計費，
所以剛好用到 10 GB、一週後才刪掉，那個月仍然超額。

兩道檢查，因為它們回答不同的問題：

| 時機 | 檢查 | 為什麼 |
| --- | --- | --- |
| **下載任何東西之前** | 桶裡已經存了多少 | 已經滿了就**直接拒絕** —— 抓 30 MB 下來才決定不上傳是浪費 |
| **每張圖片上傳前** | 已存 + 這張 是否超額 | 第一道無法知道要上傳多少 —— 那只有下載了才知道 |

**檢查在寫入之前執行** —— 已經上傳的就是已經計費的。

用量是**詢問桶本身**，不是本地計數器：本地計數在你第一次從 Cloudflare 儀表板刪東西時就會漂移，
之後它會拒絕本來放得下的、或放行本來放不下的。**讀不到用量時就不上傳** ——
問「這會不會花錢」而答不出來時，安全的方向是不要動它。

**兩種情況都會通知管理員**，因為達到上限是代替操作者做的決定，而結果是頁面少了一些圖片。

可以在 `.env` 調整：

```
R2_FREE_BYTES=10000000000     # 免費額度，位元組（10 GB，十進位）
R2_LIMIT_PERCENT=95           # 停止上限佔額度的百分比
```

**App 與面板都會顯示目前用量** —— 已用／總量、剩餘、物件數，以及一條 80% 轉黃、達到上限轉紅的進度條。

---

## 致謝

[CREDITS.md](CREDITS.md) 列出了本專案建立的每一個專案 —— Termux 與它的 companion apps、
proot-distro、Python 函式庫、TDLib、Android 建置工具 —— 附上各自專案頁面的連結、
當時使用的版本，以及它在這裡做什麼。

如果你要重建這個專案，這些是該去的頁面：

| | |
| --- | --- |
| Termux | <https://github.com/termux/termux-app> · <https://termux.dev> · [F-Droid](https://f-droid.org/packages/com.termux/) |
| Termux:API | <https://github.com/termux/termux-api> · [F-Droid](https://f-droid.org/packages/com.termux.api/) |
| Termux:Boot | <https://github.com/termux/termux-boot> · [F-Droid](https://f-droid.org/packages/com.termux.boot/) |
| python-telegram-bot | <https://github.com/python-telegram-bot/python-telegram-bot> · <https://python-telegram-bot.org> |
| gallery-dl | <https://github.com/mikf/gallery-dl> |
| httpx | <https://github.com/encode/httpx> |
| Pillow | <https://github.com/python-pillow/Pillow> |
| Cloudflare R2（boto3） | <https://developers.cloudflare.com/r2/> · <https://github.com/boto/boto3> |
| **EhTagTranslation/Database** | <https://github.com/EhTagTranslation/Database> |
| **OpenCC** | <https://github.com/BYVoid/OpenCC> |
| Telegram Bot API server | <https://github.com/tdlib/telegram-bot-api> |
| TDLib | <https://github.com/tdlib/td> |
| proot-distro | <https://github.com/termux/proot-distro> |
| Android SDK | <https://developer.android.com/studio#command-line-tools-only> |
| Eclipse Temurin JDK | <https://adoptium.net> |

**除了 `apk/` 裡的 APK 之外，這裡沒有任何東西是打包進來的**，本專案也不隸屬於上述任何專案。

> **`bot/tag_translations.py` 是衍生作品，授權為 CC BY-NC-SA 3.0**，不是本專案自己的條款。
> 它由 [`tools/build_tag_translations.py`](tools/build_tag_translations.py) 從 EhTagTranslation 資料庫產生
> （14,206 筆），上游文本本身又是 EHWiki 標籤頁面的翻譯，以相同授權再散布。
>
> **非商業條款正是它與個人使用相容、與拿來收費不相容的原因。** 如果你要商業使用，該看的就是那個檔案。

---

## 版本

App、面板與腳本**共用一個版本號**，記錄在 [`VERSION.properties`](VERSION.properties)。
App 的標題列會把自己的版本與面板的版本並排顯示，兩者都讀同一個檔案，**所以版本不一致是可見的，而不是謎團。**

```powershell
powershell -File app/build.ps1 -Bump            # 1.4 -> 1.5   （新功能）
powershell -File app/build.ps1 -Bump -Fix       # 1.4 -> 1.4.1 （只有修正）
powershell -File app/build.ps1                  # 用目前版本建置
```

**只要功能有變動就升版。** `-Bump` 會在建置**之前**改寫 `VERSION.properties`，
所以建置失敗時版本號仍然是升過的。建置也會在 App 原始碼自上次升版後有變動時**警告** ——
那不是錯誤（失敗後重建是合理的），但提醒才是重點。

[VERSIONS.md](VERSIONS.md) 列出每個版本包含什麼，以及版本號用在哪裡。

---

## 發佈 release

> ### **建立新的 release。永遠不要改名，永遠不要刪除。**
>
> Release 是已發佈的產物 —— 可能有人已經下載或正在跑它，而且 **GitHub 沒有復原功能。**

[`tools/release.ps1`](tools/release.ps1) 讓正確的事變成一個指令：

```powershell
./tools/release.ps1 -List        # 每個 release、它的資產與下載次數
./tools/release.ps1 -Verify      # 檢查有沒有缺東西、/releases/latest 對不對
./tools/release.ps1 -Create      # 發佈 VERSION.properties 裡的版本
```

**它裡面沒有任何會改名或刪除 release 的程式碼**，而且 `-Create` 在該版本已經有 release 時會拒絕。
**一個無法表達那個請求的工具，就不可能犯那個錯** —— 而那個錯這裡犯過一次，
用的是單一個看起來無害的 `PATCH`。

任何動到 release 的操作之後，請執行 `-Verify`。各項檢查涵蓋什麼、以及如果你繞過腳本直接打 API 會發生什麼，
請見 [VERSIONS.md](VERSIONS.md#發佈-release)。

---

## 編輯 PowerShell 腳本

> ### **`app/build.ps1` 與 `tools/release.ps1` 必須保留 UTF-8 BOM。**

Windows PowerShell 5.1 —— 也就是 `powershell` 執行的那個 —— 會把沒有 BOM 的 `.ps1` 當成 ANSI 讀取。
檔案裡如果有破折號、省略號或任何中文，就會被逐位元組解碼成系統代碼頁，而**失敗不是外觀問題**：
剖析器在原本是字串常值的地方看到壞掉的位元組，然後回報

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
用編輯器以外的東西改過它們之後，請執行檢查。

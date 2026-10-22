#!/data/data/com.termux/files/usr/bin/bash
# Run the /audit command's own code on the phone and print what it would say.
#
# Calling the functions rather than sending /audit through Telegram, because the interesting part is
# whether OSV is reachable through the phone's proxy and whether the package list comes back complete
# - not whether Telegram delivers a message.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/audit-run.txt"
cd "$HOME/twitter_pixiv_tg_bot/bot" || exit 1

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    python - <<'PY'
import sys
import time

sys.path.insert(0, ".")
sys.path.insert(0, "vendor")

import bot

# The proxy is read from the .env the bot loads; report it, because a failed audit is nearly always a
# proxy that is down rather than OSV.
try:
    import ehentai
    print(f"  代理: {ehentai.proxy_url() or '(未設定)'}")
except Exception as exc:
    print(f"  代理: 讀取失敗 ({type(exc).__name__})")
print()

packages = bot.installed_packages()
print(f"  套件數: {len(packages)}")
print(f"  前 6 個: {[n for n, _ in packages[:6]]}")
print()

start = time.perf_counter()
report = bot.audit_packages()
print(f"  查詢耗時: {time.perf_counter() - start:.1f}s")
print(f"  error:   {report.get('error') or '(無)'}")
print(f"  有問題:  {len(report.get('findings') or [])} 個套件")
print()
print("---------- 訊息會長這樣 ----------")
print(bot.format_audit_report(report))
print("----------------------------------")
print()
print(f"  訊息長度: {len(bot.format_audit_report(report))} 字元（上限 4096）")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

#!/data/data/com.termux/files/usr/bin/bash
# Report every installed package and version, for a vulnerability check.
#
# `pip list --format=freeze` is the only trustworthy source: requirements.txt states ranges
# (">=21.0,<23.0"), so the range says nothing about what is actually installed, and a CVE applies to
# a version rather than to a range.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
OUT="$HOME/twitter_pixiv_tg_bot/data/packages.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo
    echo "--- python ---"
    python -V 2>&1 | sed 's/^/  /'
    echo
    echo "--- installed packages ---"
    python -m pip list --format=freeze 2>/dev/null | sort | sed 's/^/  /'
    echo
    echo "--- the ones this bot imports ---"
    python - <<'PY'
mods = ["telegram", "httpx", "httpcore", "h11", "PIL", "boto3", "botocore", "s3transfer",
        "gallery_dl", "dotenv", "socks", "urllib3", "requests", "idna", "certifi"]
for name in mods:
    try:
        mod = __import__(name)
        version = (getattr(mod, "__version__", None)
                   or getattr(mod, "VERSION", None)
                   or "?")
        print(f"  {name:14} {version}")
    except Exception as exc:
        print(f"  {name:14} (not importable: {type(exc).__name__})")
PY
} > "$OUT" 2>&1

echo "written to $OUT"

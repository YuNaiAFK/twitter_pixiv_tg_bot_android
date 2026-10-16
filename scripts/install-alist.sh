#!/data/data/com.termux/files/usr/bin/bash
# Install AList from the official Android arm64 build, and initialise its data directory.
#
# AList ships a build for Android specifically, so it runs here directly rather than needing the
# proot Debian container - which matters, because the images it will serve live on the phone and the
# less indirection between the two the better.
#
# Idempotent: re-running replaces the binary but leaves the database and the gallery directory
# alone, so an upgrade does not cost the library.
set -u
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

ALIST_DIR="$HOME/alist"
GALLERY_DIR="$ALIST_DIR/galleries"
DATA_DIR="$ALIST_DIR/data"
DL_DIR="$HOME/alist-download"
VERSION="${ALIST_VERSION:-v3.65.0}"
ASSET="alist-android-arm64.tar.gz"
URL="https://github.com/AlistGo/alist/releases/download/$VERSION/$ASSET"

OUT="$HOME/twitter_pixiv_tg_bot/data/alist-install.txt"
mkdir -p "$ALIST_DIR" "$GALLERY_DIR" "$DATA_DIR" "$DL_DIR"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S')  installing AList $VERSION ==="
    echo "  arch: $(uname -m)"
    echo

    if [ "$(uname -m)" != "aarch64" ]; then
        echo "*** this build is for aarch64; the device reports $(uname -m) ***"
        exit 1
    fi

    echo "--- downloading $ASSET ---"
    started=$(date +%s)
    # Direct first: github was reachable without the proxy from here. The proxy is a fallback
    # because the earlier probes disagreed about whether it was needed.
    if ! curl -fL --max-time 600 --retry 2 -o "$DL_DIR/$ASSET" "$URL" 2>&1 | tail -2; then
        echo "  direct failed, trying the proxy"
        curl -fL --max-time 600 --retry 2 -x http://127.0.0.1:10808 \
            -o "$DL_DIR/$ASSET" "$URL" 2>&1 | tail -2
    fi
    echo "  elapsed: $(( $(date +%s) - started ))s"
    if [ ! -s "$DL_DIR/$ASSET" ]; then
        echo "*** download produced nothing ***"
        exit 1
    fi
    ls -la "$DL_DIR/$ASSET" | sed 's/^/  /'
    echo

    echo "--- extracting ---"
    tar -xzf "$DL_DIR/$ASSET" -C "$DL_DIR" 2>&1 | tail -3
    if [ ! -f "$DL_DIR/alist" ]; then
        echo "*** no alist binary in the archive ***"
        ls -la "$DL_DIR" | sed 's/^/  /'
        exit 1
    fi
    install -m 755 "$DL_DIR/alist" "$ALIST_DIR/alist"
    echo "  installed to $ALIST_DIR/alist"
    echo

    echo "--- version ---"
    cd "$ALIST_DIR" || exit 1
    ./alist version 2>&1 | sed 's/^/  /'
    echo

    echo "--- initialising the data directory (first run only) ---"
    # `alist server` creates data.db and prints the generated admin password on first start. It is
    # run under timeout and killed, so this only does the initialisation.
    if [ ! -f "$DATA_DIR/data.db" ]; then
        timeout 25 ./alist server --data "$DATA_DIR" > "$DL_DIR/first-run.log" 2>&1
        echo "  first run output:"
        sed 's/^/    /' "$DL_DIR/first-run.log" | tail -20
    else
        echo "  data.db already exists; leaving it alone"
    fi
    echo

    echo "--- what was created ---"
    ls -la "$DATA_DIR" 2>/dev/null | sed 's/^/  /'
    echo
    echo "--- the gallery directory AList will serve ---"
    echo "  $GALLERY_DIR"
    ls -la "$GALLERY_DIR" | sed 's/^/  /'
    echo

    if [ -f "$DATA_DIR/data.db" ]; then
        echo "--- resetting the admin password to something known ---"
        # The generated password is printed once and is easy to lose in a log; setting it here
        # makes the panel reachable without hunting for it.
        NEWPW="${ALIST_ADMIN_PASSWORD:-}"
        if [ -n "$NEWPW" ]; then
            ./alist admin set "$NEWPW" --data "$DATA_DIR" 2>&1 | sed 's/^/  /'
        else
            echo "  (ALIST_ADMIN_PASSWORD not set; the generated one is in first-run.log)"
        fi
    fi
} > "$OUT" 2>&1

echo "written to $OUT"

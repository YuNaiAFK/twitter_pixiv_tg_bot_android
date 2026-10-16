#!/data/data/com.termux/files/usr/bin/bash
# Why is the tunnel token rejected? Report its shape, never its value.
#
# A cloudflared tunnel token is base64 of a small JSON object - {"a": account tag, "t": tunnel id,
# "s": secret}. So a token that does not decode to that is either truncated, pasted with something
# else attached, or is not a tunnel token at all (a credentials-file, an API token, or the tunnel's
# UUID are all easy to grab by mistake on that dashboard page).
#
# Everything here is lengths and booleans. The token itself must not reach the output, because this
# file is read back over adb and could end up in a log or a screenshot.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"

ENV_FILE="$HOME/twitter_pixiv_tg_bot/.env"
OUT="$HOME/twitter_pixiv_tg_bot/data/tunnel-token-probe.txt"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo

    echo "--- the raw line in .env, with the value masked ---"
    grep -n '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE" 2>/dev/null \
        | sed 's/=.*/=<masked>/' | sed 's/^/  /'
    echo "  matching lines: $(grep -c '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE" 2>/dev/null)"
    echo

    # Exactly the same extraction the tunnel script uses, so this tests the real path.
    RAW=$(grep -m1 '^CLOUDFLARE_TUNNEL_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
    STRIPPED=$(printf '%s' "$RAW" | tr -d '"'"'"' \r')
    echo "--- after the same cleanup run-tunnel.sh applies ---"
    echo "  raw length:      ${#RAW}"
    echo "  stripped length: ${#STRIPPED}"
    echo "  leading spaces:  $(printf '%s' "$STRIPPED" | sed 's/[^ ].*//' | wc -c)"
    echo "  has whitespace:  $(printf '%s' "$STRIPPED" | grep -qc '[[:space:]]' && echo yes || echo no)"
    echo "  has quotes:      $(printf '%s' "$STRIPPED" | grep -q '["'"'"']' && echo yes || echo no)"
    echo

    echo "--- character classes present (not the characters) ---"
    # **Each class is tested separately, and '-' is never placed between two characters.**
    #
    # The first version tested them as one bracket expression, "[+-_=/]". Inside a bracket
    # expression a '-' between two characters is a RANGE, so that was not "one of + - _ = /" but
    # "anything from '+' (43) to '_' (95)" - which covers digits, every uppercase letter, and the
    # angle brackets. Every probe reported "present" no matter what the value was, and a token
    # consisting of the literal text <TOKEN> looked like it passed. It is listed last here, where
    # a trailing '-' is literal.
    check_class() {
        if printf '%s' "$STRIPPED" | grep -q "$1"; then
            printf '  %-12s present\n' "$2"
        else
            printf '  %-12s absent\n' "$2"
        fi
    }
    check_class '[A-Z]'      'uppercase'
    check_class '[a-z]'      'lowercase'
    check_class '[0-9]'      'digits'
    check_class '[+]'        'plus'
    check_class '[/]'        'slash'
    check_class '[=]'        'equals'
    check_class '[-]'        'hyphen'
    check_class '[<>]'       'angle bracket'
    echo

    echo "--- verdict ---"
    # A cloudflared tunnel token is base64 of {"a":...,"t":...,"s":...}. The '{"' prefix encodes to
    # 'eyJ', so that is the single most useful check, and the length says whether the whole thing
    # was copied rather than just its beginning.
    case "$STRIPPED" in
        eyJ*)
            if [ "${#STRIPPED}" -gt 150 ]; then
                echo "  LOOKS VALID (eyJ prefix, ${#STRIPPED} chars)"
            else
                echo "  TOO SHORT (eyJ prefix but only ${#STRIPPED} chars - probably truncated)"
            fi
            ;;
        '')  echo "  EMPTY - nothing was written to the variable" ;;
        *'<TOKEN>'*|*'<'*'>'*)
             echo "  PLACEHOLDER - the literal text was pasted instead of a token" ;;
        *)   echo "  NOT A TUNNEL TOKEN (${#STRIPPED} chars, no eyJ prefix)" ;;
    esac
    echo

    echo "--- does it decode as base64? ---"
    PADDED="$STRIPPED"
    case $((${#PADDED} % 4)) in
        2) PADDED="$PADDED==" ;;
        3) PADDED="$PADDED=" ;;
    esac
    DECODED=$(printf '%s' "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null)
    if [ -n "$DECODED" ]; then
        echo "  decodes: yes (${#DECODED} bytes)"
        # Only the KEY NAMES, never the values.
        echo "  json keys: $(printf '%s' "$DECODED" | grep -o '"[a-z]":' | tr -d '":' | tr '\n' ' ')"
    else
        echo "  decodes: NO - this is not a base64 token"
    fi
    echo

    echo "--- does it look like a tunnel token or something else? ---"
    case "$STRIPPED" in
        eyJ*)  echo "  starts with eyJ - consistent with base64 JSON" ;;
        *)     echo "  does NOT start with eyJ - a tunnel token normally does" ;;
    esac
    if printf '%s' "$STRIPPED" | grep -qE '^[0-9a-f-]{36}$'; then
        echo "  it is a bare UUID - that is the TUNNEL ID, not the token"
    fi
    echo

    echo "--- what cloudflared itself says (no token shown) ---"
    # A deliberately invalid token produces the same message shape, so this confirms the error is
    # about validity rather than about how the token is passed on the command line.
    "$HOME/cloudflared/download/cloudflared" tunnel --no-autoupdate run --token "invalid-token-probe" \
        2>&1 | head -3 | sed 's/^/  /'
} > "$OUT" 2>&1

echo "written to $OUT"

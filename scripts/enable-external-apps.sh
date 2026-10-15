#!/data/data/com.termux/files/usr/bin/bash
# Let the control app run commands in Termux, which is what removes every manual step.
#
#   bash scripts/enable-external-apps.sh          # enable
#   bash scripts/enable-external-apps.sh --check  # report only
#   bash scripts/enable-external-apps.sh --disable
#
# ## What this changes and why it is needed
#
# Termux refuses `RUN_COMMAND` intents from other apps unless its properties file says
# `allow-external-apps=true`. Without it, the control app cannot start the services, and the user
# is back to typing a command in a terminal before the app is of any use - the exact loop this is
# meant to close.
#
#   ~/.termux/termux.properties     allow-external-apps=true
#
# ## Why that setting is not switched on by default, and what it costs
#
# It lets *any* app that holds `com.termux.permission.RUN_COMMAND` run commands as the Termux
# user. On this phone that is one app, installed by adb, and the setting is what makes it work at
# all - but it is a real widening of what other software can do, so it is opt-in and this script
# says so rather than hiding it.
#
# Termux must be **restarted** for the change to take effect: it reads the properties once at
# startup. That is why the script ends by telling you so, and why the first press of the app's
# button may need Termux reopened.

set -u
export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:$PATH"

HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
PROPS="$HOME_DIR/.termux/termux.properties"
SETTING="allow-external-apps"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()   { printf '  \033[36m·\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

current_value() {
    # The effective value is the last uncommented assignment, since Termux reads the file in
    # order and a later line wins. `false` when the key is absent, which is the default.
    if [ -r "$PROPS" ]; then
        local last
        last=$(grep -E "^[[:space:]]*${SETTING}[[:space:]]*=" "$PROPS" 2>/dev/null | tail -1 || true)
        if [ -n "$last" ]; then
            printf '%s' "${last#*=}" | tr -d ' \r' | tr 'A-Z' 'a-z'
            return
        fi
    fi
    printf 'false'
}

action="${1:-enable}"

say "allow-external-apps"
no "properties file: $PROPS"
no "current value:   $(current_value)"

if [ "$action" = "--check" ]; then
    if [ "$(current_value)" = "true" ]; then
        ok "enabled - the app can run commands in Termux"
    else
        bad "not enabled - the app cannot start the services by itself"
        no "enable with:  bash scripts/enable-external-apps.sh"
    fi
    printf '\n'
    exit 0
fi

mkdir -p "$HOME_DIR/.termux"

# A backup, because this file also holds key bindings and other settings the user may have set.
if [ -f "$PROPS" ]; then
    stamp=$(date +%Y%m%d-%H%M%S)
    cp "$PROPS" "$PROPS.bak.$stamp" && no "backup: $PROPS.bak.$stamp"
fi

if [ "$action" = "--disable" ]; then
    if [ -f "$PROPS" ]; then
        # Comment the line out rather than deleting it, so the intent is still visible and
        # re-enabling is a one-character edit.
        sed -i "s|^[[:space:]]*${SETTING}[[:space:]]*=.*|# &|" "$PROPS"
        ok "disabled (the line is commented out, not removed)"
    else
        no "nothing to disable"
    fi
else
    if [ ! -f "$PROPS" ]; then
        cat > "$PROPS" <<'EOF'
# Termux properties. See https://wiki.termux.com/wiki/Termux.properties
#
# allow-external-apps lets other apps run commands here through RUN_COMMAND intents. It is
# required by the bot control app, which uses it to start the Bot API server, the bot and the
# control panel without anyone typing a command. Enabled by scripts/enable-external-apps.sh.
allow-external-apps=true
EOF
        ok "created $PROPS"
    elif grep -qE "^[[:space:]]*${SETTING}[[:space:]]*=" "$PROPS"; then
        sed -i "s|^[[:space:]]*${SETTING}[[:space:]]*=.*|${SETTING}=true|" "$PROPS"
        ok "set $SETTING=true"
    else
        # Append with a blank line so it does not run into whatever was last.
        printf '\n%s=true\n' "$SETTING" >> "$PROPS"
        ok "appended $SETTING=true"
    fi

    # Show the result from the file, not from what we intended to write.
    no "now reads:"
    grep -nE "^[[:space:]]*#?[[:space:]]*${SETTING}" "$PROPS" 2>/dev/null | sed 's/^/    /'

    if [ "$(current_value)" = "true" ]; then
        ok "enabled"
    else
        bad "the file does not show it as enabled - check $PROPS"
        exit 1
    fi
fi

printf '\n'
printf '    \033[33mTermux must be restarted for this to take effect.\033[0m\n'
printf '    It reads the properties file once at startup.\n'
printf '\n'
printf '    Close Termux completely (swipe it away from the recents list) and open it\n'
printf '    again, or reboot the phone. Then the app can start everything by itself.\n'
printf '\n'

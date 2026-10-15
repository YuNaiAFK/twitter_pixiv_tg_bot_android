#!/data/data/com.termux/files/usr/bin/bash
# Report what this device can actually run, before anything is installed.
#
# Written for a rooted OnePlus 8 Pro on Pixel Experience 13, but it changes nothing and is
# safe to run anywhere: every check is a read.
#
# Why a probe rather than a guess: the single question that decides how this is deployed is
# whether the kernel exposes the namespaces and cgroups a container runtime needs. Android
# kernels vary by device and ROM, and the answer is not visible from the Android version.
# Everything downstream - Docker, or a plain chroot, or Termux alone - follows from it.
#
# Usage:  bash scripts/probe-device.sh

set -u

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()   { printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '  \033[36m·\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

section "Device"
info "kernel    $(uname -r)"
info "machine   $(uname -m)"
if [ -r /system/build.prop ]; then
    info "android   $(grep -m1 'ro.build.version.release' /system/build.prop 2>/dev/null | cut -d= -f2)"
    info "rom       $(grep -m1 'ro.build.display.id' /system/build.prop 2>/dev/null | cut -d= -f2)"
fi
if [ "$(uname -m)" != "aarch64" ]; then
    warn "not aarch64 - prebuilt ARM64 binaries will not run"
fi

section "Environment"
if [ -n "${TERMUX_VERSION:-}" ]; then
    ok "running inside Termux ($TERMUX_VERSION)"
else
    info "not Termux (fine inside a chroot)"
fi
if [ "$(id -u)" = "0" ]; then
    ok "running as root (uid 0)"
else
    warn "not root - a chroot needs it, Termux-only does not"
fi
if command -v su >/dev/null 2>&1; then
    ok "su present"
else
    info "no su on PATH"
fi
if command -v proot-distro >/dev/null 2>&1; then
    ok "proot-distro present"
else
    info "proot-distro not installed"
fi

section "Python (the bot itself)"
if command -v python >/dev/null 2>&1; then
    ok "python $(python --version 2>&1 | awk '{print $2}')"
    info "path  $(command -v python)"
else
    no "python not found - pkg install python"
fi
if command -v gallery-dl >/dev/null 2>&1; then
    ok "gallery-dl $(gallery-dl --version 2>&1 | head -1)"
else
    no "gallery-dl not found - pip install gallery-dl"
fi

section "Kernel: what a container runtime needs"
# Namespaces. Docker needs at least pid, net, mnt and ipc; user namespaces are needed for
# rootless operation and are commonly disabled on Android.
if [ -r /proc/self/status ]; then
    namespaces=$(grep -m1 '^NSpid:' /proc/self/status 2>/dev/null | awk '{print NF-1}')
    info "NSpid depth ${namespaces:-?} (1 = no pid namespace nesting)"
fi
for ns in "/proc/self/ns/pid" "/proc/self/ns/net" "/proc/self/ns/mnt" "/proc/self/ns/user"; do
    if [ -e "$ns" ]; then
        ok "namespace $(basename "$ns") present"
    else
        no "namespace $(basename "$ns") MISSING"
    fi
done
if [ -r /proc/sys/user/max_user_namespaces ]; then
    maxns=$(cat /proc/sys/user/max_user_namespaces 2>/dev/null)
    if [ "${maxns:-0}" -gt 0 ] 2>/dev/null; then
        ok "user namespaces allowed (max_user_namespaces=$maxns)"
    else
        no "user namespaces disabled (max_user_namespaces=$maxns)"
    fi
else
    warn "max_user_namespaces not readable - cannot tell"
fi

section "Kernel: cgroups"
if [ -f /proc/cgroups ]; then
    info "/proc/cgroups:"
    while read -r name hier num enabled; do
        case "$name" in
            \#*) continue ;;
        esac
        if [ "${enabled:-0}" = "1" ]; then
            ok "  $name enabled"
        else
            info "  $name not enabled"
        fi
    done < /proc/cgroups
else
    warn "/proc/cgroups missing"
fi
if [ -d /sys/fs/cgroup ]; then
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        ok "cgroup v2 unified ($(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null))"
    else
        info "cgroup v1 layout"
        info "  controllers: $(ls /sys/fs/cgroup 2>/dev/null | head -12 | tr '\n' ' ')"
    fi
    # Writing is the part that matters: reading proves nothing about permission.
    probe=/sys/fs/cgroup/dsh_probe.$$
    if mkdir "$probe" 2>/dev/null; then
        ok "can create a cgroup (needs root)"
        rmdir "$probe" 2>/dev/null
    else
        warn "cannot create a cgroup here - expected unless root"
    fi
else
    no "/sys/fs/cgroup missing - no container runtime will work"
fi

section "Filesystems (overlayfs is what Docker images need)"
if grep -qw overlay /proc/filesystems 2>/dev/null; then
    ok "overlay supported"
else
    no "overlay NOT in /proc/filesystems - Docker images cannot be unpacked"
fi
for fs in fuse tmpfs ext4; do
    if grep -qw "$fs" /proc/filesystems 2>/dev/null; then
        ok "$fs supported"
    else
        info "$fs not listed"
    fi
done

section "SELinux (the usual reason a root chroot still fails)"
if command -v getenforce >/dev/null 2>&1; then
    info "mode $(getenforce 2>/dev/null)"
elif [ -r /sys/fs/selinux/enforce ]; then
    if [ "$(cat /sys/fs/selinux/enforce 2>/dev/null)" = "1" ]; then
        info "mode Enforcing"
    else
        info "mode Permissive"
    fi
else
    info "SELinux not exposed"
fi

section "Result"
printf '  A container runtime (Docker) needs: overlayfs + cgroups + namespaces + root.\n'
printf '  If any of those showed %s, use the chroot path instead - it needs only root\n' "✗"
printf '  and gives the same 2000 MB upload limit, which is the actual goal.\n'
printf '\n'
printf '  Paste this whole output when asking for help.\n'

#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="$REPO_DIR/void-desktop-setup.sh"
[[ -x "$TARGET_SCRIPT" ]] || { echo 'Setup script must be executable' >&2; exit 1; }
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SCENARIOS=0

fail() { echo "Assertion failed: $*" >&2; exit 1; }
assert_contains() { grep -Eq -- "$2" "$1" || fail "expected '$2' in $1"; }
assert_not_contains() { if grep -Eq -- "$2" "$1"; then fail "unexpected '$2' in $1"; fi; }
assert_absent() { [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path $1"; }
assert_link() { [[ -L "$1" && "$(readlink "$1")" == "$2" ]] || fail "incorrect link $1 -> $2"; }
assert_package() { assert_contains "$CASE_DIR/packages" "^$1$"; }
assert_no_package() { assert_not_contains "$CASE_DIR/packages" "^$1$"; }

new_case() {
    CASE_DIR="$TMP_ROOT/$1"
    mkdir -p "$CASE_DIR"/{bin,sv,services,home,etc,backgrounds,noctalia-greeter,applications,system-repos}
    mkdir -p "$CASE_DIR/examples"/{pipewire,wireplumber} "$CASE_DIR/alsa-share" "$CASE_DIR/etc/alsa" "$CASE_DIR/etc/pipewire" "$CASE_DIR/etc/turnstile"
    local svc
    # Audio service dirs deliberately exist: the script must never enable them.
    for svc in dbus bluetoothd greetd NetworkManager elogind seatd turnstiled accounts-daemon pipewire wireplumber pipewire-pulse pulseaudio dhcpcd wpa_supplicant iwd connmand wicd; do
        mkdir -p "$CASE_DIR/sv/$svc"
    done
    touch "$CASE_DIR/examples/pipewire/20-pipewire-pulse.conf" "$CASE_DIR/examples/wireplumber/10-wireplumber.conf"
    touch "$CASE_DIR/alsa-share/50-pipewire.conf" "$CASE_DIR/alsa-share/99-pipewire-default.conf"
    printf '[Desktop Entry]\nExec=pipewire\n' > "$CASE_DIR/applications/pipewire.desktop"
    : > "$CASE_DIR/packages"
    : > "$CASE_DIR/actions"
    echo tester > "$CASE_DIR/groups"
    GPU_OUTPUT='00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 620 [8086:5917]'
    MISSING_CMDS=""
    UNAVAILABLE_PACKAGE=""
    FAIL_SV=0
    FAIL_SV_SVC=""
    FAIL_NM_LINK=0
    cat > "$CASE_DIR/bin/xbps-install" <<'EOS'
#!/usr/bin/env bash
printf 'xbps-install %s\n' "$*" >> "$MOCK_ROOT/actions"
for pkg in "$@"; do
    [[ "$pkg" == -* ]] && continue
    grep -qxF "$pkg" "$MOCK_ROOT/packages" || echo "$pkg" >> "$MOCK_ROOT/packages"
done
EOS
    cat > "$CASE_DIR/bin/xbps-query" <<'EOS'
#!/usr/bin/env bash
pkg="${!#}"
if [[ "$1" == -R ]]; then
    [[ "$pkg" != "${MOCK_UNAVAILABLE_PACKAGE:-}" ]]
else
    grep -qxF "$pkg" "$MOCK_ROOT/packages"
fi
EOS
    cat > "$CASE_DIR/bin/lspci" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$MOCK_LSPCI_OUTPUT"
EOS
    cat > "$CASE_DIR/bin/getent" <<'EOS'
#!/usr/bin/env bash
case "$1" in
    passwd) echo "tester:x:1000:1000::$VDS_CURRENT_HOME:/bin/bash" ;;
    group) echo "$2:x:1000:" ;;
    *) exit 1 ;;
esac
EOS
    cat > "$CASE_DIR/bin/id" <<'EOS'
#!/usr/bin/env bash
paste -sd ' ' "$MOCK_ROOT/groups"
EOS
    cat > "$CASE_DIR/bin/usermod" <<'EOS'
#!/usr/bin/env bash
printf 'usermod %s\n' "$*" >> "$MOCK_ROOT/actions"
echo "$2" >> "$MOCK_ROOT/groups"
EOS
    cat > "$CASE_DIR/bin/sv" <<'EOS'
#!/usr/bin/env bash
printf 'sv %s\n' "$*" >> "$MOCK_ROOT/actions"
if [[ "$1" == down && -n "${MOCK_FAIL_SV_SVC:-}" && "${2##*/}" == "$MOCK_FAIL_SV_SVC" ]]; then
    exit 1
fi
exit "${MOCK_FAIL_SV:-0}"
EOS
    cat > "$CASE_DIR/bin/ln" <<'EOS'
#!/usr/bin/env bash
if [[ "${MOCK_FAIL_NM_LINK:-0}" == 1 && "${!#}" == "$MOCK_ROOT/services/NetworkManager" ]]; then
    printf 'ln failed NetworkManager\n' >> "$MOCK_ROOT/actions"
    exit 1
fi
exec /usr/bin/ln "$@"
EOS
    cat > "$CASE_DIR/bin/chown" <<'EOS'
#!/usr/bin/env bash
printf 'chown %s\n' "$*" >> "$MOCK_ROOT/actions"
EOS
    for svc in niri noctalia noctalia-greeter-session; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$CASE_DIR/bin/$svc"
    done
    chmod +x "$CASE_DIR/bin"/*
    cat > "$CASE_DIR/runner.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
# Source the actual script; mock only platform validation, not file/service logic.
# shellcheck source=../void-desktop-setup.sh
source "$TARGET_SCRIPT"
command() {
    if [[ "${1:-}" == -v && " ${MOCK_MISSING_CMDS:-} " == *" ${2:-} "* ]]; then
        return 1
    fi
    builtin command "$@"
}
setup_preflight() {
    exec {TTY_FD}<"$TTY_INPUT"
    resolve_desktop_user
}
main
EOS
}

run_case() {
    local input="$1" mode="${2:-apply}" expected="${3:-0}"
    printf '%s\n' "$input" > "$CASE_DIR/input"
    local args=()
    local entrypoint="$CASE_DIR/runner.sh"
    if [[ "$mode" == dry || "$mode" == direct-dry || "$mode" == pipe-dry ]]; then
        args=(--dry-run)
    fi
    local launch=(bash "$entrypoint" "${args[@]}")
    if [[ "$mode" == direct-dry ]]; then
        launch=("$TARGET_SCRIPT" "${args[@]}")
    elif [[ "$mode" == pipe-dry ]]; then
        launch=(bash -s -- "${args[@]}")
    fi
    local status=0
    # The legacy dry-run hook is intentionally set: it must not execute mutations.
    env PATH="$CASE_DIR/bin:$PATH" TARGET_SCRIPT="$TARGET_SCRIPT" \
        MOCK_ROOT="$CASE_DIR" MOCK_LSPCI_OUTPUT="$GPU_OUTPUT" MOCK_MISSING_CMDS="$MISSING_CMDS" \
        MOCK_UNAVAILABLE_PACKAGE="$UNAVAILABLE_PACKAGE" MOCK_FAIL_SV="$FAIL_SV" MOCK_FAIL_SV_SVC="$FAIL_SV_SVC" MOCK_FAIL_NM_LINK="$FAIL_NM_LINK" \
        VDS_CURRENT_USER=tester VDS_CURRENT_HOME="$CASE_DIR/home" VDS_INPUT_FILE="$CASE_DIR/input" \
        VDS_ALLOW_NON_ROOT=1 VDS_DRY_RUN_EXEC=1 \
        VDS_SV_DIR="$CASE_DIR/sv" VDS_SERVICE_DIR="$CASE_DIR/services" \
        VDS_XBPS_REPO_CONF="$CASE_DIR/etc/voiders.conf" VDS_XBPS_SYSTEM_REPO_DIR="$CASE_DIR/system-repos" \
        VDS_NVIDIA_MODPROBE_CONF="$CASE_DIR/etc/nvidia.conf" VDS_INTEL_PROFILE_CONF="$CASE_DIR/etc/intel.sh" \
        VDS_GREETD_CONF="$CASE_DIR/etc/greetd.toml" VDS_BACKGROUND_DIR="$CASE_DIR/backgrounds" \
        VDS_NOCTALIA_GREETER_DIR="$CASE_DIR/noctalia-greeter" VDS_EXAMPLES_DIR="$CASE_DIR/examples" \
        VDS_APPLICATIONS_DIR="$CASE_DIR/applications" VDS_ALSA_SHARE_DIR="$CASE_DIR/alsa-share" \
        VDS_ALSA_CONF_DIR="$CASE_DIR/etc/alsa" VDS_PIPEWIRE_SYSTEM_DIR="$CASE_DIR/etc/pipewire" \
        VDS_TURNSTILE_CONF="$CASE_DIR/etc/turnstile/turnstiled.conf" \
        timeout 15 "${launch[@]}" < "$TARGET_SCRIPT" > "$CASE_DIR/run.log" 2>&1 || status=$?
    if [[ "$status" != "$expected" ]]; then
        cat "$CASE_DIR/run.log" >&2
        fail "$CASE_DIR: exit $status, expected $expected"
    fi
    SCENARIOS=$((SCENARIOS + 1))
}

snapshot() {
    # Include contents, link targets, modes, inode/mtime and state from mocked commands.
    local path
    for path in "$CASE_DIR/home" "$CASE_DIR/etc" "$CASE_DIR/services" "$CASE_DIR/backgrounds" "$CASE_DIR/noctalia-greeter"; do
        find "$path" -printf '%p %y %m %i %T@ %l\n' | sort
        find "$path" -type f -exec sha256sum {} + | sort
    done
    sha256sum "$CASE_DIR/packages" "$CASE_DIR/groups"
}
snapshot_session_stack() {
    local path
    for path in "$CASE_DIR/services/elogind" "$CASE_DIR/services/seatd" "$CASE_DIR/services/turnstiled" "$CASE_DIR/etc/turnstile/turnstiled.conf"; do
        if [[ -e "$path" || -L "$path" ]]; then
            stat --printf='%n %F %a %i %y %N\n' "$path"
            if [[ -f "$path" ]]; then sha256sum "$path"; fi
        else
            printf '%s absent\n' "$path"
        fi
    done
}
assert_audio() {
    assert_package dbus
    assert_package pipewire
    assert_package wireplumber
    assert_package alsa-pipewire
    assert_package libspa-bluetooth
    assert_link "$CASE_DIR/home/.config/pipewire/pipewire.conf.d/10-wireplumber.conf" "$CASE_DIR/examples/wireplumber/10-wireplumber.conf"
    assert_link "$CASE_DIR/home/.config/pipewire/pipewire.conf.d/20-pipewire-pulse.conf" "$CASE_DIR/examples/pipewire/20-pipewire-pulse.conf"
    assert_link "$CASE_DIR/etc/alsa/50-pipewire.conf" "$CASE_DIR/alsa-share/50-pipewire.conf"
    assert_link "$CASE_DIR/etc/alsa/99-pipewire-default.conf" "$CASE_DIR/alsa-share/99-pipewire-default.conf"
    assert_link "$CASE_DIR/services/bluetoothd" "$CASE_DIR/sv/bluetoothd"
    assert_contains "$CASE_DIR/groups" '^bluetooth$'
    assert_absent "$CASE_DIR/services/pipewire"
    assert_absent "$CASE_DIR/services/wireplumber"
    assert_absent "$CASE_DIR/services/pipewire-pulse"
}

new_case intel_sway_clean_nm
run_case $'2\ny'
assert_package mesa-dri
assert_package vulkan-loader
assert_package mesa-vulkan-intel
assert_package intel-media-driver
assert_package elogind
assert_package wireplumber-elogind
assert_no_package seatd
assert_link "$CASE_DIR/services/elogind" "$CASE_DIR/sv/elogind"
assert_link "$CASE_DIR/services/NetworkManager" "$CASE_DIR/sv/NetworkManager"
assert_contains "$CASE_DIR/groups" '^network$'
assert_contains "$CASE_DIR/home/.config/sway/config" '^include /etc/sway/config$'
assert_contains "$CASE_DIR/home/.config/sway/config" '^exec pipewire$'
assert_contains "$CASE_DIR/home/.config/sway/config" '^exec dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway$'
assert_package xdg-desktop-portal-wlr
assert_package xdg-desktop-portal-gtk
assert_no_package xdg-desktop-portal-kde
assert_no_package xdg-desktop-portal-gnome
assert_contains "$CASE_DIR/home/.config/xdg-desktop-portal/sway-portals.conf" 'ScreenCast=wlr;'
assert_audio
assert_contains "$CASE_DIR/actions" 'chown tester .*/home/\.config$'
snapshot > "$CASE_DIR/before"
cp "$CASE_DIR/actions" "$CASE_DIR/actions-before"
run_case $'2\ny'
snapshot > "$CASE_DIR/after"
cmp "$CASE_DIR/before" "$CASE_DIR/after" || { diff -u "$CASE_DIR/before" "$CASE_DIR/after"; fail 'second run changed filesystem/state'; }
cmp "$CASE_DIR/actions-before" "$CASE_DIR/actions" || fail 'second run repeated mutations'

new_case old_intel
GPU_OUTPUT='00:02.0 VGA compatible controller: Intel Corporation HD Graphics 3000'
run_case $'3\nn'
assert_package libva-intel-driver
assert_contains "$CASE_DIR/etc/intel.sh" 'LIBVA_DRIVER_NAME=i965'
assert_contains "$CASE_DIR/etc/intel.sh" 'VDPAU_DRIVER=va_gl'
assert_package libvdpau-va-gl

new_case amd_all
GPU_OUTPUT='01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 24 [Radeon RX 6400]'
run_case $'4 1 2\ny\nn'
for pkg in mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi linux-firmware-amd kde-plasma niri sway noctalia xdg-desktop-portal-gnome xdg-desktop-portal-wlr xdg-desktop-portal-kde xdg-desktop-portal-gtk; do assert_package "$pkg"; done
[[ "$(grep -cx niri "$CASE_DIR/packages")" == 1 ]] || fail 'duplicate niri'
assert_contains "$CASE_DIR/home/.config/niri/config.kdl" '^spawn-at-startup "pipewire"$'
assert_contains "$CASE_DIR/home/.config/niri/config.kdl" '^spawn-at-startup "noctalia" "--daemon"$'
assert_contains "$CASE_DIR/home/.config/niri/config.kdl" 'XCURSOR_SIZE "24"'
assert_contains "$CASE_DIR/home/.config/xdg-desktop-portal/niri-portals.conf" 'FileChooser=gtk;'
assert_contains "$CASE_DIR/home/.config/xdg-desktop-portal/niri-portals.conf" 'Secret=gnome-keyring;'
assert_package gnome-keyring
assert_link "$CASE_DIR/home/.config/autostart/pipewire.desktop" "$CASE_DIR/applications/pipewire.desktop"
assert_contains "$CASE_DIR/etc/voiders.conf" '^repository=https://repo.voiders.dev$'
assert_audio
snapshot > "$CASE_DIR/before"
run_case $'4\nn' # Existing repo must not prompt for approval again.
snapshot > "$CASE_DIR/after"
cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'all-desktop repeat changed files'

# All requested NVIDIA generations; Pascal fixture no longer expects modern nvidia.
for spec in 'turing:TU106 [GeForce RTX 2060]:nvidia' 'ampere:GA104 [GeForce RTX 3070]:nvidia' 'ada:AD106 [GeForce RTX 4060 Ti]:nvidia' 'blackwell:GB203 [GeForce RTX 5080]:nvidia' 'maxwell:GM107 [GeForce GTX 750 Ti]:nvidia580' 'pascal:GP107M [GeForce GTX 1050 Mobile]:nvidia580' 'volta:GV100 [TITAN V]:nvidia580' 'kepler:GK104 [GeForce GTX 680]:nvidia470' 'fermi:GF108 [GeForce GT 430]:nvidia390'; do
    IFS=: read -r name description driver <<< "$spec"
    new_case "nvidia_$name"
    GPU_OUTPUT="01:00.0 VGA compatible controller: NVIDIA Corporation $description [10de:0001]"
    run_case $'3\nn'
    assert_package "$driver"
    assert_package "${driver}-opencl"
    assert_no_package nvidia-settings
    for other in nvidia nvidia580 nvidia470 nvidia390; do
        [[ "$other" == "$driver" ]] || assert_no_package "$other"
    done
    if [[ "$driver" == nvidia390 ]]; then
        assert_absent "$CASE_DIR/etc/nvidia.conf"
    else
        assert_contains "$CASE_DIR/etc/nvidia.conf" '^options nvidia-drm modeset=1$'
    fi
    assert_package kde-plasma
    assert_package xdg-desktop-portal-kde
    assert_no_package xdg-desktop-portal-wlr
    assert_no_package xdg-desktop-portal-gnome
    assert_audio
    if [[ "$name" == ada ]]; then
        snapshot > "$CASE_DIR/before"
        run_case $'3\nn'
        snapshot > "$CASE_DIR/after"
        cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'NVIDIA repeat changed files'
        printf 'options nvidia-drm modeset=0\n' > "$CASE_DIR/etc/nvidia.conf"
        run_case $'3\nn'
        assert_contains "$CASE_DIR/etc/nvidia.conf" 'modeset=0'
        assert_contains "$CASE_DIR/run.log" 'Preserving existing configuration'
    fi
done

for description in 'G92 [GeForce 8800 GT]' 'Unknown GPU [10de:ffff]' 'GeForce GT 730'; do
    new_case "nvidia_fallback_$SCENARIOS"
    GPU_OUTPUT="01:00.0 VGA compatible controller: NVIDIA Corporation $description"
    run_case $'2\nn'
    assert_package mesa-dri
    assert_package vulkan-loader
    for driver in nvidia nvidia580 nvidia470 nvidia390; do assert_no_package "$driver"; done
    assert_no_package void-repo-nonfree
    assert_absent "$CASE_DIR/etc/nvidia.conf"
done

new_case nvidia_unavailable
GPU_OUTPUT='01:00.0 VGA compatible controller: NVIDIA Corporation AD106 [GeForce RTX 4060 Ti]'
UNAVAILABLE_PACKAGE=nvidia
run_case $'2\nn'
assert_no_package nvidia
assert_package mesa-dri
assert_contains "$CASE_DIR/run.log" 'unavailable for this architecture'

new_case nvidia_existing_other_branch
GPU_OUTPUT='01:00.0 VGA compatible controller: NVIDIA Corporation AD106 [GeForce RTX 4060 Ti]'
echo nvidia470 > "$CASE_DIR/packages"
run_case $'3\nn'
assert_no_package nvidia
assert_contains "$CASE_DIR/run.log" 'Existing nvidia470 conflicts'

new_case hybrid_pascal
GPU_OUTPUT=$'00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 620\n01:00.0 3D controller: NVIDIA Corporation GP107M [GeForce GTX 1050 Mobile]'
run_case $'3\n3\nn'
assert_package mesa-vulkan-intel
assert_package nvidia580
assert_no_package nvidia

new_case dedicated_pascal
GPU_OUTPUT=$'00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 620\n01:00.0 3D controller: NVIDIA Corporation GP107M [GeForce GTX 1050 Mobile]'
run_case $'1\n3\nn'
assert_package nvidia580
assert_no_package mesa-vulkan-intel

new_case mixed_nvidia
GPU_OUTPUT=$'00:02.0 VGA compatible controller: NVIDIA Corporation AD106\n01:00.0 VGA compatible controller: NVIDIA Corporation GP107M'
run_case $'3\n2\nn'
assert_package mesa-dri
assert_no_package nvidia
assert_no_package nvidia580

new_case no_gpu
GPU_OUTPUT=''
run_case $'y\n2\nn'
assert_package mesa-dri
assert_package vulkan-loader

new_case unknown_gpu
GPU_OUTPUT='00:00.0 Display controller: Unknown Vendor [1234:ffff]'
run_case $'2\nn'
assert_package mesa-dri
assert_package vulkan-loader

for compositor in 1 2; do
    new_case "seatd_$compositor"
    ln -s "$CASE_DIR/sv/seatd" "$CASE_DIR/services/seatd"
    run_case "$(printf '%s\nn\nn\n' "$compositor")"
    assert_package seatd
    assert_package turnstile
    assert_no_package elogind
    assert_link "$CASE_DIR/services/turnstiled" "$CASE_DIR/sv/turnstiled"
    for group in _seatd audio video; do assert_contains "$CASE_DIR/groups" "^$group$"; done
done
new_case turnstile_existing
ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
run_case $'2\nn'
assert_package seatd
assert_no_package elogind

new_case kde_alternative_seat
ln -s "$CASE_DIR/sv/seatd" "$CASE_DIR/services/seatd"
run_case $'3\nn'
assert_package kde-plasma
assert_package elogind
assert_link "$CASE_DIR/services/elogind" "$CASE_DIR/sv/elogind"
assert_link "$CASE_DIR/services/seatd" "$CASE_DIR/sv/seatd"
assert_no_package turnstile

# Migration takes place only with explicit consent, never with custom service dirs.
for svc in dhcpcd wpa_supplicant dhcpcd-eth0 wpa_supplicant-wlan0 dhclient udhcpc iwd connmand wicd; do
    new_case "network_$svc"
    mkdir -p "$CASE_DIR/sv/$svc"
    ln -s "$CASE_DIR/sv/$svc" "$CASE_DIR/services/$svc"
    run_case $'2\ny\ny'
    assert_absent "$CASE_DIR/services/$svc"
    assert_link "$CASE_DIR/services/NetworkManager" "$CASE_DIR/sv/NetworkManager"
    assert_contains "$CASE_DIR/actions" "sv down .*/$svc$"
    # Installing NM must precede stopping the old service.
    nm_line="$(grep -n 'xbps-install .*NetworkManager' "$CASE_DIR/actions" | cut -d: -f1)"
    stop_line="$(grep -n 'sv down' "$CASE_DIR/actions" | cut -d: -f1)"
    [[ "$nm_line" -lt "$stop_line" ]] || fail 'connection stopped before downloads'
    cp "$CASE_DIR/actions" "$CASE_DIR/actions-before"
    run_case $'2\ny'
    cmp "$CASE_DIR/actions-before" "$CASE_DIR/actions" || fail 'repeated network migration'
done
new_case network_declined
ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
ln -s "$CASE_DIR/sv/wpa_supplicant" "$CASE_DIR/services/wpa_supplicant"
run_case $'2\ny\nn'
assert_link "$CASE_DIR/services/dhcpcd" "$CASE_DIR/sv/dhcpcd"
assert_link "$CASE_DIR/services/wpa_supplicant" "$CASE_DIR/sv/wpa_supplicant"
assert_absent "$CASE_DIR/services/NetworkManager"
assert_no_package NetworkManager

new_case network_custom
mkdir "$CASE_DIR/services/dhcpcd"
run_case $'2\ny'
assert_absent "$CASE_DIR/services/NetworkManager"
assert_contains "$CASE_DIR/run.log" 'Custom network service'
new_case network_missing_nm
rm -r "$CASE_DIR/sv/NetworkManager"
ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
run_case $'2\ny\ny'
assert_link "$CASE_DIR/services/dhcpcd" "$CASE_DIR/sv/dhcpcd"
assert_not_contains "$CASE_DIR/actions" 'sv down'
new_case network_stop_failure
ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
FAIL_SV=1
run_case $'2\ny\ny' apply 1
assert_absent "$CASE_DIR/services/NetworkManager"
assert_link "$CASE_DIR/services/dhcpcd" "$CASE_DIR/sv/dhcpcd"

new_case network_partial_stop_failure
ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
ln -s "$CASE_DIR/sv/wpa_supplicant" "$CASE_DIR/services/wpa_supplicant"
FAIL_SV_SVC=wpa_supplicant
run_case $'2\ny\ny' apply 1
assert_absent "$CASE_DIR/services/NetworkManager"
assert_link "$CASE_DIR/services/dhcpcd" "$CASE_DIR/sv/dhcpcd"
assert_link "$CASE_DIR/services/wpa_supplicant" "$CASE_DIR/sv/wpa_supplicant"
assert_contains "$CASE_DIR/actions" 'sv up .*/dhcpcd$'
for svc in NetworkManager dbus; do
    new_case "network_down_$svc"
    : > "$CASE_DIR/sv/$svc/down"
    ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
    run_case $'2\ny\ny'
    assert_link "$CASE_DIR/services/dhcpcd" "$CASE_DIR/sv/dhcpcd"
    assert_absent "$CASE_DIR/services/NetworkManager"
    assert_not_contains "$CASE_DIR/actions" 'sv down'
done

new_case network_enable_failure
ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
FAIL_NM_LINK=1
run_case $'2\ny\ny' apply 1
assert_absent "$CASE_DIR/services/NetworkManager"
assert_link "$CASE_DIR/services/dhcpcd" "$CASE_DIR/sv/dhcpcd"
assert_contains "$CASE_DIR/actions" 'sv up .*/dhcpcd$'
assert_contains "$CASE_DIR/run.log" 'restoring previous network service links'

new_case noctalia_reject
run_case $'1\nn\nn'
assert_package niri
assert_no_package noctalia
assert_no_package greetd
assert_absent "$CASE_DIR/etc/voiders.conf"
assert_contains "$CASE_DIR/run.log" 'NOT maintained by Void Linux'
assert_contains "$CASE_DIR/home/.config/niri/config.kdl" 'spawn-at-startup "pipewire"'
assert_not_contains "$CASE_DIR/home/.config/niri/config.kdl" 'spawn-at-startup "noctalia"'
new_case noctalia_accept
run_case $'1\ny\nn'
assert_package noctalia
assert_contains "$CASE_DIR/home/.config/niri/config.kdl" '^spawn-at-startup "noctalia" "--daemon"$'
assert_contains "$CASE_DIR/etc/greetd.toml" '^command = ".*/noctalia-greeter-session"$'
assert_contains "$CASE_DIR/etc/greetd.toml" '^user = "_greeter"$'
assert_contains "$CASE_DIR/run.log" 'Noctalia Greeter configured'
assert_link "$CASE_DIR/services/greetd" "$CASE_DIR/sv/greetd"
new_case stock_greetd
cat > "$CASE_DIR/etc/greetd.toml" <<'EOF_STOCK_GREETD'
[terminal]
# Packaged greetd default
vt = 7

[default_session]
command = "agreety --cmd /bin/sh"
user = "_greeter"
EOF_STOCK_GREETD
cp "$CASE_DIR/etc/greetd.toml" "$CASE_DIR/stock-original"
run_case $'1\ny\nn'
cmp "$CASE_DIR/stock-original" "$CASE_DIR/etc/greetd.toml.void-desktop-setup.bak" || fail 'stock greetd backup differs'
assert_contains "$CASE_DIR/etc/greetd.toml" '^command = ".*/noctalia-greeter-session"$'
assert_link "$CASE_DIR/services/greetd" "$CASE_DIR/sv/greetd"
snapshot > "$CASE_DIR/before"
run_case $'1\nn'
snapshot > "$CASE_DIR/after"
cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'stock greetd repeat changed files'
new_case custom_greetd
printf '[default_session]\ncommand = "custom-greeter"\nuser = "_greeter"\n' > "$CASE_DIR/etc/greetd.toml"
run_case $'1\ny\nn'
assert_contains "$CASE_DIR/run.log" 'Existing greetd configuration preserved'
assert_contains "$CASE_DIR/run.log" 'greeter integration requires manual validation'
assert_absent "$CASE_DIR/services/greetd"
assert_absent "$CASE_DIR/etc/greetd.toml.void-desktop-setup.bak"
new_case noctalia_existing_repo
printf '# existing\nrepository=https://repo.voiders.dev\n' > "$CASE_DIR/etc/other.conf"
run_case $'1\nn'
assert_package noctalia
assert_absent "$CASE_DIR/etc/voiders.conf"
assert_not_contains "$CASE_DIR/run.log" 'Add this third-party repository'
new_case noctalia_custom_repo_target
printf '# custom repository\n' > "$CASE_DIR/etc/voiders.conf"
run_case $'1\ny\nn'
assert_contains "$CASE_DIR/etc/voiders.conf" '^# custom repository$'
assert_no_package noctalia

new_case preserve_custom
mkdir -p "$CASE_DIR/home/.config"/{niri,sway,xdg-desktop-portal,autostart,pipewire/pipewire.conf.d}
printf '// custom niri\n' > "$CASE_DIR/home/.config/niri/config.kdl"
printf '# custom sway\n' > "$CASE_DIR/home/.config/sway/config"
printf '[preferred]\ndefault=gtk;\n' > "$CASE_DIR/home/.config/xdg-desktop-portal/niri-portals.conf"
printf '# custom pipewire\n' > "$CASE_DIR/home/.config/pipewire/pipewire.conf"
printf '# custom system pipewire\n' > "$CASE_DIR/etc/pipewire/pipewire.conf"
printf '# custom startup\n' > "$CASE_DIR/home/.config/autostart/pipewire.desktop"
printf '# custom intel\n' > "$CASE_DIR/etc/intel.sh"
printf '# custom greetd\n' > "$CASE_DIR/etc/greetd.toml"
printf '# original backup\n' > "$CASE_DIR/etc/greetd.toml.void-desktop-setup.bak"
printf '# custom greeter\n' > "$CASE_DIR/noctalia-greeter/greeter.toml"
printf 'custom wallpaper\n' > "$CASE_DIR/backgrounds/void-desktop-setup-default.jpg"
printf '# custom wireplumber\n' > "$CASE_DIR/home/.config/pipewire/pipewire.conf.d/10-wireplumber.conf"
ln -s /missing/custom-pulse.conf "$CASE_DIR/home/.config/pipewire/pipewire.conf.d/20-pipewire-pulse.conf"
ln -s /missing/custom-alsa.conf "$CASE_DIR/etc/alsa/50-pipewire.conf"
find "$CASE_DIR/home" "$CASE_DIR/etc" "$CASE_DIR/noctalia-greeter" "$CASE_DIR/backgrounds" -type f -exec sha256sum {} + > "$CASE_DIR/custom-checksums"
run_case $'4\ny\nn'
sha256sum --quiet -c "$CASE_DIR/custom-checksums" || fail 'overwrote custom files'
assert_link "$CASE_DIR/home/.config/pipewire/pipewire.conf.d/20-pipewire-pulse.conf" /missing/custom-pulse.conf
assert_link "$CASE_DIR/etc/alsa/50-pipewire.conf" /missing/custom-alsa.conf
assert_contains "$CASE_DIR/run.log" 'Custom PipeWire configuration preserved'
run_case $'4\nn'
sha256sum --quiet -c "$CASE_DIR/custom-checksums" || fail 'second run overwrote custom files'

new_case pulseaudio_existing
echo pulseaudio > "$CASE_DIR/packages"
run_case $'2\nn'
assert_not_contains "$CASE_DIR/home/.config/sway/config" '^exec pipewire$'
assert_contains "$CASE_DIR/run.log" 'stop/remove pulseaudio manually'
new_case global_audio_existing
ln -s "$CASE_DIR/sv/pipewire" "$CASE_DIR/services/pipewire"
run_case $'3\nn'
assert_absent "$CASE_DIR/home/.config/autostart/pipewire.desktop"
assert_contains "$CASE_DIR/run.log" 'Existing global audio service pipewire'

# Real dry-run snapshots: no files, links, packages, groups or service actions change.
for decision in y n; do
    new_case "dry_$decision"
    GPU_OUTPUT='01:00.0 VGA compatible controller: NVIDIA Corporation AD106 [GeForce RTX 4060 Ti]'
    ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
    snapshot > "$CASE_DIR/before"
    run_case "$(printf '4\n%s\ny\ny\n' "$decision")" direct-dry
    snapshot > "$CASE_DIR/after"
    cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'dry-run modified system'
    [[ ! -s "$CASE_DIR/actions" ]] || fail 'dry-run executed a mutating mock'
    assert_contains "$CASE_DIR/run.log" '\[dry-run\] sv down'
    if [[ "$decision" == y ]]; then
        assert_contains "$CASE_DIR/run.log" '\[dry-run\] write .*/voiders.conf'
    else
        assert_not_contains "$CASE_DIR/run.log" '\[dry-run\] write .*/voiders.conf'
    fi
done

new_case piped_dry_run
snapshot > "$CASE_DIR/before"
run_case $'1\nn\ny' pipe-dry
snapshot > "$CASE_DIR/after"
cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'piped dry-run modified system'
[[ ! -s "$CASE_DIR/actions" ]] || fail 'piped dry-run executed mutations'
assert_contains "$CASE_DIR/run.log" 'Setup completed successfully'

new_case service_custom
mkdir "$CASE_DIR/services/bluetoothd"
run_case $'2\nn'
[[ -d "$CASE_DIR/services/bluetoothd" && ! -L "$CASE_DIR/services/bluetoothd" ]] || fail 'overwrote custom service directory'
assert_contains "$CASE_DIR/run.log" 'Preserving existing service entry'
new_case service_down
: > "$CASE_DIR/sv/elogind/down"
run_case $'2\nn'
assert_contains "$CASE_DIR/run.log" 'runit down flag; preserved'
[[ -f "$CASE_DIR/sv/elogind/down" ]] || fail 'removed down flag'
new_case audio_missing_example
rm "$CASE_DIR/examples/wireplumber/10-wireplumber.conf"
run_case $'2\nn'
assert_absent "$CASE_DIR/home/.config/pipewire/pipewire.conf.d/10-wireplumber.conf"
assert_contains "$CASE_DIR/run.log" 'Missing package example'
assert_not_contains "$CASE_DIR/home/.config/sway/config" '^exec pipewire$'
new_case missing_greeter
MISSING_CMDS=noctalia-greeter-session
run_case $'1\ny\nn'
assert_absent "$CASE_DIR/etc/greetd.toml"
assert_contains "$CASE_DIR/run.log" 'noctalia-greeter-session not found'
assert_absent "$CASE_DIR/services/greetd"
new_case repo_system_existing
printf 'repository=https://repo.voiders.dev\n' > "$CASE_DIR/system-repos/community.conf"
run_case $'1\nn'
assert_package noctalia
assert_absent "$CASE_DIR/etc/voiders.conf"
new_case noop_egl_seat
ln -s "$CASE_DIR/sv/elogind" "$CASE_DIR/services/elogind"
ln -s "$CASE_DIR/sv/seatd" "$CASE_DIR/services/seatd"
run_case $'2\nn'
assert_no_package seatd
assert_package elogind
assert_contains "$CASE_DIR/run.log" 'Existing seatd preserved'

new_case masked_system_repo
printf 'repository=https://repo.voiders.dev\n' > "$CASE_DIR/system-repos/community.conf"
printf '# repository disabled\n' > "$CASE_DIR/etc/community.conf"
run_case $'1\nn\nn'
assert_no_package noctalia
assert_contains "$CASE_DIR/run.log" 'Add this third-party repository'
assert_absent "$CASE_DIR/etc/voiders.conf"
new_case preserve_live_config_link
GPU_OUTPUT='01:00.0 VGA compatible controller: NVIDIA Corporation AD106 [GeForce RTX 4060 Ti]'
printf 'options nvidia-drm modeset=0\n' > "$CASE_DIR/etc/custom-nvidia.conf"
ln -s "$CASE_DIR/etc/custom-nvidia.conf" "$CASE_DIR/etc/nvidia.conf"
run_case $'3\nn'
assert_link "$CASE_DIR/etc/nvidia.conf" "$CASE_DIR/etc/custom-nvidia.conf"
assert_contains "$CASE_DIR/etc/custom-nvidia.conf" '^options nvidia-drm modeset=0$'
assert_contains "$CASE_DIR/run.log" 'Preserving existing configuration'

new_case installed_elogind_with_seatd
ln -s "$CASE_DIR/sv/seatd" "$CASE_DIR/services/seatd"
echo elogind > "$CASE_DIR/packages"
run_case $'2\nn'
assert_package turnstile
assert_absent "$CASE_DIR/services/elogind"
assert_contains "$CASE_DIR/run.log" 'elogind installed=true, elogind enabled=false, seatd enabled=true, turnstiled enabled=false'

# Installed packages and enabled services are independent states.
for compositor in 1 2; do
    new_case "installed_elogind_existing_stack_$compositor"
    printf 'elogind\nseatd\nturnstile\n' > "$CASE_DIR/packages"
    ln -s "$CASE_DIR/sv/seatd" "$CASE_DIR/services/seatd"
    ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
    printf 'manage_rundir = yes\nbackend = runit\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf"
    snapshot_session_stack > "$CASE_DIR/session-before"
    run_case "$(printf '%s\nn\nn\n' "$compositor")"
    assert_absent "$CASE_DIR/services/elogind"
    assert_no_package wireplumber-elogind
    assert_contains "$CASE_DIR/run.log" 'elogind installed=true, elogind enabled=false, seatd enabled=true, turnstiled enabled=true'
    for group in _seatd audio video; do assert_contains "$CASE_DIR/groups" "^$group$"; done
    snapshot_session_stack > "$CASE_DIR/session-after"
    cmp "$CASE_DIR/session-before" "$CASE_DIR/session-after" || fail 'changed existing alternative session stack'
    assert_not_contains "$CASE_DIR/actions" '^sv (down|up)'
    snapshot > "$CASE_DIR/before"
    cp "$CASE_DIR/actions" "$CASE_DIR/actions-before"
    run_case "$(printf '%s\nn\nn\n' "$compositor")"
    snapshot > "$CASE_DIR/after"
    cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'alternative session repeat changed state'
    cmp "$CASE_DIR/actions-before" "$CASE_DIR/actions" || fail 'alternative session repeat mutated system'
done

new_case only_elogind
echo elogind > "$CASE_DIR/packages"
ln -s "$CASE_DIR/sv/elogind" "$CASE_DIR/services/elogind"
snapshot_session_stack > "$CASE_DIR/session-before"
run_case $'2\nn'
assert_package wireplumber-elogind
assert_no_package turnstile
assert_no_package seatd
assert_contains "$CASE_DIR/run.log" 'elogind installed=true, elogind enabled=true, seatd enabled=false, turnstiled enabled=false'
snapshot_session_stack > "$CASE_DIR/session-after"
cmp "$CASE_DIR/session-before" "$CASE_DIR/session-after" || fail 'changed elogind-only stack'

new_case only_seatd_turnstile
printf 'seatd\nturnstile\n' > "$CASE_DIR/packages"
ln -s "$CASE_DIR/sv/seatd" "$CASE_DIR/services/seatd"
ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
printf 'manage_rundir = yes\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf"
snapshot_session_stack > "$CASE_DIR/session-before"
run_case $'2\nn'
assert_no_package elogind
assert_no_package wireplumber-elogind
assert_contains "$CASE_DIR/run.log" 'elogind installed=false, elogind enabled=false, seatd enabled=true, turnstiled enabled=true'
snapshot_session_stack > "$CASE_DIR/session-after"
cmp "$CASE_DIR/session-before" "$CASE_DIR/session-after" || fail 'changed seatd/turnstile-only stack'

# Both enabled: validate manage_rundir without changing/restarting either service.
for compositor in 2 3; do
    new_case "elogind_turnstile_safe_$compositor"
    printf 'elogind\nturnstile\n' > "$CASE_DIR/packages"
    ln -s "$CASE_DIR/sv/elogind" "$CASE_DIR/services/elogind"
    ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
    printf '# user configuration\n  manage_rundir\t=\tno  \ndebug = yes\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf"
    snapshot_session_stack > "$CASE_DIR/session-before"
    run_case "$(printf '%s\nn\n' "$compositor")"
    assert_contains "$CASE_DIR/run.log" 'elogind installed=true, elogind enabled=true, seatd enabled=false, turnstiled enabled=true'
    assert_contains "$CASE_DIR/run.log" 'turnstile manage_rundir=no confirmed'
    assert_not_contains "$CASE_DIR/run.log" 'cannot confirm manage_rundir=no'
    assert_no_package seatd
    snapshot_session_stack > "$CASE_DIR/session-after"
    cmp "$CASE_DIR/session-before" "$CASE_DIR/session-after" || fail 'changed compatible coexistence configuration'
    assert_not_contains "$CASE_DIR/actions" '^sv (down|up)'
    snapshot > "$CASE_DIR/before"
    run_case "$(printf '%s\nn\n' "$compositor")"
    snapshot > "$CASE_DIR/after"
    cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'coexistence repeat changed state'
done

for config in missing enabled commented duplicate inline invalid dangling oversized; do
    new_case "elogind_turnstile_uncertain_$config"
    printf 'elogind\nturnstile\n' > "$CASE_DIR/packages"
    ln -s "$CASE_DIR/sv/elogind" "$CASE_DIR/services/elogind"
    ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
    case "$config" in
        missing) ;;
        enabled) printf 'manage_rundir = yes\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf" ;;
        commented) printf '# manage_rundir = no\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf" ;;
        duplicate) printf 'manage_rundir = no\nmanage_rundir = yes\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf" ;;
        inline) printf 'manage_rundir = no # not a valid turnstile boolean\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf" ;;
        invalid) printf 'manage_rundir = NO\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf" ;;
        dangling) ln -s /missing/custom-turnstile.conf "$CASE_DIR/etc/turnstile/turnstiled.conf" ;;
        oversized) printf '%1024smanage_rundir = no\n' '' > "$CASE_DIR/etc/turnstile/turnstiled.conf" ;;
    esac
    snapshot_session_stack > "$CASE_DIR/session-before"
    run_case $'3\nn'
    assert_package kde-plasma
    assert_no_package seatd
    assert_contains "$CASE_DIR/run.log" 'cannot confirm manage_rundir=no'
    snapshot_session_stack > "$CASE_DIR/session-after"
    cmp "$CASE_DIR/session-before" "$CASE_DIR/session-after" || fail 'changed uncertain coexistence configuration'
    assert_not_contains "$CASE_DIR/actions" '^sv (down|up)'
done

new_case kde_turnstile_safe
echo turnstile > "$CASE_DIR/packages"
ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
printf 'manage_rundir=no\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf"
run_case $'3\nn'
assert_package elogind
assert_package kde-plasma
assert_link "$CASE_DIR/services/elogind" "$CASE_DIR/sv/elogind"
assert_link "$CASE_DIR/services/turnstiled" "$CASE_DIR/sv/turnstiled"
assert_contains "$CASE_DIR/etc/turnstile/turnstiled.conf" '^manage_rundir=no$'
assert_no_package seatd

new_case kde_turnstile_uncertain
printf 'elogind\nturnstile\n' > "$CASE_DIR/packages"
ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
printf 'manage_rundir=yes\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf"
snapshot_session_stack > "$CASE_DIR/session-before"
run_case $'3' apply 1
assert_no_package kde-plasma
assert_absent "$CASE_DIR/services/elogind"
assert_contains "$CASE_DIR/run.log" 'requires manual reconciliation of manage_rundir'
snapshot_session_stack > "$CASE_DIR/session-after"
cmp "$CASE_DIR/session-before" "$CASE_DIR/session-after" || fail 'KDE modified an uncertain runtime configuration'

new_case coexistence_dry_run
printf 'elogind\nturnstile\n' > "$CASE_DIR/packages"
ln -s "$CASE_DIR/sv/elogind" "$CASE_DIR/services/elogind"
ln -s "$CASE_DIR/sv/turnstiled" "$CASE_DIR/services/turnstiled"
printf 'manage_rundir=yes\n' > "$CASE_DIR/etc/turnstile/turnstiled.conf"
snapshot > "$CASE_DIR/before"
run_case $'3\nn' direct-dry
snapshot > "$CASE_DIR/after"
cmp "$CASE_DIR/before" "$CASE_DIR/after" || fail 'coexistence dry-run changed system'
[[ ! -s "$CASE_DIR/actions" ]] || fail 'coexistence dry-run executed mutations'
assert_contains "$CASE_DIR/run.log" 'cannot confirm manage_rundir=no'

# EOF/invalid choices terminate promptly under timeout, never wait forever.
new_case input_eof
run_case '' apply 1
new_case invalid_desktop
run_case $'9' apply 1
new_case repo_eof
run_case $'1' apply 1
assert_absent "$CASE_DIR/etc/voiders.conf"
new_case migration_eof
ln -s "$CASE_DIR/sv/dhcpcd" "$CASE_DIR/services/dhcpcd"
run_case $'2\ny' apply 1
assert_link "$CASE_DIR/services/dhcpcd" "$CASE_DIR/sv/dhcpcd"

echo "All $SCENARIOS mock smoke scenarios passed (apply, repeat and dry-run)."

#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="$REPO_DIR/void-desktop-setup.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -Eq "$pattern" "$file"; then
        echo "Assertion failed: expected pattern '$pattern' in $file"
        exit 1
    fi
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"
    if grep -Eq "$pattern" "$file"; then
        echo "Assertion failed: unexpected pattern '$pattern' in $file"
        exit 1
    fi
}

run_scenario() {
    local name="$1"
    local lspci_output="$2"
    local input_payload="$3"
    local missing_cmds="$4"
    local preexisting_nvidia_config="${5:-}"

    local scenario_dir="$TMP_ROOT/$name"
    local bin_dir="$scenario_dir/bin"
    local sv_dir="$scenario_dir/sv"
    local home_dir="$scenario_dir/home/tester"
    local service_dir="$scenario_dir/var_service"
    local xbps_log="$scenario_dir/xbps.log"
    local run_log="$scenario_dir/run.log"
    local input_file="$scenario_dir/input.txt"

    mkdir -p "$bin_dir" "$sv_dir" "$home_dir" "$service_dir" "$scenario_dir/etc" "$scenario_dir/backgrounds" "$scenario_dir/noctalia-greeter"
    mkdir -p "$sv_dir/dbus" "$sv_dir/bluetooth" "$sv_dir/greetd" "$sv_dir/NetworkManager"
    if [[ -n "$preexisting_nvidia_config" ]]; then
        printf '%s\n' "$preexisting_nvidia_config" > "$scenario_dir/etc/nvidia-modeset.conf"
    fi

    cat > "$bin_dir/xbps-install" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_XBPS_LOG"
exit 0
EOS

    cat > "$bin_dir/lspci" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$MOCK_LSPCI_OUTPUT"
EOS

    cat > "$bin_dir/logname" <<'EOS'
#!/usr/bin/env bash
echo tester
EOS

    cat > "$bin_dir/getent" <<'EOS'
#!/usr/bin/env bash
if [[ "$1" == "passwd" ]]; then
  echo "$2:x:1000:1000::${VDS_CURRENT_HOME}:/bin/bash"
  exit 0
fi
exit 1
EOS

    cat > "$bin_dir/who" <<'EOS'
#!/usr/bin/env bash
echo "tester pts/0 2026-01-01 00:00 (:0)"
EOS

    chmod +x "$bin_dir"/*

    cat > "$scenario_dir/bash_env.sh" <<'EOS'
command() {
    if [[ "${1:-}" == "-v" && -n "${2:-}" ]]; then
        case " ${MOCK_MISSING_CMDS:-} " in
            *" ${2} "*) return 1 ;;
        esac
    fi
    builtin command "$@"
}
EOS

    printf '%s\n' "$input_payload" > "$input_file"

    PATH="$bin_dir:$PATH" \
    BASH_ENV="$scenario_dir/bash_env.sh" \
    MOCK_MISSING_CMDS="$missing_cmds" \
    MOCK_LSPCI_OUTPUT="$lspci_output" \
    MOCK_XBPS_LOG="$xbps_log" \
    VDS_ALLOW_NON_ROOT=1 \
    VDS_CURRENT_USER=tester \
    VDS_CURRENT_HOME="$home_dir" \
    VDS_INPUT_FILE="$input_file" \
    VDS_DRY_RUN_EXEC=1 \
    VDS_SV_DIR="$sv_dir" \
    VDS_SERVICE_DIR="$service_dir" \
    VDS_XBPS_REPO_CONF="$scenario_dir/etc/10-voiders-community.conf" \
    VDS_NVIDIA_MODPROBE_CONF="$scenario_dir/etc/nvidia-modeset.conf" \
    VDS_GREETD_CONF="$scenario_dir/etc/greetd.toml" \
    VDS_BACKGROUND_DIR="$scenario_dir/backgrounds" \
    VDS_NOCTALIA_GREETER_DIR="$scenario_dir/noctalia-greeter" \
    bash "$TARGET_SCRIPT" --dry-run > "$run_log" 2>&1

    echo "$scenario_dir"
}

# 1) no GPU + Sway + no NetworkManager
scenario_no_gpu="$(run_scenario "no_gpu_sway" "" $'y\n2\nn' "")"
assert_contains "$scenario_no_gpu/xbps.log" '\bmesa-dri\b'
assert_contains "$scenario_no_gpu/xbps.log" '\bsway\b'
assert_not_contains "$scenario_no_gpu/xbps.log" '\bnoctalia\b'
assert_not_contains "$scenario_no_gpu/xbps.log" '\bgreetd\b'

# 2) Intel + Noctalia + NetworkManager
intel_line='00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 620 (rev 07)'
scenario_intel="$(run_scenario "intel_noctalia_nm" "$intel_line" $'1\ny' "qs")"
assert_contains "$scenario_intel/xbps.log" '\bgreetd\b'
assert_contains "$scenario_intel/xbps.log" '\bnoctalia\b'
assert_contains "$scenario_intel/xbps.log" '\bNetworkManager\b'
assert_contains "$scenario_intel/run.log" 'Noctalia Greeter is configured only when Niri\+Noctalia is selected'

# 3) AMD + all shells with repeated options (no duplicates)
amd_line='01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. \[AMD/ATI\] Navi 24 \[Radeon RX 6400\]'
scenario_amd="$(run_scenario "amd_all" "$amd_line" $'4 1 2\nn' "")"
assert_contains "$scenario_amd/xbps.log" '\bkde-plasma-desktop\b'
assert_contains "$scenario_amd/xbps.log" '\bsway\b'
assert_contains "$scenario_amd/xbps.log" '\bnoctalia\b'
if [[ "$(grep -Eo '\bniri\b' "$scenario_amd/xbps.log" | wc -l | tr -d ' ')" != "1" ]]; then
    echo "Assertion failed: niri installed more than once in repeated/all-shell selection"
    exit 1
fi

# 4) multi-GPU selection + NVIDIA path + KDE-only
multi_gpu_output=$'00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 620 (rev 07)\n01:00.0 VGA compatible controller: NVIDIA Corporation GP107M \[GeForce GTX 1050 Mobile\] (rev a1)'
scenario_nvidia="$(run_scenario "nvidia_kde" "$multi_gpu_output" $'1\n3\nn' "")"
assert_contains "$scenario_nvidia/xbps.log" '\bnvidia\b'
assert_contains "$scenario_nvidia/xbps.log" '\bkde-plasma-desktop\b'
assert_not_contains "$scenario_nvidia/xbps.log" '\bnoctalia\b'
assert_contains "$scenario_nvidia/run.log" 'module options only; kernel cmdline is not modified'

# 5) preserve an existing NVIDIA configuration before replacing it
scenario_nvidia_backup="$(run_scenario "nvidia_backup" "$multi_gpu_output" $'1\n3\nn' "" 'options nvidia-drm modeset=0')"
assert_contains "$scenario_nvidia_backup/run.log" 'preserve .*/nvidia-modeset.conf -> .*/nvidia-modeset.conf.void-desktop-setup.bak'

echo "All mock smoke tests passed."

#!/bin/bash
# void-desktop-setup.sh
# Void Linux - Minimal Desktop Setup / Setup Minimalista de Escritorio
#
# Usage / Uso:
#   curl -sL https://raw.githubusercontent.com/SirOtter0/void-desktop-setup/main/void-desktop-setup.sh | sudo bash
#   o bien:
#   git clone https://github.com/SirOtter0/void-desktop-setup.git
#   cd void-desktop-setup
#   sudo ./void-desktop-setup.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

if [[ $# -gt 0 ]]; then
    echo -e "${RED}Error: Unknown argument(s): $*${NC}"
    echo -e "${RED}Error: Argumento(s) desconocido(s): $*${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TTY_INPUT="${VDS_INPUT_FILE:-/dev/tty}"
TTY_FD=""
SV_DIR="${VDS_SV_DIR:-/etc/sv}"
SERVICE_DIR="${VDS_SERVICE_DIR:-/var/service}"
VOIDERS_REPO_CONF="${VDS_XBPS_REPO_CONF:-/etc/xbps.d/10-voiders-community.conf}"
NVIDIA_CONF="${VDS_NVIDIA_MODPROBE_CONF:-/etc/modprobe.d/nvidia-modeset.conf}"
INTEL_CONF="${VDS_INTEL_PROFILE_CONF:-/etc/profile.d/intel-gpu.sh}"
EXAMPLES_DIR="${VDS_EXAMPLES_DIR:-/usr/share/examples}"
APPLICATIONS_DIR="${VDS_APPLICATIONS_DIR:-/usr/share/applications}"
ALSA_CONF_DIR="${VDS_ALSA_CONF_DIR:-/etc/alsa/conf.d}"
ALSA_SHARE_DIR="${VDS_ALSA_SHARE_DIR:-/usr/share/alsa/alsa.conf.d}"
PIPEWIRE_SYSTEM_DIR="${VDS_PIPEWIRE_SYSTEM_DIR:-/etc/pipewire}"
XBPS_SYSTEM_REPO_DIR="${VDS_XBPS_SYSTEM_REPO_DIR:-/usr/share/xbps.d}"
GREETD_CONF="${VDS_GREETD_CONF:-/etc/greetd/config.toml}"
BACKGROUND_DIR="${VDS_BACKGROUND_DIR:-/usr/share/backgrounds}"
NOCTALIA_GREETER_DIR="${VDS_NOCTALIA_GREETER_DIR:-/var/lib/noctalia-greeter}"

CURRENT_USER=""
CURRENT_HOME=""
GPU=""

WANTS_NIRI=false
WANTS_NOCTALIA=false
WANTS_SWAY=false
WANTS_KDE=false
NETWORKMANAGER_SELECTED=false
NOCTALIA_READY=false
NVIDIA_DRIVER=""
SESSION_SERVICES=()
AUDIO_AUTOSTART=true

INSTALLED_LOG=()
ENABLED_SERVICES=()
SKIPPED_SERVICES=()

declare -A INSTALLED_PACKAGE_SET=()

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

log_step() {
    echo -e "${YELLOW}$1${NC}"
}

log_info() {
    echo -e "${BLUE}$1${NC}"
}

log_ok() {
    echo -e "${GREEN}$1${NC}"
}

log_warn() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

run_cmd() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
        return 0
    fi
    "$@"
}

make_parent_dir() {
    local parent dir
    parent="$(dirname "$1")"
    local new_user_dirs=()
    dir="$parent"
    while [[ -n "$CURRENT_HOME" && "$dir" == "$CURRENT_HOME/"* && ! -e "$dir" && ! -L "$dir" ]]; do
        new_user_dirs+=("$dir")
        dir="$(dirname "$dir")"
    done
    run_cmd mkdir -p "$parent"
    if [[ ${#new_user_dirs[@]} -gt 0 ]]; then
        run_cmd chown "$CURRENT_USER" "${new_user_dirs[@]}"
    fi
}

# Existing files (including dangling symlinks) always belong to the user.
write_file() {
    local target="$1" content
    content="$(cat)"
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ ! -L "$target" && -f "$target" ]] && cmp -s "$target" <(printf '%s\n' "$content"); then
            return 0
        fi
        log_warn "→ Preserving existing configuration / Conservando configuración existente: $target; review manually / revisar manualmente"
        return 0
    fi
    if $DRY_RUN; then
        echo "[dry-run] write $target"
        return 0
    fi
    make_parent_dir "$target"
    printf '%s\n' "$content" > "$target"
    if [[ -n "$CURRENT_HOME" && "$target" == "$CURRENT_HOME/"* ]]; then
        chown "$CURRENT_USER" "$target"
    fi
}

link_if_absent() {
    local source="$1" target="$2" owner="${3:-}"
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        return 0
    fi
    if [[ -e "$target" || -L "$target" ]]; then
        log_warn "→ Preserving existing configuration / Conservando configuración existente: $target; expected $source, review manually"
        return 0
    fi
    if [[ ! -f "$source" && $DRY_RUN == false ]]; then
        log_warn "→ Missing package example $source; skipping $target"
        return 0
    fi
    make_parent_dir "$target"
    run_cmd ln -s "$source" "$target"
    if [[ -n "$owner" ]]; then
        run_cmd chown -h "$owner" "$target"
    fi
}

add_user_group() {
    local group="$1"
    if ! getent group "$group" >/dev/null; then
        log_warn "→ Group $group unavailable; after package installation add $CURRENT_USER manually if needed"
        return 0
    fi
    if [[ " $(id -nG "$CURRENT_USER") " != *" $group "* ]]; then
        run_cmd usermod -aG "$group" "$CURRENT_USER"
    fi
}

service_enabled() {
    [[ -e "$SERVICE_DIR/$1" || -L "$SERVICE_DIR/$1" ]]
}

read_line_from_tty() {
    local __result_var="$1"
    local -n __result_ref="$__result_var"
    if [[ -z "$TTY_FD" ]]; then
        log_error "Error: Interactive input is required and $TTY_INPUT is not readable"
        log_error "Error: Se requiere entrada interactiva y $TTY_INPUT no es legible"
        exit 1
    fi
    IFS= read -r __result_ref <&"$TTY_FD"
}

read_array_from_tty() {
    local __result_var="$1"
    local -n __result_ref="$__result_var"
    if [[ -z "$TTY_FD" ]]; then
        log_error "Error: Interactive input is required and $TTY_INPUT is not readable"
        log_error "Error: Se requiere entrada interactiva y $TTY_INPUT no es legible"
        exit 1
    fi
    read -r -a __result_ref <&"$TTY_FD"
}

install_packages() {
    local filtered=()
    local pkg

    for pkg in "$@"; do
        if [[ -z "${INSTALLED_PACKAGE_SET[$pkg]:-}" ]]; then
            INSTALLED_PACKAGE_SET["$pkg"]=1
            if ! xbps-query -p pkgver "$pkg" >/dev/null 2>&1; then
                filtered+=("$pkg")
            fi
        fi
    done

    if [[ ${#filtered[@]} -eq 0 ]]; then
        return 0
    fi

    INSTALLED_LOG+=("${filtered[*]}")
    run_cmd xbps-install -S -y "${filtered[@]}"
}

enable_service_if_exists() {
    local svc="$1"
    local source_path="$SV_DIR/$svc"
    local link_path="$SERVICE_DIR/$svc"

    if [[ ! -d "$source_path" ]]; then
        SKIPPED_SERVICES+=("$svc")
        return 1
    fi

    if service_enabled "$svc"; then
        if [[ ! -L "$link_path" || "$(readlink -f "$link_path")" != "$(readlink -f "$source_path")" ]]; then
            log_warn "→ Preserving existing service entry $link_path; review manually"
            SKIPPED_SERVICES+=("$svc")
            return 1
        fi
    else
        run_cmd mkdir -p "$SERVICE_DIR" || return 1
        run_cmd ln -s "$source_path" "$link_path" || return 1
    fi

    if [[ -e "$source_path/down" ]]; then
        log_warn "→ $svc has a runit down flag; preserved, start it manually when ready"
    fi
    if [[ " ${ENABLED_SERVICES[*]} " != *" $svc "* ]]; then
        ENABLED_SERVICES+=("$svc")
    fi
    return 0
}

resolve_desktop_user() {
    if [[ -n "${VDS_CURRENT_USER:-}" ]]; then
        CURRENT_USER="$VDS_CURRENT_USER"
    elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        CURRENT_USER="$SUDO_USER"
    elif have_cmd logname; then
        CURRENT_USER="$(logname 2>/dev/null || true)"
    fi

    if [[ -z "$CURRENT_USER" || "$CURRENT_USER" == "root" ]]; then
        if have_cmd who; then
            CURRENT_USER="$(who -m 2>/dev/null | awk '{print $1}' || true)"
        fi
    fi

    if [[ -z "$CURRENT_USER" || "$CURRENT_USER" == "root" ]]; then
        log_error "Error: Could not detect non-root desktop user"
        log_error "Error: No se pudo detectar un usuario de escritorio no-root"
        exit 1
    fi

    if [[ -n "${VDS_CURRENT_HOME:-}" ]]; then
        CURRENT_HOME="$VDS_CURRENT_HOME"
    elif have_cmd getent; then
        CURRENT_HOME="$(getent passwd "$CURRENT_USER" | awk -F: '{print $6}' || true)"
    fi

    if [[ -z "$CURRENT_HOME" ]]; then
        log_error "Error: Could not resolve home directory for $CURRENT_USER"
        log_error "Error: No se pudo resolver el directorio home de $CURRENT_USER"
        exit 1
    fi

    log_ok "User detected / Usuario detectado: $CURRENT_USER"
    log_ok "Home detected / Home detectado: $CURRENT_HOME"
}

configure_voiders_repo() {
    local conf local_repo_dir
    local_repo_dir="$(dirname "$VOIDERS_REPO_CONF")"
    for conf in "$local_repo_dir"/*.conf "$XBPS_SYSTEM_REPO_DIR"/*.conf; do
        # XBPS ignores a system config when /etc/xbps.d contains the same filename.
        if [[ "$conf" == "$XBPS_SYSTEM_REPO_DIR/"* && ( -e "$local_repo_dir/${conf##*/}" || -L "$local_repo_dir/${conf##*/}" ) ]]; then
            continue
        fi
        if [[ -f "$conf" ]] && grep -Eq '^[[:space:]]*repository=https://repo\.voiders\.dev(/[^[:space:]#]*)?([[:space:]]*(#.*)?)?$' "$conf"; then
            log_info "→ repo.voiders.dev already configured / ya configurado: $conf"
            return 0
        fi
    done
    log_warn "Noctalia uses repo.voiders.dev: a third-party repository NOT maintained by Void Linux."
    log_warn "Noctalia usa repo.voiders.dev: repositorio de terceros NO mantenido oficialmente por Void Linux."
    echo "  Add this third-party repository? / ¿Añadir este repositorio de terceros? (y/N):"
    local accept_repo
    read_line_from_tty accept_repo
    if [[ "$accept_repo" != "y" && "$accept_repo" != "Y" ]]; then
        log_warn "→ Noctalia skipped / omitido; Niri will use official Void packages"
        return 1
    fi
    if [[ -e "$VOIDERS_REPO_CONF" || -L "$VOIDERS_REPO_CONF" ]]; then
        log_warn "→ Preserving $VOIDERS_REPO_CONF; configure the repository manually"
        return 1
    fi
    write_file "$VOIDERS_REPO_CONF" <<'EOF_REPO'
repository=https://repo.voiders.dev
EOF_REPO
}

setup_preflight() {
    if [[ "$EUID" -ne 0 ]]; then
        if ! $DRY_RUN || [[ "${VDS_ALLOW_NON_ROOT:-0}" != "1" ]]; then
            log_error "Error: This script must be run as root"
            log_error "Error: Este script debe ejecutarse como root"
            echo "Usage / Uso: sudo ./void-desktop-setup.sh"
            exit 1
        fi
        log_warn "[dry-run] Running non-root test mode / modo de prueba no-root"
    fi

    if [[ ! -r "$TTY_INPUT" ]]; then
        log_error "Error: Interactive mode requires a readable tty source ($TTY_INPUT)"
        log_error "Error: El modo interactivo requiere una fuente tty legible ($TTY_INPUT)"
        exit 1
    fi
    exec {TTY_FD}<"$TTY_INPUT"

    if ! have_cmd xbps-install || ! have_cmd xbps-query; then
        log_error "Error: xbps-install / xbps-query not found"
        log_error "Error: xbps-install / xbps-query no encontrados"
        exit 1
    fi

    if [[ -r /etc/os-release ]]; then
        local os_id
        # Runtime distribution metadata, not a project shell source.
        # shellcheck source=/dev/null
        os_id="$(. /etc/os-release && echo "${ID:-}")"
        if [[ "$os_id" != "void" && ! $DRY_RUN ]]; then
            log_error "Error: This script supports Void Linux only"
            log_error "Error: Este script solo soporta Void Linux"
            exit 1
        fi
    elif ! $DRY_RUN; then
        log_error "Error: /etc/os-release not found; cannot verify Void Linux"
        log_error "Error: /etc/os-release no encontrado; no se puede verificar Void Linux"
        exit 1
    fi

    if ! have_cmd lspci; then
        log_warn "lspci not found, installing pciutils... / lspci no encontrado, instalando pciutils..."
        install_packages pciutils
    fi

    if ! have_cmd lspci; then
        log_warn "lspci is still unavailable; GPU detection will fall back to unknown"
        log_warn "lspci aún no está disponible; la detección de GPU será desconocida"
    fi

    resolve_desktop_user
}

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Void Linux - Desktop Setup / Setup             ║${NC}"
    echo -e "${BLUE}║        Minimal Desktop Environment / Escritorio       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

detect_gpu() {
    log_step "[1/8] Detecting GPU(s) / Detectando GPU(s)..."

    local gpu_lines=()
    if have_cmd lspci; then
        mapfile -t gpu_lines < <(lspci -nn 2>/dev/null | grep -E "VGA|3D|Display" || true)
    fi

    local gpu_count="${#gpu_lines[@]}"
    echo "  GPUs detected / GPUs detectadas: $gpu_count"

    if [[ "$gpu_count" -gt 0 ]]; then
        local line
        for line in "${gpu_lines[@]}"; do
            [[ -n "$line" ]] && echo "    → $line"
        done
    fi

    if [[ "$gpu_count" -eq 0 ]]; then
        log_warn "⚠️  WARNING / ADVERTENCIA: No GPUs detected"
        echo "  Continue anyway? (y/n) / ¿Continuar de todos modos? (y/n):"
        local continue_anyway
        read_line_from_tty continue_anyway
        if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
            exit 1
        fi
        GPU=""
        return 0
    fi

    local selected_gpu="${gpu_lines[0]}"

    if [[ "$gpu_count" -gt 1 ]]; then
        log_warn "⚠️  Multiple GPUs detected / Múltiples GPUs detectadas"
        echo ""
        echo "  Select primary GPU / Selecciona GPU principal:"
        echo "  1) Dedicated GPU (NVIDIA/AMD) / GPU dedicada"
        echo "  2) Integrated GPU (Intel) / GPU integrada"
        echo "  3) Both (hybrid/PRIME) / Ambas (híbrido)"
        echo ""

        local gpu_choice
        read_line_from_tty gpu_choice

        case "$gpu_choice" in
            1)
                local gpu_line
                for gpu_line in "${gpu_lines[@]}"; do
                    local gpu_lower="${gpu_line,,}"
                    if [[ "$gpu_lower" == *"nvidia"* || "$gpu_lower" =~ (^|[^a-z])(amd|ati)([^a-z]|$) ]]; then
                        selected_gpu="$gpu_line"
                        break
                    fi
                done
                ;;
            2)
                local gpu_line
                for gpu_line in "${gpu_lines[@]}"; do
                    if [[ "${gpu_line,,}" == *"intel"* ]]; then
                        selected_gpu="$gpu_line"
                        break
                    fi
                done
                ;;
            3)
                selected_gpu="$(printf '%s\n' "${gpu_lines[@]}")"
                ;;
            *)
                log_warn "Invalid GPU option, using first detected GPU / Opción inválida, usando la primera GPU"
                ;;
        esac
    fi

    GPU="$selected_gpu"
    echo "  Using / Usando: $GPU"
    echo ""
}

nvidia_driver_for_gpu() {
    local description="${1,,}"
    if [[ "$description" =~ (^|[^a-z0-9])(tu|ga|ad|gh|gb)[0-9]{3}([^0-9]|$) || "$description" =~ geforce[[:space:]]rtx[[:space:]][2-5][0-9]{3} || "$description" =~ geforce[[:space:]]gtx[[:space:]]16[0-9]{2} ]]; then
        echo nvidia
    elif [[ "$description" =~ (^|[^a-z0-9])(gm|gp|gv)[0-9]{3}([^0-9]|$) ]]; then
        echo nvidia580
    elif [[ "$description" =~ (^|[^a-z0-9])gk[0-9]{3}([^0-9]|$) ]]; then
        echo nvidia470
    elif [[ "$description" =~ (^|[^a-z0-9])gf[0-9]{3}([^0-9]|$) ]]; then
        echo nvidia390
    fi
}

install_nvidia_driver() {
    local line branch="" candidate other
    while IFS= read -r line; do
        [[ "${line,,}" == *nvidia* ]] || continue
        candidate="$(nvidia_driver_for_gpu "$line")"
        if [[ -z "$candidate" || ( -n "$branch" && "$branch" != "$candidate" ) ]]; then
            log_warn "→ NVIDIA generation unknown, unsupported or mixed; using Mesa/Nouveau. Review installed NVIDIA blacklists manually."
            install_packages mesa-dri vulkan-loader
            return 0
        fi
        branch="$candidate"
    done <<< "$GPU"

    for other in nvidia nvidia580 nvidia470 nvidia390; do
        if [[ "$other" != "$branch" ]] && xbps-query -p pkgver "$other" >/dev/null 2>&1; then
            log_warn "→ Existing $other conflicts with $branch; preserve it and reconcile drivers manually"
            return 0
        fi
    done

    install_packages void-repo-nonfree
    run_cmd xbps-install -S
    if ! $DRY_RUN && ! xbps-query -R -p pkgver "$branch" >/dev/null 2>&1; then
        log_warn "→ $branch unavailable for this architecture/libc/repository; using Mesa/Nouveau. Review NVIDIA blacklists manually."
        install_packages mesa-dri vulkan-loader
        return 0
    fi
    log_info "→ NVIDIA branch / Rama NVIDIA: $branch"
    # nvidia-settings is a binary bundled inside each driver, not a separate package.
    install_packages "$branch" "${branch}-opencl" vulkan-loader
    NVIDIA_DRIVER="$branch"
    if [[ "$branch" != nvidia390 ]]; then
        write_file "$NVIDIA_CONF" <<'EOF_NVIDIA'
options nvidia-drm modeset=1
EOF_NVIDIA
        log_info "  Note: module options only; kernel cmdline is not modified. Existing options are preserved."
    fi
    if [[ "$branch" == nvidia390 || "$branch" == nvidia470 ]]; then
        log_warn "→ Legacy $branch lacks GBM for Niri/Sway; use Nouveau or a compatible X11 session."
    fi
}

install_gpu_drivers() {
    log_step "[2/8] Installing GPU drivers / Instalando drivers de GPU..."

    local gpu_lower="${GPU,,}"
    local recognized=false

    if [[ -z "$gpu_lower" ]]; then
        log_warn "→ No GPU identified, installing basic Mesa drivers / Sin GPU identificada, instalando Mesa básico"
        install_packages mesa-dri vulkan-loader
        return 0
    fi

    if [[ "$gpu_lower" =~ (^|[^a-z])(amd|ati)([^a-z]|$) ]]; then
        log_ok "→ AMD/ATI detected / detectada"
        install_packages mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi linux-firmware-amd
        recognized=true
    fi

    if [[ "$gpu_lower" == *"intel"* ]]; then
        log_ok "→ Intel detected / detectada"

        if [[ "$GPU" =~ (^|[[:space:]])HD[[:space:]]Graphics[[:space:]][1-6][0-9][0-9] || "$GPU" =~ (^|[[:space:]])HD[[:space:]]Graphics[[:space:]](2000|3000|4000|5000|510|520|530|540|550|5600|5700|5800|5900|6000|610|620|630|640|650) || "$GPU" =~ (GMA|Iron[[:space:]]Lake|Sandy[[:space:]]Bridge|Ivy[[:space:]]Bridge|Haswell|Broadwell|Skylake) ]]; then
            log_warn "→ Old Intel detected (pre-2018) / Intel antiguo detectado"
            install_packages mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel linux-firmware-intel libvdpau-va-gl libva-intel-driver
            write_file "$INTEL_CONF" <<'EOF_INTEL_OLD'
# Intel GPU (old / antiguo)
export LIBVA_DRIVER_NAME=i965
export VDPAU_DRIVER=va_gl
EOF_INTEL_OLD
        else
            log_ok "→ Modern Intel detected / Intel moderno detectado"
            install_packages mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel linux-firmware-intel libvdpau-va-gl intel-media-driver
            write_file "$INTEL_CONF" <<'EOF_INTEL_MODERN'
# Intel GPU (modern / moderno)
export LIBVA_DRIVER_NAME=iHD
export VDPAU_DRIVER=va_gl
EOF_INTEL_MODERN
        fi
        recognized=true
    fi

    if [[ "$gpu_lower" == *"nvidia"* ]]; then
        install_nvidia_driver
        recognized=true
    fi
    if $recognized; then
        return 0
    fi

    log_warn "→ Unknown GPU / GPU desconocida, installing basic drivers"
    install_packages mesa-dri vulkan-loader
}

select_shells() {
    log_step "[3/8] Select shells to install / Selecciona shells a instalar:"
    echo ""
    echo "  1) Niri + Noctalia (requires repo.voiders.dev)"
    echo "  2) Sway"
    echo "  3) KDE Plasma (Wayland)"
    echo "  4) Multiple / Múltiples (install all)"
    echo ""
    echo -e "${YELLOW}Enter numbers separated by space (e.g. 1 3 4):${NC}"
    echo -e "${YELLOW}Introduce números separados por espacio (ej. 1 3 4):${NC}"

    local shell_selection=()
    read_array_from_tty shell_selection

    local selection
    local valid=false
    for selection in "${shell_selection[@]}"; do
        case "$selection" in
            1)
                WANTS_NIRI=true
                WANTS_NOCTALIA=true
                valid=true
                ;;
            2)
                WANTS_SWAY=true
                valid=true
                ;;
            3)
                WANTS_KDE=true
                valid=true
                ;;
            4)
                WANTS_NIRI=true
                WANTS_NOCTALIA=true
                WANTS_SWAY=true
                WANTS_KDE=true
                valid=true
                ;;
            *)
                log_warn "→ Skipping invalid option / Opción inválida: $selection"
                ;;
        esac
    done

    if ! $valid; then
        log_error "Error: No valid shell option selected"
        log_error "Error: No se seleccionó una opción válida de shell"
        exit 1
    fi

    echo "  Installing selected shells / Instalando shells seleccionadas..."

    configure_session_management
    if $WANTS_NIRI; then
        install_packages niri
        if configure_voiders_repo; then
            install_packages greetd noctalia noctalia-greeter
            NOCTALIA_READY=true
        else
            WANTS_NOCTALIA=false
        fi
    fi

    if $WANTS_SWAY; then
        log_ok "→ Installing Sway"
        install_packages sway swaybg swaylock
    fi

    if $WANTS_KDE; then
        log_ok "→ Installing KDE Plasma"
        install_packages kde-plasma
    fi

    echo ""
    if $WANTS_NOCTALIA; then
        log_info "ℹ️  Noctalia Greeter is configured only when Niri+Noctalia is selected."
        log_info "ℹ️  Noctalia Greeter se configura solo cuando se selecciona Niri+Noctalia."
    else
        log_info "ℹ️  Noctalia Greeter is skipped for this selection."
        log_info "ℹ️  Noctalia Greeter se omite para esta selección."
    fi
}

configure_session_management() {
    # elogind supplies seats, PAM sessions and XDG_RUNTIME_DIR; no seatd is needed.
    # Preserve an existing seatd/turnstile stack for standalone compositors.
    if ! service_enabled elogind && { service_enabled seatd || service_enabled turnstiled; }; then
        if $WANTS_KDE || xbps-query -p pkgver elogind >/dev/null 2>&1; then
            log_error "→ KDE/installed elogind and existing seatd/turnstile setup requires manual reconciliation before rerunning"
            exit 1
        fi
        install_packages seatd turnstile
        SESSION_SERVICES=(seatd turnstiled)
        add_user_group _seatd
        add_user_group audio
        add_user_group video
    else
        install_packages elogind wireplumber-elogind
        SESSION_SERVICES=(elogind)
        if service_enabled seatd || service_enabled turnstiled; then
            log_warn "→ Existing parallel seat/session services; review seatd/turnstile and elogind configuration manually"
        fi
    fi
}

configure_pipewire() {
    local config_dir="$CURRENT_HOME/.config"
    local source
    if ! $DRY_RUN && { [[ ! -f "$EXAMPLES_DIR/wireplumber/10-wireplumber.conf" ]] || [[ ! -f "$EXAMPLES_DIR/pipewire/20-pipewire-pulse.conf" ]]; }; then
        AUDIO_AUTOSTART=false
        log_warn "→ Required PipeWire examples missing; reconcile package installation before starting audio"
    fi
    for source in "$PIPEWIRE_SYSTEM_DIR/pipewire.conf" "$config_dir/pipewire/pipewire.conf"; do
        if [[ -e "$source" || -L "$source" ]]; then
            log_warn "→ Custom PipeWire configuration preserved: $source; reconcile startup overrides manually"
        fi
    done
    link_if_absent "$EXAMPLES_DIR/wireplumber/10-wireplumber.conf" "$config_dir/pipewire/pipewire.conf.d/10-wireplumber.conf" "$CURRENT_USER"
    link_if_absent "$EXAMPLES_DIR/pipewire/20-pipewire-pulse.conf" "$config_dir/pipewire/pipewire.conf.d/20-pipewire-pulse.conf" "$CURRENT_USER"
    link_if_absent "$ALSA_SHARE_DIR/50-pipewire.conf" "$ALSA_CONF_DIR/50-pipewire.conf"
    link_if_absent "$ALSA_SHARE_DIR/99-pipewire-default.conf" "$ALSA_CONF_DIR/99-pipewire-default.conf"
    add_user_group bluetooth
    if xbps-query -p pkgver pulseaudio >/dev/null 2>&1; then
        AUDIO_AUTOSTART=false
        log_warn "→ PulseAudio installed: stop/remove pulseaudio manually before starting PipeWire; automatic startup skipped"
    fi
    for source in pipewire wireplumber pipewire-pulse pulseaudio; do
        if service_enabled "$source"; then
            AUDIO_AUTOSTART=false
            log_warn "→ Existing global audio service $source; migrate to user-session audio manually; automatic startup skipped"
        fi
    done
    if $WANTS_KDE && $AUDIO_AUTOSTART; then
        link_if_absent "$APPLICATIONS_DIR/pipewire.desktop" "$config_dir/autostart/pipewire.desktop" "$CURRENT_USER"
    fi
    log_info "→ PipeWire runs as the desktop user with WirePlumber and pipewire-pulse; requires a D-Bus session and XDG_RUNTIME_DIR"
}

configure_portals() {
    local portal_dir="$CURRENT_HOME/.config/xdg-desktop-portal"
    if $WANTS_KDE; then
        install_packages xdg-desktop-portal-kde
    fi
    if $WANTS_SWAY; then
        install_packages xdg-desktop-portal-wlr
        write_file "$portal_dir/sway-portals.conf" <<'EOF_SWAY_PORTALS'
[preferred]
default=gtk;
org.freedesktop.impl.portal.Screenshot=wlr;
org.freedesktop.impl.portal.ScreenCast=wlr;
EOF_SWAY_PORTALS
    fi
    if $WANTS_NIRI; then
        install_packages xdg-desktop-portal-gnome gnome-keyring
        write_file "$portal_dir/niri-portals.conf" <<'EOF_NIRI_PORTALS'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.FileChooser=gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
EOF_NIRI_PORTALS
    fi
}

install_essentials() {
    log_step "[4/8] Installing essential utilities / Instalando utilidades esenciales..."
    install_packages dbus fuzzel kitty pipewire wireplumber alsa-pipewire bluez libspa-bluetooth polkit xdg-desktop-portal xdg-desktop-portal-gtk accountsservice
    configure_pipewire
    configure_portals
    log_ok "→ Essential utilities installed / utilidades instaladas"
}

configure_network() {
    log_step "[5/8] Network configuration / Configurando red..."
    echo "  Do you want NetworkManager? (y/n) / ¿Quieres NetworkManager? (y/n):"

    local use_nm
    read_line_from_tty use_nm

    if [[ "$use_nm" != "y" && "$use_nm" != "Y" ]]; then
        log_info "→ NetworkManager skipped / omitido"
        return 0
    fi

    local conflicts=() entry svc
    local -A conflict_targets=()
    for entry in "$SERVICE_DIR"/*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        svc="${entry##*/}"
        case "$svc" in
            dhcpcd|dhcpcd-*|dhclient|dhclient-*|udhcpc|udhcpc-*|wpa_supplicant|wpa_supplicant-*|wicd|connman|connmand|iwd)
                if [[ ! -L "$entry" ]]; then
                    log_warn "→ Custom network service $entry; migrate manually before enabling NetworkManager"
                    return 0
                fi
                conflicts+=("$svc")
                conflict_targets["$svc"]="$(readlink "$entry")"
                ;;
        esac
    done
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warn "→ Conflicting network services / Servicios de red en conflicto: ${conflicts[*]}"
        log_warn "Stopping these services can disconnect this machine (including SSH). NetworkManager may need new connection settings."
        log_warn "Detener estos servicios puede cortar la conexión (incluido SSH). NetworkManager puede necesitar configurar la conexión."
        echo "  Stop/disable them and migrate to NetworkManager? / ¿Detenerlos y migrar a NetworkManager? (y/N):"
        local migrate
        read_line_from_tty migrate
        if [[ "$migrate" != y && "$migrate" != Y ]]; then
            log_warn "→ Network migration declined / migración rechazada; existing networking preserved"
            return 0
        fi
    fi

    # Finish downloads before stopping the current connection.
    install_packages NetworkManager network-manager-applet
    add_user_group network
    if [[ ! -d "$SV_DIR/NetworkManager" ]] || { service_enabled NetworkManager && [[ ! -L "$SERVICE_DIR/NetworkManager" || "$(readlink -f "$SERVICE_DIR/NetworkManager")" != "$(readlink -f "$SV_DIR/NetworkManager")" ]]; }; then
        log_warn "→ NetworkManager service missing/custom; existing networking preserved"
        return 0
    fi
    if [[ -e "$SV_DIR/NetworkManager/down" || -e "$SV_DIR/dbus/down" ]]; then
        log_warn "→ NetworkManager/D-Bus has a runit down flag; existing networking preserved, reconcile manually"
        return 0
    fi
    if ! enable_service_if_exists dbus; then
        log_warn "→ D-Bus unavailable; existing networking preserved"
        return 0
    fi
    local stopped=() previous
    for svc in "${conflicts[@]}"; do
        if ! run_cmd sv down "$SERVICE_DIR/$svc"; then
            log_error "→ Failed to stop $svc; preserving links and restarting previously stopped services"
            for previous in "${stopped[@]}"; do
                run_cmd sv up "$SERVICE_DIR/$previous" || log_warn "→ Failed to restart $previous; restore networking manually"
            done
            return 1
        fi
        stopped+=("$svc")
    done
    for svc in "${conflicts[@]}"; do
        run_cmd rm -- "$SERVICE_DIR/$svc"
    done
    if enable_service_if_exists NetworkManager; then
        NETWORKMANAGER_SELECTED=true
        log_ok "→ NetworkManager enabled / activado"
    else
        log_error "→ Could not enable NetworkManager; restoring previous network service links"
        for svc in "${conflicts[@]}"; do
            if ! service_enabled "$svc"; then
                run_cmd ln -s "${conflict_targets[$svc]}" "$SERVICE_DIR/$svc" || log_warn "→ Restore $svc manually"
            fi
            run_cmd sv up "$SERVICE_DIR/$svc" || log_warn "→ Failed to restart $svc; restore networking manually"
        done
        return 1
    fi
}

enable_core_services() {
    log_step "[6/8] Enabling services / Activando servicios..."

    local services=(dbus "${SESSION_SERVICES[@]}" bluetoothd)

    if $WANTS_NOCTALIA && have_cmd noctalia-greeter; then
        services+=(greetd)
    fi

    # Audio daemons belong to the user session, never global runit services.
    services+=(accounts-daemon)

    local svc
    for svc in "${services[@]}"; do
        enable_service_if_exists "$svc" || true
    done

    if [[ ${#ENABLED_SERVICES[@]} -gt 0 ]]; then
        log_ok "→ Enabled services / Servicios activados: ${ENABLED_SERVICES[*]}"
    else
        log_warn "→ No services enabled"
    fi

    if [[ ${#SKIPPED_SERVICES[@]} -gt 0 ]]; then
        log_warn "→ Missing services skipped / Servicios omitidos por falta: ${SKIPPED_SERVICES[*]}"
    fi
}

configure_noctalia_assets() {
    if ! $WANTS_NOCTALIA || ! $NOCTALIA_READY; then
        return 0
    fi

    log_step "[7/8] Configuring Noctalia Greeter assets / Configurando recursos de Noctalia Greeter..."

    local wallpaper_path="$BACKGROUND_DIR/void-desktop-setup-default.jpg"
    if [[ -f "$SCRIPT_DIR/void-desktop-setup-default.jpg" ]]; then
        if [[ -e "$wallpaper_path" || -L "$wallpaper_path" ]]; then
            if ! cmp -s "$SCRIPT_DIR/void-desktop-setup-default.jpg" "$wallpaper_path"; then
                log_warn "→ Preserving existing wallpaper: $wallpaper_path"
            fi
        else
            run_cmd mkdir -p "$BACKGROUND_DIR"
            run_cmd cp "$SCRIPT_DIR/void-desktop-setup-default.jpg" "$wallpaper_path"
        fi
    else
        log_warn "→ Local wallpaper not found; skipping copy / wallpaper local no encontrado"
    fi

    if have_cmd noctalia-greeter; then
        write_file "$GREETD_CONF" <<'EOF_GREETD'
[terminal]
vt = 1

[default_session]
command = "noctalia-greeter"
user = "greeter"
EOF_GREETD

        if [[ -d "$NOCTALIA_GREETER_DIR" || $DRY_RUN == true ]]; then
            write_file "$NOCTALIA_GREETER_DIR/greeter.toml" <<'EOF_GREETER'
[appearance]
scheme = "Synced"
theme_mode = "dark"

[appearance.wallpaper]
path = "/usr/share/backgrounds/void-desktop-setup-default.jpg"
fill_mode = "cover"
EOF_GREETER
            log_ok "→ Noctalia Greeter files configured / archivos configurados"
        else
            log_warn "→ Noctalia greeter directory missing; review package layout manually"
            log_warn "→ Falta directorio de Noctalia greeter; revisa el paquete manualmente"
        fi
    else
        NOCTALIA_READY=false
        log_warn "→ noctalia-greeter binary not found; greetd not auto-configured"
        log_warn "→ binario noctalia-greeter no encontrado; greetd no se configuró automáticamente"
    fi
}

append_session_startup() {
    if $DRY_RUN; then
        echo "[dry-run] startup in $1: $2"
    else
        printf '\n%s\n' "$2" >> "$1"
    fi
}

configure_shell_files() {
    log_step "[8/8] Creating shell configurations / Creando configuraciones de shell..."

    if $WANTS_NIRI && have_cmd niri; then
        local niri_dir="$CURRENT_HOME/.config/niri"
        local niri_cfg="$niri_dir/config.kdl"
        if [[ -e "$niri_cfg" || -L "$niri_cfg" ]]; then
            log_warn "→ Preserving existing Niri configuration: $niri_cfg; ensure user-session PipeWire startup manually"
        else
            if $WANTS_NOCTALIA && have_cmd qs; then
                write_file "$niri_cfg" <<'EOF_NIRI_QS'
// Niri - Minimal default config
environment {
    XCURSOR_SIZE "24"
}

spawn-at-startup "qs" "-c" "noctalia-shell"

input {
    keyboard {
        xkb {
            layout "es"
        }
    }
}

binds {
    Mod+Return { spawn "kitty"; }
    Mod+Q { close-window; }
    Mod+Shift+E { spawn "fuzzel"; }
}
EOF_NIRI_QS
            else
                write_file "$niri_cfg" <<'EOF_NIRI'
// Niri - Minimal default config
environment {
    XCURSOR_SIZE "24"
}

input {
    keyboard {
        xkb {
            layout "es"
        }
    }
}

binds {
    Mod+Return { spawn "kitty"; }
    Mod+Q { close-window; }
    Mod+Shift+E { spawn "fuzzel"; }
}
EOF_NIRI
                log_info "→ Niri config created without Noctalia auto-start (declined or qs unavailable)"
                log_info "→ Configuración Niri creada sin auto-inicio Noctalia (rechazado o qs no disponible)"
            fi

            if $AUDIO_AUTOSTART; then
                append_session_startup "$niri_cfg" 'spawn-at-startup "pipewire"'
            fi
        fi
    fi

    if $WANTS_SWAY; then
        local sway_cfg="$CURRENT_HOME/.config/sway/config"
        if [[ -e "$sway_cfg" || -L "$sway_cfg" ]]; then
            log_warn "→ Preserving existing Sway configuration: $sway_cfg; ensure user-session PipeWire and D-Bus environment import manually"
        else
            write_file "$sway_cfg" <<'EOF_SWAY'
include /etc/sway/config
exec dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
EOF_SWAY
            if $AUDIO_AUTOSTART; then
                append_session_startup "$sway_cfg" 'exec pipewire'
            fi
        fi
    fi
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          ✅ Setup completed successfully!              ║${NC}"
    echo -e "${GREEN}║          ✅ Setup completado exitosamente!             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BLUE}Features included / Características incluidas:${NC}"
    echo "  ✓ GPU driver step completed / Paso de drivers completado; review warnings / revisar advertencias"

    if $WANTS_NIRI && ! $WANTS_NOCTALIA; then
        echo "  ✓ Niri selected (official repository); Noctalia skipped"
    fi
    if $WANTS_NOCTALIA; then
        echo "  ✓ Niri + Noctalia selected / Niri + Noctalia seleccionados"
    fi

    if $WANTS_SWAY; then
        echo "  ✓ Sway selected / Sway seleccionado"
    fi

    if $WANTS_KDE; then
        echo "  ✓ KDE Plasma selected / KDE Plasma seleccionado"
    fi

    if $WANTS_NOCTALIA && $NOCTALIA_READY; then
        echo "  ✓ Noctalia Greeter configured / Noctalia Greeter configurado"
    elif $WANTS_NOCTALIA; then
        echo "  ⚠ Noctalia selected but greeter integration requires manual validation"
        echo "  ⚠ Noctalia seleccionado pero la integración de greeter requiere validación manual"
    fi

    if [[ -n "$NVIDIA_DRIVER" && "$NVIDIA_DRIVER" != nvidia390 ]]; then
        echo "  ✓ NVIDIA branch selected / Rama NVIDIA seleccionada: $NVIDIA_DRIVER"
        echo "  Review preserved module options / Revisa las opciones de módulo conservadas"
    fi

    if [[ ${#ENABLED_SERVICES[@]} -gt 0 ]]; then
        echo "  ✓ Services enabled: ${ENABLED_SERVICES[*]}"
    fi

    if $NETWORKMANAGER_SELECTED; then
        echo "  ✓ NetworkManager selected; conflicting runit services disabled only with consent"
    fi
    if [[ ${#SKIPPED_SERVICES[@]} -gt 0 ]]; then
        echo "  ⚠ Services skipped (missing): ${SKIPPED_SERVICES[*]}"
    fi

    echo ""
    echo -e "${YELLOW}Next steps / Próximos pasos:${NC}"
    echo "  1. Reboot: sudo reboot"

    echo "  Audio: wpctl status; pactl info (pulseaudio-utils). Review warnings about preserved configurations."
    echo "  TTY sessions: dbus-run-session niri --session; dbus-run-session sway (XDG_RUNTIME_DIR required)."
    if $WANTS_NOCTALIA; then
        echo "  2. Login at Noctalia Greeter / Inicia sesión en Noctalia Greeter"
        echo "  3. Validate session entries manually / Valida sesiones manualmente"
    else
        echo "  2. Start your selected desktop session from your preferred login manager"
        echo "  2. Inicia tu sesión de escritorio seleccionada desde tu gestor de login"
    fi

    echo ""
    echo -e "${BLUE}Repository / Repositorio: https://github.com/SirOtter0/void-desktop-setup${NC}"
    echo -e "${BLUE}Documentation / Documentación: https://docs.noctalia.dev/ & https://docs.voidlinux.org/${NC}"
    echo ""
}

main() {
    print_header
    setup_preflight
    detect_gpu
    install_gpu_drivers
    select_shells
    install_essentials
    configure_network
    enable_core_services
    configure_noctalia_assets
    configure_shell_files
    print_summary
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main
fi

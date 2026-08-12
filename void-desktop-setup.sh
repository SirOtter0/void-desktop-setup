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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TTY_INPUT="${VDS_INPUT_FILE:-/dev/tty}"
TTY_FD=""
SV_DIR="${VDS_SV_DIR:-/etc/sv}"
SERVICE_DIR="${VDS_SERVICE_DIR:-/var/service}"
VOIDERS_REPO_CONF="${VDS_XBPS_REPO_CONF:-/etc/xbps.d/10-voiders-community.conf}"
NVIDIA_CONF="${VDS_NVIDIA_MODPROBE_CONF:-/etc/modprobe.d/nvidia-modeset.conf}"
GREETD_CONF="${VDS_GREETD_CONF:-/etc/greetd/config.toml}"
BACKGROUND_DIR="${VDS_BACKGROUND_DIR:-/usr/share/backgrounds}"
NOCTALIA_GREETER_DIR="${VDS_NOCTALIA_GREETER_DIR:-/var/lib/noctalia-greeter}"

CURRENT_USER=""
CURRENT_HOME=""
GPU=""

WANTS_NOCTALIA=false
WANTS_SWAY=false
WANTS_KDE=false
NETWORKMANAGER_SELECTED=false
NOCTALIA_READY=false

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
        if [[ "${VDS_DRY_RUN_EXEC:-0}" == "1" ]]; then
            "$@" >/dev/null 2>&1 || true
        fi
        return 0
    fi
    "$@"
}

write_file() {
    local target="$1"
    if $DRY_RUN; then
        if [[ -e "$target" || -L "$target" ]]; then
            echo "[dry-run] preserve $target -> ${target}.void-desktop-setup.bak"
        fi
        echo "[dry-run] write $target"
        cat >/dev/null
        return 0
    fi

    preserve_existing_file "$target"
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

preserve_existing_file() {
    local target="$1"
    local backup_path="${target}.void-desktop-setup.bak"

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        return 0
    fi

    if [[ -e "$backup_path" || -L "$backup_path" ]]; then
        log_warn "→ Existing $target is being replaced; original backup already exists at $backup_path"
        return 0
    fi

    cp -a -- "$target" "$backup_path"
    log_warn "→ Existing $target saved to $backup_path"
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
            filtered+=("$pkg")
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

    if $DRY_RUN; then
        echo "[dry-run] enable service $svc"
    else
        mkdir -p "$SERVICE_DIR"
        ln -snf "$source_path" "$link_path"
    fi

    ENABLED_SERVICES+=("$svc")
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
    log_warn "Noctalia requires repo.voiders.dev / Noctalia requiere repo.voiders.dev"
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

    if ! have_cmd xbps-install; then
        log_error "Error: xbps-install not found"
        log_error "Error: xbps-install no encontrado"
        exit 1
    fi

    if [[ -r /etc/os-release ]]; then
        local os_id
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
        mapfile -t gpu_lines < <(lspci -nn 2>/dev/null | grep -E "VGA|3D" || true)
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
                selected_gpu="${gpu_lines[*]}"
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

install_gpu_drivers() {
    log_step "[2/8] Installing GPU drivers / Instalando drivers de GPU..."

    local gpu_lower="${GPU,,}"

    if [[ -z "$gpu_lower" ]]; then
        log_warn "→ No GPU identified, installing basic Mesa drivers / Sin GPU identificada, instalando Mesa básico"
        install_packages mesa-dri vulkan-loader
        return 0
    fi

    if [[ "$gpu_lower" =~ (^|[^a-z])(amd|ati)([^a-z]|$) ]]; then
        log_ok "→ AMD/ATI detected / detectada"
        install_packages mesa-dri mesa-vulkan-radeon mesa-vaapi linux-firmware-amd
        return 0
    fi

    if [[ "$gpu_lower" == *"intel"* ]]; then
        log_ok "→ Intel detected / detectada"

        if [[ "$GPU" =~ HD[[:space:]]Graphics[[:space:]][1-6][0-9][0-9] || "$GPU" =~ HD[[:space:]]Graphics[[:space:]](2000|3000|4000|5000|510|520|530|540|550|5600|5700|5800|5900|6000|610|620|630|640|650) || "$GPU" =~ (GMA|Iron[[:space:]]Lake|Sandy[[:space:]]Bridge|Ivy[[:space:]]Bridge|Haswell|Broadwell|Skylake) ]]; then
            log_warn "→ Old Intel detected (pre-2018) / Intel antiguo detectado"
            install_packages mesa-dri mesa-vulkan-intel intel-video-accel linux-firmware-intel libva-intel-driver
            write_file /etc/profile.d/intel-gpu.sh <<'EOF_INTEL_OLD'
# Intel GPU (old / antiguo)
export LIBVA_DRIVER_NAME=i965
export VDPAU_DRIVER=i965
EOF_INTEL_OLD
        else
            log_ok "→ Modern Intel detected / Intel moderno detectado"
            install_packages mesa-dri mesa-vulkan-intel intel-video-accel linux-firmware-intel intel-media-driver
            write_file /etc/profile.d/intel-gpu.sh <<'EOF_INTEL_MODERN'
# Intel GPU (modern / moderno)
export LIBVA_DRIVER_NAME=iHD
export VDPAU_DRIVER=va_gl
EOF_INTEL_MODERN
        fi
        return 0
    fi

    if [[ "$gpu_lower" == *"nvidia"* ]]; then
        log_warn "→ NVIDIA detected / detectada"
        install_packages void-repo-nonfree
        install_packages nvidia nvidia-opencl nvidia-settings

        echo "  Adding NVIDIA module options in modprobe.d / Añadiendo opciones de módulo NVIDIA en modprobe.d..."
        write_file "$NVIDIA_CONF" <<'EOF_NVIDIA'
options nvidia-drm modeset=1
EOF_NVIDIA

        log_info "  Note: this sets module options only; kernel cmdline is not modified."
        log_info "  Nota: esto solo define opciones de módulo; no modifica la línea de kernel."
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

    if $WANTS_NOCTALIA; then
        log_ok "→ Installing Niri + Noctalia"
        configure_voiders_repo
        install_packages greetd niri noctalia noctalia-greeter
        NOCTALIA_READY=true
    fi

    if $WANTS_SWAY; then
        log_ok "→ Installing Sway"
        install_packages sway swaybg swaylock
    fi

    if $WANTS_KDE; then
        log_ok "→ Installing KDE Plasma"
        install_packages kde-plasma-desktop
    fi

    echo ""
    if $WANTS_NOCTALIA; then
        log_info "ℹ️  Noctalia Greeter is configured only when Niri+Noctalia is selected."
        log_info "ℹ️  Noctalia Greeter se configura solo cuando se selecciona Niri+Noctalia."
    else
        log_info "ℹ️  Noctalia Greeter is not installed for Sway-only/KDE-only selections."
        log_info "ℹ️  Noctalia Greeter no se instala en selecciones solo Sway/KDE."
    fi
}

install_essentials() {
    log_step "[4/8] Installing essential utilities / Instalando utilidades esenciales..."
    install_packages fuzzel kitty pipewire wireplumber bluez polkit xdg-desktop-portal xdg-desktop-portal-gtk accountsservice
    log_ok "→ Essential utilities installed / utilidades instaladas"
}

configure_network() {
    log_step "[5/8] Network configuration / Configurando red..."
    echo "  Do you want NetworkManager? (y/n) / ¿Quieres NetworkManager? (y/n):"

    local use_nm
    read_line_from_tty use_nm

    if [[ "$use_nm" == "y" || "$use_nm" == "Y" ]]; then
        NETWORKMANAGER_SELECTED=true
        install_packages NetworkManager network-manager-applet
        if enable_service_if_exists NetworkManager; then
            log_ok "→ NetworkManager installed and enabled / instalado y activado"
        else
            log_warn "→ NetworkManager installed but service missing in $SV_DIR"
            log_warn "→ NetworkManager instalado pero sin servicio en $SV_DIR"
        fi
    else
        log_warn "→ NetworkManager not installed / no instalado (use iwd or manual config)"
        log_warn "→ NetworkManager no instalado (usa iwd o configuración manual)"
    fi
}

enable_core_services() {
    log_step "[6/8] Enabling services / Activando servicios..."

    local services=(dbus bluetooth)

    if $WANTS_NOCTALIA; then
        services+=(greetd)
    fi

    if $NETWORKMANAGER_SELECTED; then
        services+=(NetworkManager)
    fi

    # Optional on some Void installations; enable only when provided by packages.
    services+=(pipewire wireplumber accounts-daemon)

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
        if $DRY_RUN; then
            if [[ -e "$wallpaper_path" || -L "$wallpaper_path" ]]; then
                echo "[dry-run] preserve $wallpaper_path -> ${wallpaper_path}.void-desktop-setup.bak"
            fi
            echo "[dry-run] copy $SCRIPT_DIR/void-desktop-setup-default.jpg -> $wallpaper_path"
        else
            mkdir -p "$BACKGROUND_DIR"
            preserve_existing_file "$wallpaper_path"
            cp "$SCRIPT_DIR/void-desktop-setup-default.jpg" "$wallpaper_path"
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

configure_shell_files() {
    log_step "[8/8] Creating shell configurations / Creando configuraciones de shell..."

    if $WANTS_NOCTALIA && have_cmd niri; then
        local niri_dir="$CURRENT_HOME/.config/niri"
        local niri_cfg="$niri_dir/config.kdl"
        if $DRY_RUN; then
            echo "[dry-run] write $niri_cfg"
        else
            mkdir -p "$niri_dir"
        fi

        if have_cmd qs; then
            write_file "$niri_cfg" <<'EOF_NIRI_QS'
// Niri - Minimal default config
environment {
    XCURSOR_SIZE = 24
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
    XCURSOR_SIZE = 24
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
            log_warn "→ qs not found; Niri config created without Noctalia auto-start"
            log_warn "→ qs no encontrado; configuración de Niri creada sin auto-inicio de Noctalia"
        fi

        if ! $DRY_RUN; then
            chown -R "$CURRENT_USER":"$CURRENT_USER" "$niri_dir"
        fi

        log_ok "→ Niri configuration created / configuración creada"
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
    echo "  ✓ GPU drivers configured / drivers de GPU configurados"

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

    if [[ "${GPU,,}" == *"nvidia"* ]]; then
        echo "  ✓ NVIDIA module options configured in modprobe.d"
        echo "  ✓ Opciones de módulo NVIDIA configuradas en modprobe.d"
    fi

    if [[ ${#ENABLED_SERVICES[@]} -gt 0 ]]; then
        echo "  ✓ Services enabled: ${ENABLED_SERVICES[*]}"
    fi

    if [[ ${#SKIPPED_SERVICES[@]} -gt 0 ]]; then
        echo "  ⚠ Services skipped (missing): ${SKIPPED_SERVICES[*]}"
    fi

    echo ""
    echo -e "${YELLOW}Next steps / Próximos pasos:${NC}"
    echo "  1. Reboot: sudo reboot"

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

main

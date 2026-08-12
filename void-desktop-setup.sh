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

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Void Linux - Desktop Setup / Setup             ║${NC}"
echo -e "${BLUE}║        Minimal Desktop Environment / Escritorio       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check root / Verificar root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo -e "${RED}Error: Este script debe ejecutarse como root${NC}"
    echo "Usage / Uso: sudo ./void-desktop-setup.sh"
    exit 1
fi

# Get current user / Obtener usuario (usuario que usará el escritorio)
CURRENT_USER=${SUDO_USER:-$(who -m | awk '{print $1}')}
if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "root" ]; then
    echo -e "${RED}Error: Could not detect non-root user${NC}"
    echo -e "${RED}Error: No se pudo detectar un usuario no-root${NC}"
    exit 1
fi

echo -e "${GREEN}User detected / Usuario detectado: ${CURRENT_USER}${NC}"
echo ""

# ============================================
# 1. DETECCIÓN DE GPU
# ============================================
echo -e "${YELLOW}[1/8] Detecting GPU(s) / Detectando GPU(s)...${NC}"

ALL_GPUS=$(lspci -nn | grep -E "VGA|3D" || echo "")
GPU_COUNT=$(echo "$ALL_GPUS" | grep -c "VGA\|3D" 2>/dev/null || echo "0")

echo "  GPUs detected / GPUs detectadas: $GPU_COUNT"

if [ -n "$ALL_GPUS" ] && [ "$GPU_COUNT" -gt 0 ]; then
    echo "$ALL_GPUS" | while read -r line; do
        [ -n "$line" ] && echo "    → $line"
    done
fi

GPU=""
if [ "$GPU_COUNT" -eq 0 ] || [ -z "$ALL_GPUS" ]; then
    echo -e "${RED}⚠️  WARNING / ADVERTENCIA: No GPUs detected${NC}"
    echo "  Installing basic Mesa drivers... / Instalando drivers básicos de Mesa..."
    xbps-install -S -y mesa-dri vulkan-loader
    echo -e "${YELLOW}  ⚠️  You may need a dedicated GPU / Puede que necesites una GPU dedicada${NC}"
    echo ""
    echo "  Continue anyway? (y/n) / ¿Continuar de todos modos? (y/n):"
    read -r continue_anyway < /dev/tty
    if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
        exit 1
    fi
else
    if [ "$GPU_COUNT" -gt 1 ]; then
        echo -e "${YELLOW}⚠️  Multiple GPUs detected / Múltiples GPUs detectadas${NC}"
        echo ""
        echo "  Select primary GPU / Selecciona GPU principal:"
        echo "  1) Dedicated GPU (NVIDIA/AMD) / GPU dedicada"
        echo "  2) Integrated GPU (Intel) / GPU integrada"
        echo "  3) Both (hybrid/PRIME) / Ambas (híbrido)"
        echo ""
        read -r gpu_choice < /dev/tty
        
        case $gpu_choice in
            1)
                PRIMARY_GPU=$(echo "$ALL_GPUS" | grep -E "NVIDIA|AMD" | head -1)
                [ -z "$PRIMARY_GPU" ] && PRIMARY_GPU="$ALL_GPUS"
                ;;
            2)
                PRIMARY_GPU=$(echo "$ALL_GPUS" | grep -i "Intel" | head -1)
                [ -z "$PRIMARY_GPU" ] && PRIMARY_GPU="$ALL_GPUS"
                ;;
            *)
                PRIMARY_GPU="$ALL_GPUS"
                ;;
        esac
    else
        PRIMARY_GPU="$ALL_GPUS"
    fi
    
    GPU="$PRIMARY_GPU"
    echo "  Using / Usando: $GPU"
    echo ""
fi

# ============================================
# 2. INSTALACIÓN DE DRIVERS SEGÚN GPU
# ============================================
echo -e "${YELLOW}[2/8] Installing GPU drivers / Instalando drivers de GPU...${NC}"

if [ -z "$GPU" ]; then
    echo -e "  ${YELLOW}→ No GPU detected, using basic drivers / Sin GPU detectada, usando drivers básicos${NC}"
    xbps-install -S -y mesa-dri vulkan-loader

elif echo "$GPU" | grep -qi "amd\|ati"; then
    echo -e "  ${GREEN}→ AMD/ATI detected / detectada${NC}"
    xbps-install -S -y mesa-dri mesa-vulkan-radeon mesa-vaapi linux-firmware-amd

elif echo "$GPU" | grep -qi "intel"; then
    echo -e "  ${GREEN}→ Intel detected / detectada${NC}"
    if echo "$GPU" | grep -qiE \
        "HD Graphics [1-5][0-9][0-9]|HD Graphics 2000|HD Graphics 3000|HD Graphics 4000|\
         HD Graphics 5000|HD Graphics 6000|HD Graphics 510|HD Graphics 520|HD Graphics 530|\
         HD Graphics 540|HD Graphics 550|HD Graphics 5600|HD Graphics 5700|HD Graphics 5800|\
         HD Graphics 5900|HD Graphics 6000|HD Graphics 610|HD Graphics 620|HD Graphics 630|\
         HD Graphics 640|HD Graphics 650|GMA|Iron Lake|Sandy Bridge|Ivy Bridge|Haswell|Broadwell|Skylake"; then
        
        echo -e "  ${YELLOW}→ Old Intel detected (pre-2018) / Intel antiguo detectado${NC}"
        xbps-install -S -y mesa-dri mesa-vulkan-intel intel-video-accel linux-firmware-intel libva-intel-driver
        cat > /etc/profile.d/intel-gpu.sh << 'EOF'
# Intel GPU (old / antiguo)
export LIBVA_DRIVER_NAME=i965
export VDPAU_DRIVER=i965
EOF
    else
        echo -e "  ${GREEN}→ Modern Intel detected / Intel moderno detectado${NC}"
        xbps-install -S -y mesa-dri mesa-vulkan-intel intel-video-accel linux-firmware-intel intel-media-driver
        cat > /etc/profile.d/intel-gpu.sh << 'EOF'
# Intel GPU (modern / moderno)
export LIBVA_DRIVER_NAME=iHD
export VDPAU_DRIVER=va_gl
EOF
    fi

elif echo "$GPU" | grep -qi "nvidia"; then
    echo -e "  ${YELLOW}→ NVIDIA detected / detectada${NC}"
    xbps-install -S -y void-repo-nonfree
    xbps-install -S -y nvidia nvidia-opencl nvidia-settings

    echo "  Adding NVIDIA kernel module options / Añadiendo opciones de módulo NVIDIA..."
    cat > /etc/modprobe.d/nvidia-modeset.conf << 'EOF'
options nvidia-drm modeset=1 fbdev=1
EOF

else
    echo -e "  ${YELLOW}→ Unknown GPU / GPU desconocida, installing basic drivers${NC}"
    xbps-install -S -y mesa-dri vulkan-loader
fi

# ============================================
# 3. SELECCIÓN DE SHELLS
# ============================================
echo -e "${YELLOW}[3/8] Select shells to install / Selecciona shells a instalar:${NC}"
echo ""
echo "  1) Niri + Noctalia (recommended / recomendado)"
echo "  2) Sway"
echo "  3) KDE Plasma (Wayland)"
echo "  4) Multiple / Múltiples (select all you want)"
echo ""
echo -e "${YELLOW}Enter numbers separated by space (e.g. 1 3 4):${NC}"
echo -e "${YELLOW}Introduce números separados por espacio (ej. 1 3 4):${NC}"
read -r -a shell_selection < /dev/tty

echo "  Installing shells / Instalando shells..."
for selection in "${shell_selection[@]}"; do
    case $selection in
        1)
            echo -e "  ${GREEN}→ Installing Niri + Noctalia${NC}"
            # Añadir repo voiders-community para Noctalia
            echo "repository=https://repo.voiders.dev" > /etc/xbps.d/10-voiders-community.conf
            xbps-install -S -y niri noctalia noctalia-greeter
            ;;
        2)
            echo -e "  ${GREEN}→ Installing Sway${NC}"
            xbps-install -S -y sway swaybg swaylock
            ;;
        3)
            echo -e "  ${GREEN}→ Installing KDE Plasma${NC}"
            xbps-install -S -y kde-plasma-desktop
            ;;
        4)
            echo -e "  ${GREEN}→ Installing all available shells${NC}"
            echo "repository=https://repo.voiders.dev" > /etc/xbps.d/10-voiders-community.conf
            xbps-install -S -y niri noctalia noctalia-greeter sway kde-plasma-desktop
            ;;
        *)
            echo -e "  ${YELLOW}→ Skipping invalid option / Opción inválida${NC}"
            ;;
    esac
done

echo ""
echo -e "${BLUE}ℹ️  All installed shells will be available in Noctalia Greeter${NC}"
echo -e "${BLUE}ℹ️  Todas las shells instaladas estarán disponibles en Noctalia Greeter${NC}"
echo ""

# ============================================
# 4. UTILIDADES ESENCIALES
# ============================================
echo -e "${YELLOW}[4/8] Installing essential utilities / Instalando utilidades esenciales...${NC}"
xbps-install -S -y fuzzel kitty pipewire wireplumber bluez polkit xdg-desktop-portal xdg-desktop-portal-gtk accountsservice
echo -e "  ${GREEN}→ Essential utilities installed / utilidades instaladas${NC}"

# ============================================
# 5. GESTIÓN DE RED
# ============================================
echo -e "${YELLOW}[5/8] Network configuration / Configurando red...${NC}"
echo -e "  Do you want NetworkManager? (y/n) / ¿Quieres NetworkManager? (y/n):${NC}"
read -r use_nm < /dev/tty
if [ "$use_nm" = "y" ] || [ "$use_nm" = "Y" ]; then
    xbps-install -S -y network-manager network-manager-applet
    ln -sf /etc/sv/NetworkManager /var/service/
    echo -e "  ${GREEN}→ NetworkManager installed / instalado${NC}"
else
    echo -e "  ${YELLOW}→ NetworkManager not installed / no instalado (use iwd or configure manually)${NC}"
    echo -e "  ${YELLOW}→ NetworkManager no instalado (usa iwd o configura manualmente)${NC}"
fi

# ============================================
# 6. ACTIVAR SERVICIOS
# ============================================
echo -e "${YELLOW}[6/8] Enabling services / Activando servicios...${NC}"
for svc in dbus greetd pipewire wireplumber accounts-daemon bluetooth; do
    [ -d "/etc/sv/$svc" ] && ln -sf "/etc/sv/$svc" /var/service/
done
echo -e "  ${GREEN}→ Services enabled / Servicios activados${NC}"

# ============================================
# 7. WALLPAPER (SOLO SI NOCTALIA)
# ============================================
if command -v qs >/dev/null 2>&1 || [ -f /usr/bin/qs ]; then
    echo -e "${YELLOW}[7/8] Setting default wallpaper for Noctalia...${NC}"
    echo -e "${YELLOW}[7/8] Estableciendo wallpaper por defecto para Noctalia...${NC}"

    mkdir -p /usr/share/backgrounds

    if [ -f "./void-desktop-setup-default.jpg" ]; then
        cp ./void-desktop-setup-default.jpg \
           /usr/share/backgrounds/void-desktop-setup-default.jpg
    else
        if command -v curl &> /dev/null; then
            curl -L "https://raw.githubusercontent.com/void-linux/void-docs/master/src/assets/void-bg.jpg" \
                -o /usr/share/backgrounds/void-desktop-setup-default.jpg 2>/dev/null || true
        fi
    fi

    mkdir -p /var/lib/noctalia-greeter
    cat > /var/lib/noctalia-greeter/greeter.toml << 'EOF'
[appearance]
scheme = "Synced"
theme_mode = "dark"

[appearance.wallpaper]
path = "/usr/share/backgrounds/void-desktop-setup-default.jpg"
fill_mode = "cover"
EOF
    chmod 644 /var/lib/noctalia-greeter/greeter.toml

    echo -e "  ${GREEN}→ Default wallpaper set for Noctalia${NC}"
    echo -e "  ${GREEN}→ Wallpaper por defecto establecido para Noctalia${NC}"
fi

# ============================================
# 8. CONFIGURACIÓN MÍNIMA DE SHELLS
# ============================================
echo -e "${YELLOW}[8/8] Creating minimal shell configurations / Creando configuraciones mínimas...${NC}"

if command -v niri &> /dev/null; then
    mkdir -p "/home/$CURRENT_USER/.config/niri"
    cat > "/home/$CURRENT_USER/.config/niri/config.kdl" << 'EOF'
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
EOF
    chown -R "$CURRENT_USER":"$CURRENT_USER" "/home/$CURRENT_USER/.config/niri"
    echo -e "  ${GREEN}→ Niri configuration created / configuración creada${NC}"
fi

if command -v qs &> /dev/null; then
    mkdir -p "/home/$CURRENT_USER/.config/quickshell/noctalia-shell"
    cat > "/home/$CURRENT_USER/.config/quickshell/noctalia-shell/config.toml" << 'EOF'
[appearance]
scheme = "Synced"
theme_mode = "dark"

[appearance.wallpaper]
path = "/usr/share/backgrounds/void-desktop-setup-default.jpg"
fill_mode = "cover"

[sync]
auto_sync_greeter = true
EOF
    chown -R "$CURRENT_USER":"$CURRENT_USER" "/home/$CURRENT_USER/.config/quickshell"
    echo -e "  ${GREEN}→ Noctalia Shell configuration created / configuración creada${NC}"
fi

echo -e "  ${GREEN}→ Minimal shell configurations created / configuraciones mínimas creadas${NC}"

# ============================================
# RESUMEN FINAL
# ============================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Setup completed successfully!              ║${NC}"
echo -e "${GREEN}║          ✅ Setup completado exitosamente!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Features included / Características incluidas:${NC}"
echo "  ✓ GPU drivers configured / drivers de GPU configurados"
echo "  ✓ Selected shells installed / shells seleccionadas instaladas"
echo "  ✓ Noctalia Greeter with auto-sync / con sincronización automática"
echo "  ✓ Default wallpaper installed / wallpaper por defecto instalado"
echo "  ✓ Essential services enabled / servicios activados"

if echo "$GPU" | grep -qi "nvidia"; then
    echo "  ✓ NVIDIA kernel module options configured / opciones de módulo NVIDIA configuradas"
fi

echo ""
echo -e "${YELLOW}Next steps / Próximos pasos:${NC}"
echo "  1. Reboot: sudo reboot"
echo "  2. Login at Noctalia Greeter / Inicia sesión en Noctalia Greeter"
echo "  3. Select your preferred shell / Selecciona tu shell preferida"
echo "  4. Customize from Settings → Appearance / Personaliza desde Settings → Appearance"
echo ""
echo -e "${BLUE}Repository / Repositorio: https://github.com/SirOtter0/void-desktop-setup${NC}"
echo -e "${BLUE}Documentation / Documentación: https://docs.noctalia.dev/ & https://docs.voidlinux.org/${NC}"
echo ""

# Void Linux - Desktop Setup

[English](#english) | [Español](#español)

---

## English

Minimal post-installation script to set up Void Linux with your choice of Wayland compositors and desktop shells (Niri, Sway, KDE Plasma) plus Noctalia Greeter for a polished login experience.

All installed shells come from **official Void Linux repositories only**. No third-party repos, no building from source.

### ✨ Features

- 🔧 **Automatic GPU detection** (AMD, Intel, NVIDIA)
  - Detects old vs modern Intel GPUs
  - Handles multiple GPUs (hybrid systems)
  - Warns if no GPU detected
- 🎨 **Multiple shell support (official Void repos only)**
  - Niri + Noctalia (recommended)
  - Sway (Wayland compositor)
  - KDE Plasma (Wayland)
  - Install multiple shells and choose at login
- 🖼️ **Noctalia Greeter** with session selector
  - All installed shells appear in greeter
  - Choose different shell at each login
  - Auto-sync with shell appearance
- 🎯 **Void Linux inspired colors** (dark theme with red accents)
- ⌨️ **Minimal preconfigured shortcuts** (Spanish layout by default)
- 🚀 **Minimalist** (only essential utilities)

### 📋 Requirements

- Void Linux installed (base or minimal ISO)
- Internet connection
- User with sudo privileges
- ~2-4GB free space (more if installing multiple shells)

### 🚀 Installation

#### Quick install

```bash
sudo curl -sL https://raw.githubusercontent.com/SirOtter0/void-desktop-setup/main/void-desktop-setup.sh | bash
```

#### Manual install

```bash
git clone https://github.com/SirOtter0/void-desktop-setup.git
cd void-desktop-setup
sudo ./void-desktop-setup.sh
```

### ⚙️ What the script does

1. **Detects GPU** and installs appropriate drivers:
   - AMD: mesa-dri, mesa-vulkan-radeon, amdvlk
   - Intel: mesa-dri, mesa-vulkan-intel (i965 for old, iHD for modern)
   - NVIDIA: nvidia drivers + kernel parameters (nvidia-drm.modeset=1)
   - No GPU: basic mesa-dri + warning

2. **Lets you select shells** to install (all from official Void repos):
   - Niri + Noctalia (Noctalia from `voiders-community` repo)
   - Sway
   - KDE Plasma (Wayland)
   - Multiple shells (all appear in greeter)

3. **Installs essential utilities**:
   - greetd + Noctalia Greeter
   - pipewire + wireplumber (audio)
   - bluez (Bluetooth)
   - polkit (permissions)
   - xdg-desktop-portal (Wayland integration)
   - fuzzel (launcher)
   - kitty (terminal)

4. **Configures services** (runit):
   - dbus
   - greetd
   - pipewire
   - wireplumber
   - accounts-daemon
   - bluetooth (if available)

5. **Creates minimal configs**:
   - Niri: Spanish layout + basic shortcuts + auto-launch Noctalia
   - Noctalia Shell: dark theme + auto-sync with greeter + default wallpaper
   - Noctalia Greeter: same wallpaper + dark theme

6. **Downloads default wallpaper** (Void Linux red background)

### 🎨 Multiple Shells

When you install multiple shells (e.g., Niri + Sway + KDE), **all will be available in Noctalia Greeter**. You can choose a different shell at each login!

This is perfect for:
- Testing different Wayland compositors
- Having a fallback if one fails
- Sharing the PC with different user preferences

### 🎯 Default Configuration

#### Niri
- Spanish keyboard layout
- Basic shortcuts:
  - `Mod+Return`: terminal (kitty)
  - `Mod+Q`: close window
  - `Mod+Shift+E`: launcher (fuzzel)
  - `Mod+F1-F3`: volume control
  - `Mod+F4-F5`: brightness control
- Auto-launch Noctalia Shell

#### Noctalia Shell
- Dark theme
- Auto-sync with greeter (wallpaper, colors)
- Default wallpaper (Void Linux red)
- Minimal config (customize from Settings)

#### Noctalia Greeter
- Same wallpaper as shell
- Dark theme with Void red accents
- Session selector (all installed shells)

### 🛠️ Customization

After installation, customize from:

- **Settings → Appearance**: colors, wallpaper, theme
- **Settings → Keybinds**: keyboard shortcuts
- **Settings → Plugins**: widgets and panels
- **Settings → Security**: auto-sync greeter

### ⚠️ Important Notes

#### NVIDIA GPUs

The script automatically adds kernel parameters:
- `nvidia-drm.modeset=1`
- `fbdev=1`

These are required for Wayland support on NVIDIA.

#### NetworkManager

The script asks if you want NetworkManager. If you answer "no", configure your network manually (iwd, dhcpcd, etc.).

### 📚 Useful Links

- [Noctalia Documentation](https://docs.noctalia.dev/)
- [Niri Documentation](https://github.com/niri-wm/niri)
- [Sway Documentation](https://swaywm.org/)
- [Void Linux Handbook](https://docs.voidlinux.org/)
- [Void Linux Download](https://voidlinux.org/download/)

### 🤝 Contributing

1. Fork the project.
2. Create your branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

### 📄 License

See the [LICENSE](LICENSE) file for license details.

### 🙏 Acknowledgments

- [Void Linux](https://voidlinux.org/) – Base distribution.
- [Niri](https://github.com/niri-wm/niri) – Scrollable tiling Wayland compositor.
- [Noctalia](https://github.com/noctalia-dev/noctalia) – Desktop shell.
- [Sway](https://swaywm.org/) – i3-compatible Wayland compositor.
- [KDE Plasma](https://kde.org/plasma-desktop) – Full-featured desktop environment.

---

## Español

Script de post-instalación minimalista para configurar Void Linux con tu elección de compositores Wayland y shells de escritorio (Niri, Sway, KDE Plasma) más Noctalia Greeter para una experiencia de login pulida.

Todas las shells instaladas provienen **únicamente de los repositorios oficiales de Void Linux**. Sin repos de terceros, sin compilar desde fuente.

### ✨ Características

- 🔧 **Detección automática de GPU** (AMD, Intel, NVIDIA)
  - Detecta Intel antiguo vs moderno.
  - Maneja múltiples GPUs (sistemas híbridos).
  - Avisa si no se detecta GPU.
- 🎨 **Soporte para múltiples shells (solo repos oficiales de Void)**
  - Niri + Noctalia (recomendado).
  - Sway (compositor Wayland).
  - KDE Plasma (Wayland).
  - Instala múltiples shells y elige en el login.
- 🖼️ **Noctalia Greeter** con selector de sesiones.
  - Todas las shells instaladas aparecen en el greeter.
  - Elige shell diferente en cada login.
  - Sincronización automática con la apariencia del shell.
- 🎯 **Colores inspirados en Void Linux** (tema oscuro con acentos rojos).
- ⌨️ **Atajos preconfigurados mínimos** (layout español por defecto).
- 🚀 **Minimalista** (solo utilidades esenciales).

### 📋 Requisitos

- Void Linux instalado (ISO base o minimal).
- Conexión a internet.
- Usuario con permisos sudo.
- ~2-4GB espacio libre (más si instalas múltiples shells).

### 🚀 Instalación

#### Instalación rápida

```bash
sudo curl -sL https://raw.githubusercontent.com/SirOtter0/void-desktop-setup/main/void-desktop-setup.sh | bash
```

#### Instalación manual

```bash
git clone https://github.com/SirOtter0/void-desktop-setup.git
cd void-desktop-setup
sudo ./void-desktop-setup.sh
```

### ⚙️ Qué hace el script

1. **Detecta GPU** e instala drivers apropiados:
   - AMD: mesa-dri, mesa-vulkan-radeon, amdvlk.
   - Intel: mesa-dri, mesa-vulkan-intel (i965 para antiguo, iHD para moderno).
   - NVIDIA: drivers nvidia + parámetros de kernel (`nvidia-drm.modeset=1`).
   - Sin GPU: mesa-dri básico + aviso.

2. **Permite seleccionar shells** a instalar (todas de repos oficiales de Void):
   - Niri + Noctalia.(Noctalia de `voiders-community` repo)
   - Sway.
   - KDE Plasma (Wayland).
   - Múltiples shells (todas aparecen en el greeter).

3. **Instala utilidades esenciales**:
   - greetd + Noctalia Greeter.
   - pipewire + wireplumber (audio).
   - bluez (Bluetooth).
   - polkit (permisos).
   - xdg-desktop-portal (integración Wayland).
   - fuzzel (lanzador).
   - kitty (terminal).

4. **Configura servicios** (runit):
   - dbus.
   - greetd.
   - pipewire.
   - wireplumber.
   - accounts-daemon.
   - bluetooth (si está disponible).

5. **Crea configuraciones mínimas**:
   - Niri: layout español + atajos básicos + auto-lanzar Noctalia.
   - Noctalia Shell: tema oscuro + auto-sincronizar con greeter + wallpaper por defecto.
   - Noctalia Greeter: mismo wallpaper + tema oscuro.

6. **Descarga wallpaper por defecto** (fondo rojo de Void Linux).

### 🎨 Múltiples Shells

Cuando instalas múltiples shells (ej: Niri + Sway + KDE), **todas estarán disponibles en Noctalia Greeter**. ¡Puedes elegir shell diferente en cada login!

Esto es perfecto para:
- Probar diferentes compositores Wayland.
- Tener un fallback si uno falla.
- Compartir el PC con diferentes preferencias de usuario.

### 🎯 Configuración por defecto

#### Niri
- Layout de teclado español.
- Atajos básicos:
  - `Mod+Return`: terminal (kitty).
  - `Mod+Q`: cerrar ventana.
  - `Mod+Shift+E`: lanzador (fuzzel).
  - `Mod+F1-F3`: control de volumen.
  - `Mod+F4-F5`: control de brillo.
- Auto-lanzar Noctalia Shell.

#### Noctalia Shell
- Tema oscuro.
- Auto-sincronización con greeter (wallpaper, colores).
- Wallpaper por defecto (rojo de Void Linux).
- Configuración mínima (personaliza desde Settings).

#### Noctalia Greeter
- Mismo wallpaper que el shell.
- Tema oscuro con acentos rojos de Void.
- Selector de sesión (todas las shells instaladas).

### 🛠️ Personalización

Después de la instalación, personaliza desde:

- **Settings → Appearance**: colores, wallpaper, tema.
- **Settings → Keybinds**: atajos de teclado.
- **Settings → Plugins**: widgets y paneles.
- **Settings → Security**: auto-sincronizar greeter.

### ⚠️ Notas importantes

#### GPUs NVIDIA

El script añade automáticamente parámetros al kernel:
- `nvidia-drm.modeset=1`.
- `fbdev=1`.

Son requeridos para soporte Wayland en NVIDIA.

#### NetworkManager

El script pregunta si quieres NetworkManager. Si respondes "no", configura tu red manualmente (iwd, dhcpcd, etc.).

### 📚 Enlaces útiles

- [Documentación de Noctalia](https://docs.noctalia.dev/)
- [Documentación de Niri](https://github.com/niri-wm/niri)
- [Documentación de Sway](https://swaywm.org/)
- [Void Linux Handbook](https://docs.voidlinux.org/)
- [Void Linux Download](https://voidlinux.org/download/)

### 🤝 Contribuir

1. Haz fork del proyecto.
2. Crea tu rama (`git checkout -b feature/AmazingFeature`).
3. Haz commit de tus cambios (`git commit -m 'Add some AmazingFeature'`).
4. Haz push a la rama (`git push origin feature/AmazingFeature`).
5. Abre un Pull Request.

### 📄 Licencia

Consulta el archivo [LICENSE](LICENSE) para los detalles de la licencia.

### 🙏 Agradecimientos

- [Void Linux](https://voidlinux.org/) – Distro base.

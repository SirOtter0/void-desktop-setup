# Void Linux - Desktop Setup

[English](#english) | [Español](#español)

---

## English

Minimal post-installation script for Void Linux with selectable desktop options (Niri + Noctalia, Sway, KDE Plasma).

### Package sources

- **Sway** and **KDE Plasma** are installed from official Void repositories.
- **Niri + Noctalia + Noctalia Greeter** require `https://repo.voiders.dev` (configured only when that option is selected).

### Features

- Interactive post-install workflow.
- GPU detection with driver installation in a dedicated step (AMD/Intel/NVIDIA/basic fallback).
- Optional shell selection: Niri+Noctalia, Sway, KDE, or all.
- Conditional Noctalia/Greetd setup (only when Noctalia is selected).
- Service enabling for runit with existence checks and clear enabled/skipped reporting.
- Optional NetworkManager installation and service enabling.

### Requirements

- Void Linux (base/minimal install).
- Internet access.
- Root execution (`sudo`), plus a non-root desktop user.
- Interactive terminal (`/dev/tty` readable), because the script prompts for choices.

### Installation

#### Quick install

```bash
curl -sL https://raw.githubusercontent.com/SirOtter0/void-desktop-setup/main/void-desktop-setup.sh | sudo bash
```

> `curl ... | sudo bash` keeps script execution as root and still allows interactive `/dev/tty` prompts.

#### Manual install

```bash
git clone https://github.com/SirOtter0/void-desktop-setup.git
cd void-desktop-setup
sudo ./void-desktop-setup.sh
```

### What the script does

1. **Preflight checks**:
   - root/non-root desktop user validation,
   - Void/xbps availability checks,
   - interactive tty checks,
   - `lspci` availability handling (`pciutils`).

2. **GPU detection and driver install**:
   - AMD: `mesa-dri mesa-vulkan-radeon mesa-vaapi linux-firmware-amd`
   - Intel: `mesa-dri mesa-vulkan-intel intel-video-accel linux-firmware-intel` plus old/new VA driver selection
   - NVIDIA: `void-repo-nonfree nvidia nvidia-opencl nvidia-settings`
   - Unknown/no GPU: `mesa-dri vulkan-loader`

3. **Desktop selection**:
   - `1` Niri + Noctalia (+ Noctalia Greeter, greetd)
   - `2` Sway
   - `3` KDE Plasma
   - `4` all above

4. **Essential utilities**:
   - `fuzzel kitty pipewire wireplumber bluez polkit xdg-desktop-portal xdg-desktop-portal-gtk accountsservice`

5. **NetworkManager (optional)**:
   - installs `NetworkManager network-manager-applet`
   - enables runit service only if `/etc/sv/NetworkManager` exists

6. **Service enabling (runit, conditional/existence-checked)**:
   - attempts: `dbus`, `bluetooth`, `greetd` (if Noctalia selected), `NetworkManager` (if selected), `pipewire`, `wireplumber`, `accounts-daemon`

7. **Noctalia-only config (conditional)**:
   - greetd config with `noctalia-greeter` command if binary is available,
   - greeter wallpaper/theme file only when relevant paths exist,
   - no greeter/session promises for Sway-only/KDE-only installations.

8. **Niri config**:
   - keyboard layout `es`
   - shortcuts:
     - `Mod+Return` terminal (`kitty`)
     - `Mod+Q` close window
     - `Mod+Shift+E` launcher (`fuzzel`)

### NVIDIA note

The script writes **module options** in `/etc/modprobe.d/nvidia-modeset.conf` (`options nvidia-drm modeset=1`).
It does **not** edit kernel command-line parameters automatically.

### Dry run

You can execute a dry run to preview actions:

```bash
sudo ./void-desktop-setup.sh --dry-run
```

### Tests (non-destructive)

A mock harness is provided:

```bash
bash -n /absolute/path/to/void-desktop-setup.sh
bash /absolute/path/to/tests/mock-smoke-tests.sh
```

The mock tests run without changing host services/packages and cover:
- no GPU,
- Intel/AMD/NVIDIA detection,
- single-shell and all-shell selections,
- NetworkManager yes/no paths.

### Limits of non-VM tests

Mock tests cannot fully validate real package metadata, real runit service content, or graphical session behavior. Validate on an actual Void graphical VM for final integration confidence.

### Useful links

- [Noctalia Documentation](https://docs.noctalia.dev/)
- [Void Linux Handbook](https://docs.voidlinux.org/)
- [Niri](https://github.com/niri-wm/niri)
- [Sway](https://swaywm.org/)
- [KDE Plasma](https://kde.org/plasma-desktop)

### License

See [LICENSE](LICENSE).

### Acknowledgments

- [Void Linux](https://voidlinux.org/)
- [Niri](https://github.com/niri-wm/niri)
- [Noctalia](https://github.com/noctalia-dev/noctalia)
- [Sway](https://swaywm.org/)
- [KDE Plasma](https://kde.org/plasma-desktop)

---

## Español

Script minimalista de post-instalación para Void Linux con opciones de escritorio seleccionables (Niri + Noctalia, Sway, KDE Plasma).

### Fuentes de paquetes

- **Sway** y **KDE Plasma** se instalan desde repositorios oficiales de Void.
- **Niri + Noctalia + Noctalia Greeter** requieren `https://repo.voiders.dev` (se configura solo si eliges esa opción).

### Características

- Flujo interactivo de post-instalación.
- Detección de GPU con instalación de drivers en un paso separado (AMD/Intel/NVIDIA/fallback básico).
- Selección opcional de shells: Niri+Noctalia, Sway, KDE o todas.
- Configuración condicional de Noctalia/Greetd (solo cuando se selecciona Noctalia).
- Activación de servicios para runit con verificación de existencia y reporte claro de activados/omitidos.
- Instalación opcional de NetworkManager y activación de su servicio.

### Requisitos

- Void Linux (instalación base/minimal).
- Acceso a internet.
- Ejecución como root (`sudo`) y usuario de escritorio no-root.
- Terminal interactiva (`/dev/tty` legible), ya que el script pide opciones.

### Instalación

#### Instalación rápida

```bash
curl -sL https://raw.githubusercontent.com/SirOtter0/void-desktop-setup/main/void-desktop-setup.sh | sudo bash
```

> `curl ... | sudo bash` mantiene la ejecución como root y permite los prompts interactivos por `/dev/tty`.

#### Instalación manual

```bash
git clone https://github.com/SirOtter0/void-desktop-setup.git
cd void-desktop-setup
sudo ./void-desktop-setup.sh
```

### Qué hace el script

1. **Preflight checks**:
   - validación root/usuario de escritorio no-root,
   - verificación de disponibilidad de Void/xbps,
   - verificación de tty interactivo,
   - manejo de disponibilidad de `lspci` (`pciutils`).

2. **Detección de GPU e instalación de drivers**:
   - AMD: `mesa-dri mesa-vulkan-radeon mesa-vaapi linux-firmware-amd`
   - Intel: `mesa-dri mesa-vulkan-intel intel-video-accel linux-firmware-intel` más selección VA old/new
   - NVIDIA: `void-repo-nonfree nvidia nvidia-opencl nvidia-settings`
   - GPU desconocida/sin GPU: `mesa-dri vulkan-loader`

3. **Selección de escritorio**:
   - `1` Niri + Noctalia (+ Noctalia Greeter, greetd)
   - `2` Sway
   - `3` KDE Plasma
   - `4` todas las anteriores

4. **Utilidades esenciales**:
   - `fuzzel kitty pipewire wireplumber bluez polkit xdg-desktop-portal xdg-desktop-portal-gtk accountsservice`

5. **NetworkManager (opcional)**:
   - instala `NetworkManager network-manager-applet`
   - activa el servicio runit solo si existe `/etc/sv/NetworkManager`

6. **Activación de servicios (runit, condicional y con verificación)**:
   - intenta: `dbus`, `bluetooth`, `greetd` (si se eligió Noctalia), `NetworkManager` (si se eligió), `pipewire`, `wireplumber`, `accounts-daemon`

7. **Configuración solo para Noctalia (condicional)**:
   - configuración de greetd con comando `noctalia-greeter` si el binario existe,
   - archivo de wallpaper/tema del greeter solo cuando las rutas relevantes existen,
   - sin promesas de greeter/sesiones para instalaciones solo Sway/KDE.

8. **Configuración de Niri**:
   - layout de teclado `es`
   - atajos:
     - `Mod+Return` terminal (`kitty`)
     - `Mod+Q` cerrar ventana
     - `Mod+Shift+E` lanzador (`fuzzel`)

### Nota sobre NVIDIA

El script escribe **opciones de módulo** en `/etc/modprobe.d/nvidia-modeset.conf` (`options nvidia-drm modeset=1`).
No modifica automáticamente parámetros de línea de kernel.

### Modo dry run

Puedes ejecutar un dry run para previsualizar acciones:

```bash
sudo ./void-desktop-setup.sh --dry-run
```

### Pruebas (no destructivas)

Se incluye un harness de mocks:

```bash
bash -n /ruta/absoluta/a/void-desktop-setup.sh
bash /ruta/absoluta/a/tests/mock-smoke-tests.sh
```

Las pruebas mock se ejecutan sin cambiar servicios/paquetes del host y cubren:
- sin GPU,
- detección Intel/AMD/NVIDIA,
- selección de shell única y de todas,
- rutas de NetworkManager sí/no.

### Límites sin VM

Las pruebas mock no validan completamente metadatos reales de paquetes, contenido real de servicios runit ni comportamiento gráfico de sesión. Para validación final, prueba en una VM gráfica real de Void.

### Enlaces útiles

- [Documentación de Noctalia](https://docs.noctalia.dev/)
- [Void Linux Handbook](https://docs.voidlinux.org/)
- [Niri](https://github.com/niri-wm/niri)
- [Sway](https://swaywm.org/)
- [KDE Plasma](https://kde.org/plasma-desktop)

### Licencia

Consulta [LICENSE](LICENSE).

### Agradecimientos

- [Void Linux](https://voidlinux.org/)
- [Niri](https://github.com/niri-wm/niri)
- [Noctalia](https://github.com/noctalia-dev/noctalia)
- [Sway](https://swaywm.org/)
- [KDE Plasma](https://kde.org/plasma-desktop)

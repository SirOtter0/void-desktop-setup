# Void Linux - Desktop Setup

[English](#english) | [Español](#español)

---

## English

Minimal, interactive post-installation script for Void Linux with selectable desktop options: Niri + optional Noctalia, Sway, KDE Plasma, or all three. The script retains `set -euo pipefail` and supports `--dry-run`.

### Requirements and installation

- Void Linux, internet access, root execution and a non-root desktop user.
- An interactive terminal (`/dev/tty`), including for dry runs and confirmations.
- Review the script before running it. Configuration and network migrations may need manual reconciliation.

```bash
git clone https://github.com/SirOtter0/void-desktop-setup.git
cd void-desktop-setup
sudo ./void-desktop-setup.sh
```

Quick installation remains available:

```bash
curl -sL https://raw.githubusercontent.com/SirOtter0/void-desktop-setup/main/void-desktop-setup.sh | sudo bash
```

The script reads prompts from `/dev/tty`, including when its source is piped into Bash. The desktop user is normally determined from `SUDO_USER` or the login session.

### Package sources and Noctalia consent

Niri, Sway and KDE (`kde-plasma`) use official Void packages. Noctalia and Noctalia Greeter use `https://repo.voiders.dev`, a **third-party repository not maintained by Void Linux**.

Choosing Niri + Noctalia (or all desktops) asks explicitly before adding that repository. Only `y`/`Y` accepts. Declining keeps Niri from the official repositories and skips Noctalia, its greeter and greetd integration. The same prompt is simulated in `--dry-run` without writing a repository file.

An existing active `repository=https://repo.voiders.dev` entry, including entries with a repository subpath, is reused from `/etc/xbps.d/*.conf` or `/usr/share/xbps.d/*.conf`; no duplicate or new consent prompt is added. System files masked by an `/etc/xbps.d` file of the same name are ignored, as in XBPS. A different existing file at `/etc/xbps.d/10-voiders-community.conf` is preserved, and adding Noctalia is skipped with a warning. XBPS remains responsible for repository signature checks.

### GPU drivers and Vulkan

The script reads `lspci -nn` VGA, 3D and Display controllers. With several GPUs, select the dedicated GPU, Intel, or both. Both installs the detected vendors' driver packages.

| GPU | Packages / selection |
| --- | --- |
| AMD | `mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi linux-firmware-amd` |
| Intel | `mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel linux-firmware-intel libvdpau-va-gl`, plus VA-API driver selection |
| NVIDIA Turing and newer | `nvidia`, including GeForce RTX 4060 Ti (Ada) |
| NVIDIA Maxwell, Pascal, Volta | `nvidia580`, including GP107M / GTX 1050 Mobile (Pascal) |
| NVIDIA Kepler | `nvidia470` |
| NVIDIA Fermi | `nvidia390` |
| NVIDIA Tesla and older, undetermined generation, incompatible mixed generations | Mesa/Nouveau fallback: `mesa-dri vulkan-loader` |
| Unknown/no GPU | `mesa-dri vulkan-loader` |

NVIDIA selection uses known chip codenames (TU/GA/AD/GH/GB, GM/GP/GV, GK, GF) and unambiguous modern GeForce RTX 20–50 / GTX 16 model names. Marketing names with ambiguous generations, such as GT 730 without a codename, do not select a legacy driver. Unrecognized future codenames also fall back safely.

Recognized NVIDIA branches use `void-repo-nonfree`, the corresponding `<driver>-opencl` package and `vulkan-loader`. `nvidia-settings` is bundled in the driver package, not installed as a separate package. Outside dry runs, the branch must exist in synchronized XBPS metadata; otherwise the script falls back to Mesa/Nouveau. A different already installed NVIDIA branch is preserved and requires manual migration.

For supported DRM branches, a new `/etc/modprobe.d/nvidia-modeset.conf` contains `options nvidia-drm modeset=1`. Existing configurations remain untouched. No DRM option is added for `nvidia390`; no kernel command line is edited. **`nvidia470` and `nvidia390` lack the GBM support needed by Niri/Sway**: use Nouveau or a compatible X11 session for that hardware.

Intel retains the existing HD/GMA/generation-name heuristic for `libva-intel-driver` (`i965`) versus `intel-media-driver` (`iHD`). A new `/etc/profile.d/intel-gpu.sh` selects VA-API and `VDPAU_DRIVER=va_gl`. An existing profile is preserved. The heuristic is not a complete Intel PCI-ID database.

### PipeWire and Bluetooth

Installs `pipewire wireplumber alsa-pipewire bluez libspa-bluetooth`. `libspa-bluetooth` is the current Void package for PipeWire Bluetooth audio. Enables the real `bluetoothd` service and adds the desktop user to `bluetooth`; pairing and selecting headset profiles remain user actions.

PipeWire, WirePlumber and pipewire-pulse run **in the user session**, never as new global runit services. Following the Void Handbook, creates absent links:

- `~/.config/pipewire/pipewire.conf.d/10-wireplumber.conf` → `/usr/share/examples/wireplumber/10-wireplumber.conf`.
- `~/.config/pipewire/pipewire.conf.d/20-pipewire-pulse.conf` → `/usr/share/examples/pipewire/20-pipewire-pulse.conf`.
- `/etc/alsa/conf.d/50-pipewire.conf` and `99-pipewire-default.conf` → corresponding files in `/usr/share/alsa/alsa.conf.d/`.

PipeWire then launches WirePlumber and its PulseAudio interface in the documented order. Applications using PulseAudio or ALSA have their respective interfaces prepared.

Plasma receives `~/.config/autostart/pipewire.desktop` linked to the packaged desktop file. New Niri configurations use `spawn-at-startup "pipewire"`; new Sway configurations include `/etc/sway/config`, start PipeWire and import the Wayland environment into the D-Bus activation environment. Existing compositor configurations are preserved with a reminder to integrate startup manually.

If `pulseaudio` is installed or a global audio service already exists, the script warns and skips adding automatic audio startup. Stop/remove PulseAudio and migrate global audio services manually before using PipeWire. Custom PipeWire configurations and conflicting links are preserved; reconcile their startup overrides manually. Missing required package examples also suppress automatic startup.

### Seats, sessions and portals

The default is `elogind` with `dbus` and `wireplumber-elogind`, providing seat access, login sessions and `XDG_RUNTIME_DIR` for Niri, Sway and Plasma. No additional seatd service or broad device-access groups are needed for this default.

An existing enabled seatd/turnstile stack without elogind is retained for Niri/Sway; missing components are installed and enabled, and the user receives `_seatd`, `audio` and `video` membership. Seatd handles seats, while turnstile supplies runtime directories and session management. KDE, or an already installed elogind without an enabled elogind service alongside this alternative stack, requires manual reconciliation before continuing. Existing parallel enabled session services are preserved with a warning; their configuration must be reviewed.

A graphical session needs a **user D-Bus bus** as well as `XDG_RUNTIME_DIR`. For a TTY session with elogind, use:

```bash
dbus-run-session niri --session
dbus-run-session sway
```

Use the display manager's appropriate session entry when available. Validate greetd/Noctalia session entries separately. The script does not configure SDDM or replace an existing login manager.

| Selected desktop | Portal backends and configuration |
| --- | --- |
| KDE Plasma | `xdg-desktop-portal-kde` + GTK fallback; packaged KDE selection |
| Sway | `xdg-desktop-portal-wlr` + GTK; `sway-portals.conf` routes screenshots/screencasts to wlroots and other interfaces to GTK |
| Niri | `xdg-desktop-portal-gnome` + GTK; `niri-portals.conf` routes access, notifications and file selection to GTK, avoiding a Nautilus requirement; also installs `gnome-keyring` for the Secret portal |

All selections include `xdg-desktop-portal` and `xdg-desktop-portal-gtk`. Backends are installed only for the selected desktops; selecting all installs all three with desktop-specific routing. Existing portal configuration is never overwritten. Niri's portal support requires starting it as a session (`--session`); Sway's generated configuration imports `WAYLAND_DISPLAY` and `XDG_CURRENT_DESKTOP=sway`. Keyring unlocking/PAM integration is not configured automatically.

### NetworkManager and services

NetworkManager remains optional. Installs `NetworkManager network-manager-applet`, adds the user to `network`, and enables system D-Bus before NetworkManager.

Before enabling it, scans enabled runit entries for `dhcpcd`, `wpa_supplicant` (including interface-specific entries), `dhclient`, `udhcpc`, `iwd`, ConnMan and wicd. When conflicts exist, a separate explicit `y`/`Y` confirmation is required to stop/disable them. The warning explains that connectivity, including SSH, can drop and that new connection settings may be needed.

Downloads finish before migration. Only service symlinks are removed, after `sv down` succeeds; package/configuration files remain. Declining preserves existing networking and skips NetworkManager. Custom service directories or a missing/custom NetworkManager/D-Bus entry require manual migration. A stop failure keeps the original service links, attempts to restart any services already stopped, and aborts before enabling NetworkManager. A failure to create the NetworkManager service link attempts to restore the previous links and restart their services. A NetworkManager/D-Bus runit `down` flag also leaves the existing network in place. Repeat runs do not repeat the migration; dry runs only describe it.

Conflict detection covers enabled entries in `/var/service`, not independently launched daemons, custom service names or scripts in `rc.local`. Check those manually. NetworkManager's D-Bus-managed supplicant is distinct from a separately enabled `wpa_supplicant` runit service. No existing connection settings are converted automatically.

Other global services enabled when present are `dbus`, the chosen session manager, `bluetoothd`, `accounts-daemon`, and `greetd` only for accepted Noctalia with an available greeter binary. Missing services, custom service entries and existing runit `down` flags are reported and preserved.

### Configuration preservation and dry run

Existing files, custom symlinks (including dangling links), wallpapers and service entries are preserved. Identical files and expected symlinks are reused. New user configuration directories/files belong to the desktop user; existing trees are not recursively chowned. Installed packages are skipped. Previously created `.void-desktop-setup.bak` files remain untouched; the script no longer replaces files or makes new replacement backups.

The minimal new Niri configuration retains keyboard layout `es` and the Kitty/Fuzzel shortcuts. Quickshell/Noctalia startup is added only when Noctalia was accepted and `qs` is available. Wallpaper and greetd files are created only when absent and applicable.

```bash
sudo ./void-desktop-setup.sh --dry-run
```

Dry runs still collect choices/consent, read package/service state and report planned actions, but execute no modifying commands or file writes. When a package has not been installed, some service/example availability checks can only be resolved by a real installation.

### Tests and remaining validation

```bash
bash -n void-desktop-setup.sh tests/mock-smoke-tests.sh
bash tests/mock-smoke-tests.sh
shellcheck void-desktop-setup.sh tests/mock-smoke-tests.sh  # when installed
```

The mock harness runs package, group and service commands as mocks, and real file operations only in temporary directories. Apply runs source the actual script and replace platform preflight checks; direct and stdin-fed dry runs exercise its normal entrypoint, including the executable bit and piped installation path. Scenarios cover Intel/AMD, multiple NVIDIA generations, unknown/mixed GPUs, each desktop, audio/Bluetooth/Vulkan, session alternatives, network consent/conflicts/failure, Noctalia consent/reuse, custom files/links, repeated execution and dry-run snapshots. Input paths have timeouts so missing input cannot hang the suite.

**No VM or real hardware validation is claimed.** Before merging, validate on Void:

- XBPS availability for the target architecture/libc; NVIDIA DKMS against the actual kernel/headers, DRM/KMS and RTX 4060 Ti login. NVIDIA's nonfree packages are architecture/libc limited.
- Niri/Sway/Plasma login, seat permissions, D-Bus activation, runtime directories and portal file dialogs/screensharing.
- `wpctl status`; `pactl info` (install `pulseaudio-utils` for `pactl`); ALSA application audio; Bluetooth pairing and headset playback/microphone/profile switching.
- Network migration, Wi-Fi credentials, reconnect behavior and restart/reboot persistence, using a local console.
- Third-party Noctalia package layout, greeter user/permissions, Quickshell configuration and session entries. The greeter settings are retained from this project's original integration, not verified against real community packages.

Nouveau fallback does not remove existing NVIDIA packages/blacklists or guarantee Vulkan support. Legacy drivers may fail with current kernels and do not imply compatibility with every selected Wayland compositor. Preserved custom configuration can require manual integration even when the script completes.

### Documentation consulted

- Void Handbook: [NVIDIA](https://docs.voidlinux.org/config/graphical-session/graphics-drivers/nvidia.html), [AMD](https://docs.voidlinux.org/config/graphical-session/graphics-drivers/amd.html), [Intel](https://docs.voidlinux.org/config/graphical-session/graphics-drivers/intel.html).
- Void Handbook: [PipeWire](https://docs.voidlinux.org/config/media/pipewire.html), [Bluetooth](https://docs.voidlinux.org/config/bluetooth.html), [session/seat management](https://docs.voidlinux.org/config/session-management.html), [Wayland](https://docs.voidlinux.org/config/graphical-session/wayland.html).
- Void Handbook: [NetworkManager](https://docs.voidlinux.org/config/network/networkmanager.html), [portals](https://docs.voidlinux.org/config/graphical-session/portals.html), [KDE](https://docs.voidlinux.org/config/graphical-session/kde.html).
- Void Handbook: [XBPS repositories](https://docs.voidlinux.org/xbps/repositories/index.html), [configuration precedence / changing mirrors](https://docs.voidlinux.org/xbps/repositories/mirrors/changing.html).
- Official [Void package templates](https://github.com/void-linux/void-packages/tree/818cc6ea4ef4b9667e430270adc1451874053e11/srcpkgs) checked for current package names/subpackages, services and examples.
- Niri: [important software / portals](https://niri-wm.github.io/niri/Important-Software.html), [session startup](https://niri-wm.github.io/niri/Getting-Started.html), [portal defaults](https://github.com/niri-wm/niri/blob/main/resources/niri-portals.conf).

### License and acknowledgments

See [LICENSE](LICENSE). Thanks to [Void Linux](https://voidlinux.org/), [Niri](https://github.com/niri-wm/niri), [Noctalia](https://github.com/noctalia-dev/noctalia), [Sway](https://swaywm.org/) and [KDE Plasma](https://kde.org/plasma-desktop).

---

## Español

Script minimalista e interactivo de post-instalación de Void Linux: Niri + Noctalia opcional, Sway, KDE Plasma o los tres. Conserva `set -euo pipefail` y permite `--dry-run`.

### Requisitos e instalación

Necesitas Void Linux, internet, ejecución como root, un usuario de escritorio no-root y terminal interactiva (`/dev/tty`), también para simulaciones y confirmaciones. Revisa el script antes de ejecutarlo.

```bash
git clone https://github.com/SirOtter0/void-desktop-setup.git
cd void-desktop-setup
sudo ./void-desktop-setup.sh
```

También se mantiene la instalación rápida:

```bash
curl -sL https://raw.githubusercontent.com/SirOtter0/void-desktop-setup/main/void-desktop-setup.sh | sudo bash
```

Los prompts se leen de `/dev/tty`, incluso con el código canalizado a Bash. El usuario se determina normalmente mediante `SUDO_USER` o la sesión de login.

### Fuentes y consentimiento para Noctalia

Niri, Sway y KDE (`kde-plasma`) usan paquetes oficiales de Void. Noctalia y Noctalia Greeter utilizan `https://repo.voiders.dev`: **repositorio de terceros no mantenido oficialmente por Void Linux**.

Al seleccionar Niri + Noctalia o todos los escritorios, se solicita consentimiento explícito antes de añadirlo. Solo `y`/`Y` acepta. Rechazar mantiene Niri desde los repositorios oficiales y omite Noctalia, su greeter y la integración greetd. `--dry-run` simula la misma decisión sin escribir archivos.

Si ya existe una entrada activa `repository=https://repo.voiders.dev` (también con subruta) en `/etc/xbps.d/*.conf` o `/usr/share/xbps.d/*.conf`, se reutiliza sin duplicarla ni repetir la confirmación. Se ignoran archivos del sistema anulados por un archivo con el mismo nombre en `/etc/xbps.d`, como hace XBPS. Un archivo distinto existente en `/etc/xbps.d/10-voiders-community.conf` se conserva: se avisa y se omite Noctalia. XBPS sigue comprobando las firmas del repositorio.

### Drivers y Vulkan

Se detectan controladores VGA, 3D y Display con `lspci -nn`. Si hay varias GPU, puedes seleccionar la dedicada, Intel o ambas; ambas instala los drivers de los fabricantes detectados.

| GPU | Paquetes / selección |
| --- | --- |
| AMD | `mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi linux-firmware-amd` |
| Intel | `mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel linux-firmware-intel libvdpau-va-gl`, más selección VA-API |
| NVIDIA Turing y posteriores | `nvidia`, incluida RTX 4060 Ti (Ada) |
| NVIDIA Maxwell, Pascal y Volta | `nvidia580`, incluida GP107M / GTX 1050 Mobile (Pascal) |
| NVIDIA Kepler | `nvidia470` |
| NVIDIA Fermi | `nvidia390` |
| NVIDIA Tesla o anteriores, generación indeterminada o generaciones incompatibles mezcladas | Fallback Mesa/Nouveau: `mesa-dri vulkan-loader` |
| GPU desconocida o ausente | `mesa-dri vulkan-loader` |

La selección NVIDIA usa codenames conocidos (TU/GA/AD/GH/GB, GM/GP/GV, GK, GF) y nombres modernos inequívocos GeForce RTX 20–50 / GTX 16. Un nombre ambiguo como GT 730 sin codename no selecciona una rama legacy. Los codenames futuros desconocidos también usan fallback.

Las ramas reconocidas añaden `void-repo-nonfree`, el paquete `<driver>-opencl` correspondiente y `vulkan-loader`. `nvidia-settings` viene incluido en el driver; no se instala un paquete independiente con ese nombre. Fuera de `--dry-run`, se verifica que la rama exista en los metadatos XBPS sincronizados. Si no está disponible, se usa Mesa/Nouveau. Una rama NVIDIA distinta ya instalada se conserva y exige migración manual.

Para ramas con DRM compatible se crea, si no existe, `/etc/modprobe.d/nvidia-modeset.conf` con `options nvidia-drm modeset=1`. No se modifica la línea del kernel ni se añade esa opción para `nvidia390`. **`nvidia470` y `nvidia390` carecen del soporte GBM necesario para Niri/Sway**: usa Nouveau o una sesión X11 compatible.

Intel conserva la heurística HD/GMA/nombres de generación para elegir `libva-intel-driver` (`i965`) o `intel-media-driver` (`iHD`). Un perfil nuevo `/etc/profile.d/intel-gpu.sh` selecciona VA-API y `VDPAU_DRIVER=va_gl`; los perfiles existentes se conservan. No es una base de datos completa de IDs PCI Intel.

### PipeWire y Bluetooth

Se instalan `pipewire wireplumber alsa-pipewire bluez libspa-bluetooth`. `libspa-bluetooth` es el paquete actual de Void para audio Bluetooth con PipeWire. Se activa `bluetoothd` y se añade el usuario a `bluetooth`; el emparejamiento y la elección de perfiles se hacen en la sesión del usuario.

PipeWire, WirePlumber y pipewire-pulse funcionan **en la sesión del usuario**; no se añaden servicios runit globales de audio. Siguiendo el Handbook, se crean enlaces ausentes:

- `~/.config/pipewire/pipewire.conf.d/10-wireplumber.conf` → `/usr/share/examples/wireplumber/10-wireplumber.conf`.
- `~/.config/pipewire/pipewire.conf.d/20-pipewire-pulse.conf` → `/usr/share/examples/pipewire/20-pipewire-pulse.conf`.
- `/etc/alsa/conf.d/50-pipewire.conf` y `99-pipewire-default.conf` → sus archivos en `/usr/share/alsa/alsa.conf.d/`.

PipeWire inicia WirePlumber y la interfaz PulseAudio en el orden recomendado. Quedan preparadas las interfaces para aplicaciones PulseAudio y ALSA.

En Plasma se enlaza `~/.config/autostart/pipewire.desktop` al archivo del paquete. Las configuraciones nuevas de Niri usan `spawn-at-startup "pipewire"`. Las nuevas de Sway incluyen `/etc/sway/config`, arrancan PipeWire e importan el entorno Wayland a D-Bus. Si ya hay configuración del compositor, se conserva y se avisa para integrar el arranque manualmente.

Si está instalado `pulseaudio` o existe un servicio global de audio, se avisa y se omite añadir arranque automático. Detén/desinstala PulseAudio y migra los servicios globales manualmente antes de usar PipeWire. Las configuraciones personalizadas y enlaces diferentes se conservan y pueden necesitar reconciliación. Si faltan los ejemplos de paquetes necesarios, también se omite el arranque automático.

### Seats, sesiones y portales

Por defecto se usan `elogind`, `dbus` y `wireplumber-elogind`: proporcionan acceso al seat, sesiones y `XDG_RUNTIME_DIR` para Niri, Sway y Plasma. No se añade seatd ni se necesitan grupos amplios de acceso a dispositivos en esta opción.

Para Niri/Sway se conserva una pila seatd/turnstile ya activada sin elogind: se instalan/activan los componentes que falten y se añade el usuario a `_seatd`, `audio` y `video`. Seatd gestiona seats; turnstile proporciona directorios de runtime y sesiones. KDE, o elogind ya instalado pero sin servicio activado junto a esa pila alternativa, requiere reconciliación manual antes de continuar. Los servicios de sesión paralelos ya activados se conservan con una advertencia y deben revisarse.

La sesión gráfica necesita **D-Bus de usuario** y `XDG_RUNTIME_DIR`. Desde una TTY con elogind:

```bash
dbus-run-session niri --session
dbus-run-session sway
```

También puedes usar la entrada adecuada del gestor de login. Verifica las entradas greetd/Noctalia por separado. El script no configura SDDM ni reemplaza el gestor de login existente.

| Escritorio | Backends y configuración de portales |
| --- | --- |
| KDE Plasma | `xdg-desktop-portal-kde` + GTK como fallback; selección del paquete KDE |
| Sway | `xdg-desktop-portal-wlr` + GTK; `sway-portals.conf` dirige capturas/screencasting a wlroots y el resto a GTK |
| Niri | `xdg-desktop-portal-gnome` + GTK; `niri-portals.conf` usa GTK para acceso, notificaciones y archivos, evitando exigir Nautilus; instala también `gnome-keyring` para Secret |

Siempre se instalan `xdg-desktop-portal` y `xdg-desktop-portal-gtk`. Solo se añaden backends para los escritorios seleccionados; seleccionar todos instala los tres con rutas específicas por escritorio. Se conservan las configuraciones existentes. Niri necesita arrancar como sesión (`--session`); la configuración Sway generada importa `WAYLAND_DISPLAY` y `XDG_CURRENT_DESKTOP=sway`. No se configura automáticamente el desbloqueo del keyring ni su integración PAM.

### NetworkManager y servicios

NetworkManager es opcional. Se instalan `NetworkManager network-manager-applet`, se añade el usuario a `network` y se activa D-Bus antes de NetworkManager.

Se buscan entradas runit activadas de `dhcpcd`, `wpa_supplicant` (incluidas variantes por interfaz), `dhclient`, `udhcpc`, `iwd`, ConnMan y wicd. Si existen conflictos, se exige confirmación independiente `y`/`Y` antes de detenerlos/desactivarlos. Se advierte de que puede cortarse la conexión, incluido SSH, y de que habrá que configurar la conexión nueva.

Las descargas terminan antes de migrar. Solo se eliminan enlaces de servicio tras completar `sv down`; los paquetes/configuraciones permanecen. Rechazar conserva la red existente y omite NetworkManager. Directorios de servicio personalizados o entradas ausentes/personalizadas de NetworkManager/D-Bus requieren migración manual. Un fallo al detener conserva los enlaces originales, intenta reiniciar los servicios ya detenidos y aborta antes de activar NetworkManager. Si falla la creación del enlace de NetworkManager, se intenta restaurar los enlaces anteriores y reiniciar sus servicios. Un archivo runit `down` de NetworkManager/D-Bus también conserva la red existente. La segunda ejecución no repite la migración y `--dry-run` solo la describe.

La detección cubre `/var/service`: no detecta daemons lanzados por separado, nombres de servicio personalizados ni scripts de `rc.local`. Revísalos manualmente. El supplicant gestionado por NetworkManager vía D-Bus es distinto de un servicio runit `wpa_supplicant` independiente. No se convierten automáticamente credenciales/configuraciones de conexión.

Los demás servicios globales son `dbus`, el gestor de sesiones elegido, `bluetoothd`, `accounts-daemon` y `greetd` solo si se acepta Noctalia y existe su binario greeter. Se informan y conservan servicios ausentes, entradas personalizadas y archivos runit `down` existentes.

### Preservación, idempotencia y simulación

Se conservan archivos, enlaces personalizados (incluidos los rotos), wallpapers y entradas de servicio. Los archivos idénticos y enlaces esperados se reutilizan. Los nuevos archivos/directorios de usuario pertenecen al usuario de escritorio; no se hace `chown` recursivo de árboles existentes. Se omiten paquetes ya instalados. Los backups antiguos `.void-desktop-setup.bak` quedan intactos; ya no se reemplazan archivos ni se crean nuevos backups para reemplazarlos.

La configuración mínima nueva de Niri mantiene teclado `es` y atajos Kitty/Fuzzel. Solo añade el arranque Quickshell/Noctalia cuando se acepta Noctalia y existe `qs`. Wallpaper y archivos greetd se crean únicamente cuando no existen y corresponde configurarlos.

```bash
sudo ./void-desktop-setup.sh --dry-run
```

El modo de simulación sigue recogiendo opciones/consentimiento y leyendo el estado de paquetes/servicios, pero no ejecuta órdenes que modifiquen el sistema ni escribe archivos. Si un paquete todavía no está instalado, algunas comprobaciones de disponibilidad de servicios/ejemplos solo se pueden resolver con una instalación real.

### Tests y validación pendiente

```bash
bash -n void-desktop-setup.sh tests/mock-smoke-tests.sh
bash tests/mock-smoke-tests.sh
shellcheck void-desktop-setup.sh tests/mock-smoke-tests.sh  # si está instalado
```

El harness simula paquetes, grupos y servicios; las operaciones reales de archivos quedan en directorios temporales. Las ejecuciones de aplicación cargan el script real y sustituyen las comprobaciones de plataforma; los dry runs directos y por entrada estándar prueban la entrada normal, incluido el permiso de ejecución y la instalación canalizada. Se cubren Intel/AMD, generaciones NVIDIA, GPU desconocidas/mezcladas, cada escritorio, audio/Bluetooth/Vulkan, alternativas de sesión, red/conflictos/consentimiento/fallos, Noctalia, configuraciones/enlaces personalizados, segunda ejecución y snapshots de dry run. Las entradas tienen timeout para evitar bloqueos.

**No se afirma validación en VM ni hardware real.** Antes del merge, comprueba en Void:

- Paquetes XBPS para arquitectura/libc objetivo; DKMS NVIDIA con kernel/headers reales, DRM/KMS y login en RTX 4060 Ti. Los paquetes NVIDIA nonfree tienen restricciones de arquitectura/libc.
- Login Niri/Sway/Plasma, permisos del seat, D-Bus, runtime y diálogos/screencasting de portales.
- `wpctl status`, `pactl info` (`pactl` requiere `pulseaudio-utils`), aplicaciones ALSA, emparejamiento Bluetooth y reproducción/micrófono/cambio de perfiles de auriculares.
- Migración de red, credenciales Wi-Fi, reconexión y persistencia tras reiniciar, desde consola local.
- Paquetes Noctalia de terceros, usuario/permisos del greeter, configuración Quickshell y entradas de sesión. Se conserva la integración greeter original del proyecto; no se ha verificado con paquetes comunitarios reales.

El fallback Nouveau no elimina paquetes NVIDIA/blacklists anteriores ni garantiza Vulkan. Los drivers legacy pueden fallar con kernels recientes y no garantizan compatibilidad con todos los compositores Wayland. Conservar configuración personalizada puede requerir integración manual aunque el script termine.

### Fuentes y licencia

La sección [Documentation consulted](#documentation-consulted) enlaza todas las páginas oficiales del Handbook, los templates de paquetes de Void contrastados y la documentación de Niri utilizada. Consulta [LICENSE](LICENSE). Agradecimientos a Void Linux, Niri, Noctalia, Sway y KDE Plasma.

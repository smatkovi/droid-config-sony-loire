# Sailfish OS 5.1.0.11 Port: Sony Xperia X Compact (kugo)

Stand: 24.07.2026 — UI bootet, Touch funktioniert.

## Kernel (android_kernel_sony_msm, Branch kugo-sfos51)

- `CONFIG_USB_CONFIGFS_RNDIS=y` — generisches RNDIS statt QCRNDIS (hybris-initramfs braucht f_rndis)
- `# CONFIG_USB_CONFIGFS_QCRNDIS is not set` — kollidiert mit generischem RNDIS
- `# CONFIG_USB_CONFIGFS_RMNET_BAM is not set` — braucht QC IPA data path, ungenutzt
- `CONFIG_SECURITY_SELINUX_BOOTPARAM=y` — ermöglicht `selinux=0` in der Cmdline
- rndis.c: QC-`module_param()`-Zeilen entfernt (KBUILD_MODNAME undefined beim Vanilla-Build)
- BoardConfig.mk: `BOARD_KERNEL_CMDLINE += selinux=0`

**Wichtig:** cpio muss in der HABUILD-Chroot installiert sein, sonst entsteht ein
20-Byte-initramfs (leeres gzip) ohne Fehlermeldung → Bootloop.

## AOSP-Patches

- `bionic/libc/bionic/system_properties.cpp`: `return fsetxattr_failed ? -2 : 0` → `return 0`
  (ohne SELinux-Policy schlägt fsetxattr mit EOPNOTSUPP fehl, init bricht sonst ab)
- `system/hwservicemanager/AccessControl.cpp`: getcon/sehandle-Fehler tolerieren,
  can{Add,Get,List} kurzschließen wenn kein Kontext
- `frameworks/native/cmds/servicemanager/service_manager.c`:
  `check_mac_perms()` → `return true` (ohne SELinux schlägt getpidcon fehl,
  jede Service-Registrierung würde abgelehnt) + beide abort() im main entschärft

## Fehlende Build-Targets (nicht in `make hybris-hal` enthalten)

    make -j8 hwservicemanager vndservicemanager servicemanager logd logcat \
      android.hardware.graphics.composer@2.1-service \
      android.hardware.graphics.allocator@2.0-service \
      android.hardware.configstore@1.0-service \
      android.hardware.graphics.allocator@2.0-impl \
      android.hardware.graphics.mapper@2.0-impl \
      android.hardware.graphics.composer@2.1-impl \
      hwcomposer.msm8952 gralloc.msm8952 \
      libqdMetaData libdrmutils libdrm libhwc2on1adapter libsdmcore \
      libqservice libstdc++ libhwminijail libminijail_vendor libselinux_vendor \
      libtinyxml2 event-log-tags

Besser: einmal `make -j8` komplett laufen lassen (1–2 h), dann build_packages.sh.

## Rootfs-Fixes (gehören in droid-config sparse/)

- `/usr/bin/droid/droid-hal-early-init.sh` — fehlt im droid-hal-Paket, ohne sie
  scheitert der ExecStartPre und droid-hal-init wird endlos neu gestartet
- `/etc/login.defs` mit `UID_MIN 100000` — sonst findet start-autologin keine UID
- defaultuser (UID/GID 100000) in passwd/group/shadow + Gruppen
  wheel, video, audio, users, system, graphics, input, privileged
- `/nonplat_file_contexts` (leer) — libselinux erwartet sie neben plat_file_contexts
- `system.mount` — bind /usr/libexec/droid-hybris/system → /system
- `vendor.mount` — /dev/block/bootdevice/by-name/oem → /vendor
  **Achtung:** /vendor ist im Rootfs ein Symlink auf /system/vendor und muss
  durch ein echtes Verzeichnis ersetzt werden
- `/vendor/manifest.xml` mit graphics.allocator/composer/mapper + configstore
- `/system/lib64/egl/egl.cfg` + Symlinks auf /vendor/lib64/egl/*
- `/etc/udev/rules.d/99-input-perms.rules`: `KERNEL=="event*", MODE="0666"`
- `/dev/kgsl-3d0`, `/dev/ion`, `/dev/fb0` brauchen Zugriff für defaultuser
- lipstick-Drop-in: `QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event5`
  (Plugin erkennt den clearpad sonst nicht)
- `droid-hal-extras.service` startet vndservicemanager, allocator-, composer-
  und configstore-service (die rc-Definitionen greifen nicht)

## Startreihenfolge (kritisch)

1. droid-hal-init
2. vndservicemanager /dev/vndbinder  (SDM registriert qservice darüber)
3. allocator-service
4. composer-service  (öffnet den HWC2-HAL, HWCSession::Init)
5. configstore-service
6. lipstick mit `QT_QPA_FORCE_HWC2=1`

Ohne FORCE_HWC2 öffnet lipstick den HAL selbst und blockiert den Service.

## Offen

- WLAN: bcmdhd sucht /vendor/firmware/fw_bcmdhd.bin + bcmdhd.cal — beide fehlen,
  auch im SW_binaries-Zip. Quelle: Stock-ROM system-Image oder LineageOS-Blobs
- Icons/DPI zu groß
- USB-Netz bricht im späten Boot-Zustand ab (Debug-telnet nur früh erreichbar)
- Sensoren, Audio, Modem ungetestet

## Firmware: GELÖST (24.07.2026)

Die Firmware fehlt nicht — sie liegt auf eigenen Partitionen, die nur nicht
gemountet waren:

    mount -o ro /dev/block/bootdevice/by-name/modem /firmware   # adsp.mdt, modem.*, mba.*
    mount -o ro /dev/block/bootdevice/by-name/dsp /dsp          # DSP-Codec-Module
    echo /firmware/image > /sys/module/firmware_class/parameters/path
    echo 1 > /sys/kernel/boot_adsp/boot                          # ADSP starten!

Danach: subsys1 (adsp) = ONLINE, Soundkarte msm8976-tasha-snd-card erscheint,
module-droid-card lädt, sink.primary_output + sink.deep_buffer da, Ton geht.

Als `firmware-mount.service` in sparse/ festgehalten (Before=droid-hal-init).

## Alter Stand (überholt) — Firmware schien zu fehlen (Stand 24.07.2026, abends)

`/vendor/firmware/` (= Sony oem-Partition) enthält **keine** Subsystem-Firmware:
kein adsp.mdt/adsp.b0x, kein modem.*, kein mba.*, kein fw_bcmdhd.bin.

Folge: alle drei Subsysteme bleiben OFFLINING
(`/sys/bus/msm_subsys/devices/*/state`), daher:

- kein ADSP → keine Soundkarte (`/proc/asound/cards` = "no soundcards"),
  module-droid-card scheitert mit "Failed to open audio hw device"
- kein Modem → keine Telefonie
- kein WLAN (bcmdhd: `wl_android_wifi_on failed (-35)`,
  sucht /vendor/firmware/fw_bcmdhd.bin + bcmdhd.cal)

Quelle für die Blobs: Sony Stock-ROM (XperiFirm) oder LineageOS-Build für kugo,
Verzeichnis system/vendor/firmware bzw. system/etc/firmware.

Audio-Stack ist ansonsten vollständig vorbereitet:
- audio.primary.msm8952.so gebaut + Symlinks .kugo/.default in /vendor/lib64/hw
- audio_policy_configuration.xml + mixer_paths.xml aus device/sony/kugo/rootdir/vendor/etc
- die 5 xi:include-Dateien aus frameworks/av/services/audiopolicy/config
- libtinyalsa, libtinycompress, libaudioroute u.a. aus system/vendor/lib64

## Graphics bringup (2026-07-24)

Boot to UI with working touch. Four root causes, all fixed:

1. **libsdmextension.so stub must NOT be in the image.** A dummy stub
   (built manually from a local `external/dummylib`, never in
   PRODUCT_PACKAGES) ended up in out/ and thus in the image. SDM
   tolerates a *failed* dlopen of libsdmextension (runs without
   extensions), but a *successful* dlopen followed by a failed
   dlsym(CreateExtensionInterface) hard-aborts CoreImpl::Init ->
   composer-service dies with SIGABRT at every start.
   Removed external/dummylib and all traces from out/ (2026-07-24).
   If composer-service ever aborts right after "CoreImpl::Init: Unable
   to load symbols", check for a stub again.

2. **composer-service needs LD_LIBRARY_PATH** to dlopen Adreno libs
   (libadreno_utils/libgsl live in /vendor/lib64 only; no ld.config.txt
   in this setup). Set via Environment= in droid-hal-extras.service.

3. **/dev/ion and /dev/kgsl-3d0 need non-root access** (covered by
   sparse 99-kugo-perms.rules). Symptoms otherwise: gralloc SEGV in
   AdrenoMemInfo::AlignUnCompressedRGB (null instance after
   IonAlloc::Init EPERM) for ion; "Cannot find EGLConfig" +
   eglCreateWindowSurface 0x3001 for kgsl.

4. **clearpad needs ID_INPUT_TOUCHSCREEN=1** (sparse
   62-kugo-touchclass.rules), otherwise Qt evdevtouch autodiscovery
   finds no touchscreen in the startup wizard (runs plain
   "-plugin evdevtouch" without device argument).

Debug technique that cracked 1-3: run the failing binary under
strace -f -s 200 and extract Android log messages (logd not running)
via: grep -oE 'iov_base="[^"]{15,}"' trace | tail

## WLAN bringup (2026-07-24)

WLAN works (scan + connect). Chain and fixes:

- **Firmware lives on the Sony oem partition** (mmcblk0p39):
  /mnt/oem/firmware/fw_bcmdhd.bin + bcmdhd.cal. Added mnt-oem.mount
  (ro, nofail). Likely also relevant for other subsystem blobs.
- **Kernel has CONFIG_BCMDHD_FW_PATH=/vendor/firmware/fw_bcmdhd.bin**
  (and _NVRAM_PATH for the .cal); added symlinks there pointing into
  /mnt/oem/firmware. Do NOT rely on the sysfs module parameters
  (firmware_path/nvram_path): bcmdhd clears them on every chip
  power-down (wifi off/on), which silently breaks the next firmware
  download ("dongle image file download failed", devreset -35).
- **connman vendor unit ships --noplugin=wifi**; added drop-in
  50-enable-wifi.conf overriding ExecStart without it. Without the
  wifi plugin connman never registers wlan0 with wpa_supplicant and
  every scan returns "No carrier".
- Chip is BCM43455 (0x4345 rev 6) on SDIO, bcmdhd built-in (=y),
  nl80211 works fine once firmware is loaded. Placeholder MAC
  00:90:4c:11:22:33 means firmware not loaded; real MAC comes from
  the .cal.

## App sandboxing (2026-07-25)

Sandboxed apps (browser, camera, gallery, ...) failed to launch:
firejail aborts with "clone: Invalid argument" (EINVAL) because the
msm-4.4 kernel was built WITHOUT CONFIG_USER_NS (and likely other
namespace/seccomp options mer-kernel-check wants). sailjail has no
runtime disable switch (config Enabled=false in the default-profile
section does not bypass the firejail wrapper).

Workaround: systemd user drop-ins for booster-browser@ and
booster-silica-media@ that drop the "sailjail --profile=%i" wrapper
from ExecStart, launching the booster directly via invoker.
=> apps run UNCONFINED. Acceptable for now; proper fix is a kernel
rebuild with CONFIG_USER_NS/PID_NS/UTS_NS/IPC_NS/NET_NS/SECCOMP,
after which these drop-ins should be removed.

Also: /etc/login.defs needs GID_MIN (sparse shipped only UID_MIN),
otherwise firejail warns "cannot read UID_MIN and/or GID_MIN".

## Bluetooth (BCM4345C0, UART ttyHS0) - Stand 25.07.2026

FUNKTIONIERT: BT 4.2 (Patchram rev 0x12f, vorher ROM-only 4.1),
geraetespezifische MAC (WLAN-MAC+1), 3 Mbaud, ab Boot automatisch.

Stack: bluetooth-rfkill-event-hciattach (Daemon, lauscht auf rfkill)
-> brcm_patchram_plus (laedt /etc/firmware/BCM4345C0.hcd ueber
/dev/ttyHS0, setzt bd_addr aus /factory/bluetooth_address).
Config: /etc/bluetooth-rfkill-event/bcm4345c0.conf - lpm MUSS false
sein (mit LPM schlaeft der Chip ein, alle HCI-Kommandos timeouten).
MAC: bt-macaddr.service leitet sie beim Boot aus der WLAN-MAC ab.
Firmware: einmalig kugo-setup-bt-firmware.sh (kopiert BCM43xx.hcd
von Stock-p52, symlinkt als BCM4345C0.hcd nach /odm/firmware).

KERNEL (branch kugo-sfos51): BT_BCM_COMBO + PROTOCOL/LINE_DISCIPLINE
DRIVER (brcm-ldisc), BT_RFCOMM(+TTY) + BT_HIDP (sonst bluetoothd-
Profile-Fehler, mgmt-Power scheitert), und der hci_ldisc-Fix:
doppeltes hci_unregister_dev in hci_uart_tty_close -> list-poison-
Panic dead000000000108 beim Beenden des Attach-Prozesses (2x
reproduziert, pstore). Fix: einzelner unregister via
test_and_clear_bit.

BEDIENUNG / KNOWN ISSUES:
- UI-Toggle AUS: geht (mgmt-Reset + rfkill-block).
- UI-Toggle AN: nur mgmt, KEIN rfkill-unblock -> Daemon attacht
  nicht. Einschalten: rfkill unblock bluetooth (+ ggf. systemctl
  restart bluetooth-rfkill-event) oder Reboot.
- Boot-Attach zuverlaessig (6/6); Laufzeit-Re-Attach ~50%, haengt
  manchmal im Download - seit Kernel-Fix harmlos, Reboot hilft.
- mgmt-Power-Cycle wirft Chip auf 115200 zurueck -> auf 3M danach
  Funkstille bis Re-Attach.

ZUKUNFT: mgmt-Watcher fuer natives UI-Toggle; bluebinder-Weg
braeuchte UIM-Daemon (sysfs-install-Protokoll von brcm_sh_ldisc,
nicht auf Stock, muesste geschrieben werden - HAL-Blobs liegen
schon in /vendor + /system/lib64); brcm_patchram_plus als RPM
(Quelle github.com/AsteroidOS/brcm-patchram-plus, Build:
sb2 -t sony-kugo-aarch64 gcc -O2 -o brcm_patchram_plus src/main.c).

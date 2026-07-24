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

## Firmware fehlt komplett (Stand 24.07.2026, abends)

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

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

### BT-Toggle final (25.07. abends): funktioniert end-to-end
kugo-bt-watcher v5 repliziert bei UI-An die Boot-Reihenfolge
(bluetoothd stop -> frischer Attach -> rfkills unblocken ->
bluetoothd start), bluez AutoEnable=true powert den neu
adoptierten Adapter. Einschalten dauert 1-2 min. Root cause der
Laufzeit-Fehlschlaege: mgmt-Init von bluetoothd traf auf halb-
attachten Adapter (beim Boot verhindert Before=bluetooth.service
genau das). GPS: noch nicht funktionierend, eigenes Kapitel.

### App-Installations-Stack (Storeman-Fix, 25.07. abends)
Storeman hing ewig in "refresh cache" + Segfault. Drei Ursachen:
1. store-Repo verlangt Credentials -> PackageKit-Refresh fatal
   abgebrochen. Fix: ssu dr store.
2. polkit verlangte interaktive Auth fuer PackageKit-Aktionen,
   Storeman kann nicht antworten. Fix: pkla-Regel (sparse).
3. zypp-Cache lag unter /var/cache/zypp statt /home/.zypp-cache
   (Sailfish-Standard) -> Storeman fand keine solv-Dateien,
   Segfault. Fix: mv + Symlink /var/cache/zypp -> /home/.zypp-cache.
Ausserdem: libsailfishapp-launcher noetig fuer QML-harbour-Apps
(liefert /usr/bin/sailfish-qml), jetzt im Pattern.

### DSP-Boot-Kette + Audio-Wiederherstellung (25.07. spätabends)
ROOT CAUSE Audio-Mysterium: venus/adsp/modem wurden NIE gebootet
(alle OFFLINING ab Boot). Kernel-PIL braucht Userspace-Trigger
(echo 1 > /sys/kernel/boot_adsp/boot, wie Stock-init) + Firmware
von Partition p24 (modem, vfat, image/) via /odm/firmware.
Der alte firmware-mount.service (5f9e319) war committet aber nie
deployed (sparse wirkt erst nach RPM-Rebuild+Reinstall!) - daher
ging Audio nach jedem Reboot verloren. Ersetzt durch getestete
Kette: mnt-fw.mount (p24) + persist.mount (p36) + kugo-dsp-boot
.service (fw-Symlinks, rmt_storage, adsp-Trigger).
Soundcard (/dev/snd voll) entsteht in der Sekunde des ADSP-Boots.
PA braucht zusaetzlich: audio.primary-HALs + Policy-XMLs von oem
nach /vendor (Setup-Skript) + ro.board.platform=msm8952 + PA-
(Re)start NACH ADSP-online (Reihenfolge-Polish offen).
TODO: firmware_class/parameters/path=/firmware/image waere
eleganter als Symlinks (Idee aus altem Service); dsp-Partition
(by-name/dsp) existiert auch - pruefen was sie enthaelt.
Sensoren: ADSP online, aber SNS-Dienste registrieren sich nicht
am Router (kein 0x100er auf Node 5) - naechste Session.

### USB-Modi + Sensor-Forschungsstand (25.07. nachts)
USB: usb-moded.service war MASKED (Bringup-Altlast) -> unmask +
enable + Jolla-f5121-Configs (mode=ask, idVendor 05c6, jetzt
sparse). Dialog erscheint beim Einstecken.
Property-Raetsel geloest: droid-hal-init liest praktisch nur
/default.prop (Ramdisk) - build.prop-Ebenen greifen nicht.
ro.board.platform=msm8952 nach /default.prop (Verifikation nach
naechstem Reboot; noetig fuer hw_get_module aller HALs).
Sensoren-Stand: SNS nachweislich im adsp-Image (strings: b12=152
Treffer), boot_slpi ist auf kugo SACKGASSE (kein slpi-Subsystem
im DT, Fehler kommt sofort; Sony-rc schreibt beide Trigger nur
weil sie plattformweit gilt). Alle Userspace-Zutaten stehen
(Daemon, Libs, Registry, rmt_storage healthy mit 3 offenen
Block-fds als root). SNS registriert trotzdem keine Dienste am
Router (Node 5 nur Sysmon/SSCTL/2b/f). Daemon sendet nie (strace:
0 sendto) - wartet per Discovery auf SMGR der nie kommt.
OFFEN: Warum initialisiert SNS im adsp-Image nicht? Naechste
Session: Sony init.qcom.rc Z.60-90 Kontext, SMEM-Flags,
Vergleich mit anderen loire-SFOS-Ports (Jolla f5121 config macht
NICHTS besonderes -> bei denen kam es aus der vollen Android-
init-Umgebung).

### SENSOREN FUNKTIONIEREN - Rotation dreht! (25.07. 23:00)
41 Sensoren: BMI160 Accel+Gyro, AK09915 Mag, APDS-9940 Prox+
Licht, HSPPAD042A Druck + virtuelle. Die fehlenden Glieder nach
der Zutatenjagd (libpower, QMI-Libs, sensors_settings, irsc_util,
persist, board.platform in /default.prop):
1. tftp_server = QMI-RFSA-Dateiserver (Name taeuscht!) - Stock
   startet ihn als core-Service; jetzt in kugo-dsp-boot VOR dem
   ADSP-Trigger.
2. /data/misc/sensors fehlte -> sns_reg_storage_init des Daemons
   scheiterte still, kein Registry-Dienst, ADSP-SNS init nie.
   (strings sensors.qcom verriet den Pfad: /data/misc/sensors/
   sns.reg). Jetzt im Setup-Skript.
3. /dev/sensors war root:root 0600, Daemon laeuft als system ->
   udev-Regel (KERNEL=="sensors").
Nach Reboot mit vollstaendiger Kette: Node 5 voll mit SNS-
Diensten (0x100 SMGR etc.), test_sensors "Got 41 sensors",
sensorfwd startet (enabled), UI rotiert.
boot_slpi bleibt wirkungslos auf kugo (kein slpi-Subsystem),
schadet aber nicht - Sony-rc schreibt ihn auch.

## KAMERA-MARATHON 26./27.07. - ENDSTAND
BEIDE KAMERAS ZEIGEN LIVE-BILD (Front imx241 fluessig, Haupt imx300
stotternd ~3s). Kette: CFI-frei (frameworks/av+flac+libvpx, patches/),
32bit-minimedia (mediaserver-Stack in 8.1 32-only = XA2-Normalfall),
binderized camera.provider@2.4-service (32bit, selbst gebaut, make
baut _32 automatisch; hwbinder-Manifest, isRemote=1, camera-provider.rc
class core), SW_binaries /mnt/oem (ro.odm 8.1.0_4.4_loire_v13) via
odm/vendor-Links, camera.msm8952 aus Quellbaum, sat/sac/depth-Dummies,
persist.vendor.camera.HAL3.enabled=1, qcamerasvr GEPARKT (video0!),
cashsvr (vendor/oss/cash, 64bit ok) + tof_focus_calibration.xml aus
oem (Werkskalibrierung, Korrelation 0.998), dconf jolla-camera-hw
(f5121-Basis, Front real 2592x1944, VF 1280x960).
OFFEN: (1) HEAP-KORRUPTION fluechtig (malloc unaligned fastbin,
Abort bei vfsrc-STREAM_START, App-Prozess; gst-launch-Pfad crasht
NICHT) = WURZEL-VERDACHT - ZUERST loesen; (2) Haupt-Stottern
(getBuffer timeout 3000ms max_buffers 6; falsifiziert: maxAcquired
32->4 [Patch bleibt, korrekt], Texture-Cache-no-ref [zurueckgerollt
auf 0.1.4]); (3) Capture: HAL liefert Snapshot (ENCODER-Log), App
speichert nicht (filesink location cap_%d Default; Raw-Preview-
Callback TOT - NV21 verhandelt, 0 chain); (4) Sucher-Start 10-20s;
(5) Provider-Binary + cashsvr in droid-hal paketieren, cashsvr.rc
fehlt; (6) RGBC-XML existiert nirgends (loire wohl nur ToF).
LEHREN: vendor-Namespace ab 8.1; glibc-Aborts NICHT im logcat
(stderr!); rc 0644 root:root; timeout fehlt (coreutils in Pattern);
BusyBox: kein {}-Expand via scp, kein find -newermt; nach Crashes
2x minimedia-Zyklus; Home 777 blockiert sshd-Keys (chmod 755).
REFERENZEN: XA2/nile ohne Sonderconfig (Pakete/Config korrekt);
LineageOS loire = 32bit-only+binderized ab Werk (unser Modell);
10V-Thread 30978: gleiches Muster (Main-Sensor an Zusatz-HW).

## NACHTRAG 27.07. vormittag: BOOT-FESTIGKEIT BEWIESEN + Props-Falle
Frischer Boot ohne Handgriffe: camera-provider.rc startet Provider
automatisch, minimedia verbindet remote (isRemote=1, ready with 2),
BEIDE Kameras zeigen Bild. cashsvr noch manuell (rc fehlt - Todo).
KRITISCHE LEHRE - PERSIST-PROPS: Lineage-Test-Props (persist.camera.
eis.enable, dc.frame.sync, zsl.mode, HAL3.enabled=0 etc.) ueberlebten
als /data/property-Dateien; "Loeschen" per setprop X "" ist WIRKUNGSLOS
(leere Props bleiben gesetzt!). Nach Reboot lud der Property-Service
die Leichen -> BEIDE Kameras: Gruenstich + Freeze nach 1. Frame +
"Kamera antwortet nicht". FIX: rm /data/property/persist.camera.* +
REBOOT (rm wirkt erst nach Neustart - in-memory-Werte bleiben bis
dahin!). persist.vendor.camera.HAL3.enabled=1 bleibt der einzige
gewollte Camera-Prop. Eimer C+D-Nebenbefunde: vendor-libqdutils MUSS
stock bleiben (D revertiert, a0dc9e8-Revert im Repo); somc-provider@
1.0-Link wiederhergestellt (nicht im Manifest, unkritisch);
camera.qcom-Stock-Link korrekt auf /mnt/stock-system/vendor/lib/hw/.

## VIDEOAUFNAHME GELOEST 28.07.! 
Kette der Fixes: (1) Encoder-Stack materialisiert (libOmxCore/Venc/
stagefrighthw/c2dcolorconvert + soft-Encoder nach $D/lib, 32bit),
(2) schlanke media_codecs.xml + media_profiles nach /vendor/etc+/etc
(Stock-VOLLKATALOG haengt minimedia32!), (3) dconf video/VF beide
1280x720 (16:9-Match), (4) DER SCHLUESSEL: droidmedia-Patch - 
Recording-BufferQueue-Guards ANDROID_MAJOR >=9 -> >=8 
(droidmediacamera.cpp 514/542 + private.cpp attachToCameraVideo;
setVideoTarget existiert in 8.1!). Symptom davor: "startRecordingL:
No valid recording window", 0-Byte-MP4s. Branch kugo-video-8x in
external/droidmedia, Upstream-PR-Kandidat!
WICHTIG: Nach Lib-Tausch IMMER booster-silica-media restart + App-Kill.
Offen: malloc-Abort beim App-Schliessen (h264parse/encodebin PLAYING
-dispose - der bekannte Heap-Verdacht), Haupt-Kamera-Stottern.
NEUE THEMEN: Lade-Screen im Aus-Zustand + Power-off-Alarm = beides
ACT_DEAD-Modus (dsme/mce/charging-UI) - naechstes Kapitel.
### DRM/freedreno-Befund 28.07. (Experiment beendet)
CAF-4.4 hat drm/msm MIT a5xx_gpu.c + SDE-Stack, bindet an
"qcom,kgsl-3d0". ABER: nicht modulfaehig (multiple init_module in
sde_wb/dsi_display -> nur =y moeglich), =y aktiviert SDE-Display
neben mdss -> lipstick-Risiko. Container-mesa (libgallium_dri,
vulkan.freedreno) waere bereit. Einordnung: eigenes Projekt
(Makefile-Trennung sde/gpu noetig), NICHT quick-win.
Naechster Waydroid-Zug: SwiftShader-Libs (arm64, 13er-ABI, aus
GSI/Emulator) in overlay/system/lib64/egl + egl=swiftshader -
gleiche bewiesene Overlay-Technik, keine Kernel-Aenderung.

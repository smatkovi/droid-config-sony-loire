#!/bin/sh
# One-time: copy BT patchram from stock /system (p52) and wire
# it up for hciattach/brcm_patchram_plus (BCM4345C0 on loire).
set -e
[ -f /system/etc/firmware/BCM43xx.hcd ] || {
    mkdir -p /mnt/stock-system /system/etc/firmware
    mount -o ro /dev/mmcblk0p52 /mnt/stock-system
    cp /mnt/stock-system/etc/firmware/BCM43xx.hcd /system/etc/firmware/
    umount /mnt/stock-system
}
mkdir -p /odm/firmware
ln -sf /system/etc/firmware/BCM43xx.hcd /odm/firmware/BCM4345C0.hcd
echo "BT firmware ready."

# enable bluez AutoEnable so freshly adopted adapters get powered
sed -i 's/^#AutoEnable=true/AutoEnable=true/' /etc/bluetooth/main.conf

# --- app install stack fixes (not BT, but one-time setup too) ---
# zypp cache must live at the Sailfish path /home/.zypp-cache;
# without this Storeman finds no solv files and segfaults
if [ ! -L /var/cache/zypp ]; then
    systemctl stop packagekit 2>/dev/null
    rm -rf /home/.zypp-cache
    mv /var/cache/zypp /home/.zypp-cache
    ln -s /home/.zypp-cache /var/cache/zypp
    systemctl start packagekit 2>/dev/null
fi
# store repo requires credentials community ports lack; its auth
# failure aborts every PackageKit refresh -> Storeman hangs
ssu dr store 2>/dev/null

# --- audio stack (needs ADSP online via kugo-dsp-boot.service) ---
# HAL + policy configs live on oem (p39)
mkdir -p /vendor/lib64/hw /vendor/etc
cp -n /mnt/oem/lib64/hw/audio.primary.msm8952.so /vendor/lib64/hw/ 2>/dev/null
cp -n /mnt/oem/lib64/hw/audio.primary.kugo.so /vendor/lib64/hw/ 2>/dev/null
for f in /mnt/oem/etc/*audio*.xml /mnt/oem/etc/mixer_paths.xml; do
    ln -sf "$f" /vendor/etc/
done
# hw_get_module needs the platform id (was empty -> no HAL ever found)
grep -q "ro.board.platform" /usr/libexec/droid-hybris/system/build.prop 2>/dev/null || \
    echo "ro.board.platform=msm8952" >> /usr/libexec/droid-hybris/system/build.prop

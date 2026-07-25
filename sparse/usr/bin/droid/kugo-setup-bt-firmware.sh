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

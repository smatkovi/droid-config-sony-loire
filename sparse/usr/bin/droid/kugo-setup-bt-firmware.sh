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

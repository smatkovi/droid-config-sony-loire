#!/bin/sh
# kugo: stock GNSS HIDL service + xtra-daemon (assisted GNSS).
# Location libs materialised from /mnt/stock-system into /vendor/lib64;
# gps.conf hand-written (Sony symlink points into absent /data/customization).
# Bionic cannot resolve DNS on SFOS (no netd dnsproxyd, net.dns props ignored),
# so pin izatcloud hosts in /system/etc/hosts for the XTRA download.
mkdir -p /data/vendor/location/xtra
chown -R gps:gps /data/vendor/location 2>/dev/null
grep -q izatcloud /system/etc/hosts 2>/dev/null || cat >> /system/etc/hosts << 'HOSTS'
99.84.91.61 time.izatcloud.net
99.84.91.61 xtrapath1.izatcloud.net
99.84.91.71 xtrapath2.izatcloud.net
3.165.206.101 xtrapath3.izatcloud.net
HOSTS
LD_LIBRARY_PATH=/vendor/lib64 /mnt/stock-system/vendor/bin/xtra-daemon &
exec /mnt/stock-system/vendor/bin/hw/vendor.qti.gnss@1.0-service

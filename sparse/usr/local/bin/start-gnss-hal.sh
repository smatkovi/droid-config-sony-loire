#!/bin/sh
# kugo: start the stock GNSS HIDL service (vendor.qti.gnss@1.0-service).
# Location libs were materialised from /mnt/stock-system into /vendor/lib64
# (loc/izat/lbs/lowi/gps.utils families); configs in /vendor/etc and
# /system/vendor/etc (gps.conf hand-written, Sony's symlink points into the
# absent /data/customization). Must be up before geoclue-hybris first connects,
# otherwise kill geoclue-hybris once so DBus reactivates it against the HAL.
mkdir -p /data/vendor/location
chown -R gps:gps /data/vendor/location 2>/dev/null
exec /mnt/stock-system/vendor/bin/hw/vendor.qti.gnss@1.0-service

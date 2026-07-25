#!/bin/sh
# Derive a per-device BT MAC from the WLAN MAC (last byte +1).
[ -s /factory/bluetooth_address ] && exit 0
for i in $(seq 1 30); do
    [ -s /sys/class/net/wlan0/address ] && break; sleep 1
done
W=$(cat /sys/class/net/wlan0/address) || exit 1
L=${W##*:}; P=${W%:*}
N=$(printf "%02x" $(( (0x$L + 1) % 256 )))
mkdir -p /factory
echo "$P:$N" > /factory/bluetooth_address

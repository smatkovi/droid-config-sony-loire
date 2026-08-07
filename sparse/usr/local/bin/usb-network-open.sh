#!/bin/sh
# kugo: allow inbound connections (ssh/scp) on the USB developer-mode network.
# connman's default INPUT policy is DROP and usb-moded's connman tethering
# integration does not complete on this port ("no network gateway"), so the
# usb0 accept rule never gets installed by the stack itself.
iptables -C INPUT -i usb0 -j ACCEPT 2>/dev/null || iptables -I INPUT -i usb0 -j ACCEPT

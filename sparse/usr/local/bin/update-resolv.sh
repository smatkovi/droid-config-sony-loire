#!/bin/sh
SVC=$(connmanctl services | awk '/^\*/ {print $NF; exit}')
[ -z "$SVC" ] && exit 0
NS=$(connmanctl services "$SVC" | sed -n 's/.*Nameservers = \[ \(.*\) \].*/\1/p' | tr -d ',;')
[ -z "$NS" ] && exit 0
NEW=$(for n in $NS; do echo "nameserver $n"; done)
[ "$NEW" = "$(cat /etc/resolv.conf 2>/dev/null)" ] && exit 0
echo "$NEW" > /etc/resolv.conf

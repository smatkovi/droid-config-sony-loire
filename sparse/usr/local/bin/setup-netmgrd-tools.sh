#!/bin/sh
# kugo mobile data: Sony ODM netmgrd exec()s /system/bin/ip-wrapper-1.0,
# iptables-wrapper-1.0 etc. (versioned wrapper names, no PATH search) and
# needs a shell at /system/bin/sh. Children run as user radio, so the tools
# carry file capabilities for netlink configuration.
for t in ip tc iptables ip6tables; do
  src=$(command -v $t) || continue
  [ -x /system/bin/$t ] || cp "$src" /system/bin/$t
  ln -sf /system/bin/$t /system/bin/$t-wrapper-1.0
  setcap cap_net_admin,cap_net_raw+ep /system/bin/$t 2>/dev/null
done
ln -sf /bin/sh /system/bin/sh

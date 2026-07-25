#!/bin/sh
# kugo BT watcher v5: replicate the (always-working) boot order
# at runtime. If UI wants BT on but chip is unhealthy:
# stop bluetoothd -> unblock rfkills -> fresh daemon attach ->
# wait healthy -> start bluetoothd (inits a finished adapter,
# exactly like at boot; bluez AutoEnable then powers it).
LAST=0
healthy() { hciconfig hci0 version >/dev/null 2>&1; }
wants_on() { rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: no"; }

while true; do
    if wants_on && ! healthy; then
        sleep 12
        NOW=$(date +%s)
        if [ $((NOW - LAST)) -gt 60 ] && wants_on && ! healthy; then
            LAST=$NOW
            systemctl stop bluetooth
            rfkill unblock bluetooth
            systemctl restart bluetooth-rfkill-event
            for i in $(seq 1 20); do healthy && break; sleep 2; done
            if ! healthy; then
                systemctl restart bluetooth-rfkill-event
                for i in $(seq 1 20); do healthy && break; sleep 2; done
            fi
            rfkill unblock bluetooth
            systemctl start bluetooth
        fi
    fi
    sleep 3
done

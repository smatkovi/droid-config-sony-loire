#!/bin/sh
# kugo BT watcher v5: replicate the (always-working) boot order
# at runtime. If UI wants BT on but chip is unhealthy:
# stop bluetoothd -> unblock rfkills -> fresh daemon attach ->
# wait healthy -> start bluetoothd (inits a finished adapter,
# exactly like at boot; bluez AutoEnable then powers it).
# v6: after 3 re-attaches without an adapter, stop until Bluetooth is switched off and on
# again, so a chip that won't attach is not power-cycled every minute forever. Needs
# hciconfig (bluez5-tools): without it healthy() always failed and the watcher tore down a
# working adapter every minute.
LAST=0
FAILS=0
healthy() { hciconfig hci0 version >/dev/null 2>&1; }
wants_on() { rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: no"; }

# The boot-time attach takes up to about a minute; don't interrupt it.
for i in $(seq 1 45); do healthy && break; sleep 2; done

while true; do
    wants_on || FAILS=0
    if wants_on && ! healthy && [ $FAILS -lt 3 ]; then
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
            if healthy; then FAILS=0; else FAILS=$((FAILS + 1)); fi
            [ $FAILS -ge 3 ] && echo "kugo-bt-watcher: no adapter after 3 attaches; waiting until Bluetooth is switched off and on"
        fi
    fi
    sleep 3
done

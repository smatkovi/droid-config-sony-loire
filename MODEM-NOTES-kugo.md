# Modem bring-up on Sony Xperia X Compact (kugo, MSM8956/loire)

Base: `hybris-sony-aosp-8.1.0_r52`, Sailfish OS 5.1.0.11,
stock firmware `34.4.A.2.118`, modem `MPSS.TA.2.0.C7.3-00017`.

Symptom before these changes: ofono reports an empty modem list and
`Power request failed: SYSTEM_ERR`, while the modem subsystem itself is
online and rild/qmuxd are running.

Seven separate pieces were missing or wrong. They are listed below in the
order they have to be fixed - each one only becomes visible once the
previous one is out of the way.

## 1. Missing `/dev/socket/qmux_*` directories

qmuxd creates its sockets *inside* these directories but does not create
the directories. On stock Android that happens in
`device/sony/common/rootdir/vendor/etc/init/hw/init.common.rc` (lines
270ff), which a hybris port does not use.

```
qmi_client: unable to bind to client socket, rc = -1 errno[2:No such file or directory]
```

Fixed by `sparse/etc/tmpfiles.d/qmux-sockets.conf` and/or
`0001-radio-kugo-rc-socket-dirs.patch`. Note the per-directory ownership.

## 2. Missing `/vendor/etc/data/*.xml`

`qmi_config.xml`, `netmgr_config.xml` and `dsi_config.xml` are not part of
the hybris vendor tree. Without them:

```
qmuxd: Cannot open/parse configdb file /system/vendor/etc/data/qmi_config.xml Err[-4]
qmuxd: Failed to load XML configuration for target [Eldarion], all ports disabled
```

Copy them from the stock vendor image and add them to `proprietary-files`:

```
vendor/etc/data/qmi_config.xml
vendor/etc/data/netmgr_config.xml
vendor/etc/data/dsi_config.xml
```

## 3. Missing radio properties

Present in the stock `build.prop`, absent in the port:

```
ro.use_data_netmgrd=true
persist.radio.lw_enabled=true
persist.radio.apm_sim_not_pwdn=1
persist.radio.block_allow_data=1
```

## 4. qcril database path

`libril-qc-qmi-1.so` attaches `/odm/radio/qcril_database/qcril.db`, but on
this port the oem image is mounted read-only at `/mnt/oem`. A symlink is
*not* enough - sqlite opens the database with
`PRAGMA main.locking_mode = EXCLUSIVE` and needs write access:

```
qcril_db_open: Failed to open qcril db 14      (SQLITE_CANTOPEN)
```

Copy the file to a writable location instead:

```sh
mkdir -p /odm/radio/qcril_database
cp /mnt/oem/radio/qcril_database/qcril.db /odm/radio/qcril_database/
chown -R radio:radio /odm/radio
```

## 5. `/data/misc/radio` ownership

Ships as `system:radio`, rild runs as `radio` and cannot create its
working copy of the database. `chown radio:radio /data/misc/radio`.
Also create `/vendor/qcril_database/upgrade` to silence a warning.

## 6. `/odm/lib64` missing

The linker searches `/odm/lib64`; only `/odm/lib` existed. Symlink it to
`/mnt/oem/lib64`.

## 7. `use_qmuxd` and the master port  (the actual blocker)

The modem on this device never allocates a `DATA*_CNTL` SMD packet
channel. `/sys/kernel/debug/smd/ch` only ever shows

```
APPS <-> MDMSW:  DS, IPCRTR, SSM_RTR_MODEM_APPS
```

so qmuxd cannot open `/dev/smdcntl0` (`-ENODEV`, or `-ETIMEDOUT` after
raising `open_timeout`). The device tree is correct
(`msm8956.dtsi`: `qcom,smdpkt-data5-cntl` -> `smdcntl0`, remote `"modem"`),
the driver registers the node, the modem simply does not offer the
channel. It instead announces shim-layer support, and qmuxd agrees:

```
qmuxd: Shim layer supported by modem, closing client fd[19]
```

QMI therefore has to go over the IPC router, where the modem exports 28
services on node 0 (Voice = 0x09 on instance 2, NAS/WDS/DMS on instance 1).

Two changes are needed:

**a)** `use_qmuxd = 0` in the Eldarion section of `qmi_config.xml`
(`patch-qmi-config.py`). This makes the QMI client library take the shim
path:

```
qmi_client [...] Shim layer present. Do not use QMUXD
```

**b)** Patch the master port in `libril-qc-qmi-1.so`
(`patch-libril-master-port.py`).

`qmi_ril_client_get_master_port()` returns `QMI_CLIENT_INSTANCE_ANY`
(0xffff) only if one of the features 0x18/0x1c/0x1d/0x1e/0x1f is
supported - and all five are hardcoded to 0 in this build. It therefore
always falls back to `qmi_ril_client_get_port_for_legacy_targets()`,
which picks a port from the baseband type derived from `ro.baseband`:

| ro.baseband | type | feature | port |
| --- | --- | --- | --- |
| csfb | 3 | 0x00 | 0xbf |
| svlte2a | 5 | 0x06 | 0xbf |
| apq/sda/mdm/auto | 2 | 0x04 | 0x9d / 0xb9 |
| mdm2 | 10 | 0x04, 0x2a | 0x9d / 0xb9 |
| dsda | 8 | 0x01 | 0x9d / 0xb0 |
| dsda2 | 9 | 0x25 | 0x9d |
| sglte, sglte2 | 6 | 0x07 | 0xbf / 0x9d / 0x80 |
| **msm, sdm** | **4** | **0x05** | **never queried** |

Feature 0x05 (= integrated msm baseband) is not queried anywhere in that
function, so `ro.baseband=msm` falls through to the default branch

```
0x2ed8a8:  mov w8, #0x80        ->  port 128
```

Port 128 is a QMUX port. With qmuxd out of the picture nothing answers it,
so every `qmi_client_init_instance()` returns `-3` (QMI_TIMEOUT_ERR) and
qcril loops on

```
qcril_qmi_init_core_client_handles: Client init failed, details: QMI Voice
qmi_ril_peripheral_mng_vote: modem connect failed -1
```

The patch replaces that one constant with `QMI_CLIENT_INSTANCE_ANY`:

```
0x2ed8a8:  mov w8, #0x80  ->  mov w8, #0xffff
bytes   :  e8 03 19 32    ->  e8 ff 9f 52
```

After that the QMI library resolves each service through the IPC router
and picks up whatever instance the modem offers. rild initialises its
clients, NAS starts reporting signal strength, and ofono exposes

```
/ril_0  Powered=true  Online=true
        org.ofono.VoiceCallManager, org.ofono.SimManager,
        org.nemomobile.ofono.CellInfo, org.nemomobile.ofono.SimInfo
```

## Debugging hints

`persist.radio.adb_log_on=1` unlocks the detailed qcril messages
(`Trying qmi_client_init_instance() try # N port[X]`,
`qmi_client_init_instance returned failure(N) for VOICE`) which are
otherwise invisible. Read them with

```sh
/usr/libexec/droid-hybris/system/bin/logcat -b radio -d
```

Useful kernel views:

```sh
cat /sys/kernel/debug/smd/ch                            # SMD channels per edge
cat /sys/kernel/debug/msm_ipc_router/dump_servers       # QMI services per node
cat /sys/kernel/debug/msm_ipc_router/dump_xprt_info     # transports
```

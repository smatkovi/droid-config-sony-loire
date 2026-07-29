#!/usr/bin/env python3
"""
Patch libril-qc-qmi-1.so so that rild asks for QMI_CLIENT_INSTANCE_ANY
instead of the legacy QMUX port 0x80 on integrated-msm basebands.

Background
----------
qcril calls qmi_client_init_instance(service_obj, port, ...) to open its
QMI clients (Voice, DMS, NAS, ...).  The 'port' argument comes from

    qmi_ril_client_get_master_port()      @ 0x2ed8d0

which reads:

    port = QMI_CLIENT_INSTANCE_ANY (0xffff);
    if (!feature(0x1e) && !feature(0x18) && !feature(0x1c)
        && !feature(0x1d) && !feature(0x1f))
            port = qmi_ril_client_get_port_for_legacy_targets();
    return port;

All five of those feature checks are hardcoded to 0 in this build
(case labels 0x186524/0x186548/0x186550/0x186558/0x186560 all do
`stur wzr, [x29, #-0xd8]`), so the legacy path is always taken.

qmi_ril_client_get_port_for_legacy_targets() @ 0x2ed7a4 selects the port
from the baseband type, which qmi_ril_is_feature_supported() derives from
the `ro.baseband` property:

    ro.baseband        type   feature id   -> port
    csfb                 3        0x00        0xbf
    svlte2a              5        0x06        0xbf
    apq/sda/mdm/auto     2        0x04        0x9d / 0xb9
    mdm2                10     0x04/0x2a      0x9d / 0xb9
    dsda                 8        0x01        0x9d / 0xb0
    dsda2                9        0x25        0x9d
    sglte/sglte2         6        0x07        0xbf / 0x9d / 0x80
    msm/sdm              4        0x05        (never queried!)

Feature 0x05 (= baseband type 4 = msm/sdm, i.e. an integrated modem)
is not queried anywhere in the legacy function, so msm falls through to
the default branch at 0x2ed8a8:  `mov w8, #0x80`  ->  port 128.

On kugo (MSM8956, ro.baseband=msm) the modem does not expose any
DATA*_CNTL SMD packet channel - it only offers DS, IPCRTR and
SSM_RTR_MODEM_APPS, and it tells qmuxd "Shim layer supported by modem".
QMI therefore has to go over the IPC router, where the services are
registered on node 0 with per-service instance ids (Voice on instance 2,
NAS/WDS/DMS on instance 1).  Asking for the fixed QMUX port 128 finds
nobody, so every qmi_client_init_instance() call returns -3
(QMI_TIMEOUT_ERR) and qcril loops forever on

    qcril_qmi_init_core_client_handles: Client init failed, details: QMI Voice

The patch
---------
Replace the default branch constant with QMI_CLIENT_INSTANCE_ANY:

    0x2ed8a8:  mov w8, #0x80     ->  mov w8, #0xffff
    bytes    :  e8 03 19 32      ->  e8 ff 9f 52

With INSTANCE_ANY the QMI library resolves each service through the IPC
router and picks up whatever instance the modem actually offers.

Only the msm/sdm default branch is touched; all other baseband types keep
their original ports.

Requires additionally (see README):
  * use_qmuxd = 0 in the Eldarion section of /vendor/etc/data/qmi_config.xml
"""

import hashlib
import os
import shutil
import sys

FILE_OFFSET = 0x2398A8          # vaddr 0x2ed8a8 - load bias 0xb4000
ORIG_BYTES = bytes.fromhex("e8031932")   # mov w8, #0x80
NEW_BYTES = bytes.fromhex("e8ff9f52")    # mov w8, #0xffff

MD5_BEFORE = "01e7e9a02cac0b25a1c6d2ed4230f03d"
MD5_AFTER = "31ca0900f8f9401f5361fac44126b2bc"


def main(path):
    if not os.path.isfile(path):
        sys.exit("not found: %s" % path)

    data = bytearray(open(path, "rb").read())
    digest = hashlib.md5(bytes(data)).hexdigest()

    if digest == MD5_AFTER:
        print("already patched: %s" % path)
        return 0

    if digest != MD5_BEFORE:
        print("warning: unexpected md5 %s" % digest)
        print("         expected %s (Sony 34.4.A.2.118 / loire)" % MD5_BEFORE)

    found = bytes(data[FILE_OFFSET:FILE_OFFSET + 4])
    if found != ORIG_BYTES:
        sys.exit("bytes at 0x%x are %s, expected %s - aborting"
                 % (FILE_OFFSET, found.hex(), ORIG_BYTES.hex()))

    shutil.copy2(path, path + ".orig")
    data[FILE_OFFSET:FILE_OFFSET + 4] = NEW_BYTES
    open(path, "wb").write(bytes(data))

    print("patched %s" % path)
    print("  0x%x: %s -> %s (mov w8,#0x80 -> mov w8,#0xffff)"
          % (FILE_OFFSET, ORIG_BYTES.hex(), NEW_BYTES.hex()))
    print("  backup: %s.orig" % path)
    print("  md5: %s" % hashlib.md5(bytes(data)).hexdigest())
    return 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 \
        else "/vendor/lib64/libril-qc-qmi-1.so"
    sys.exit(main(target))

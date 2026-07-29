#!/usr/bin/env python3
"""
Set use_qmuxd = 0 in the Eldarion (MSM8976) section of qmi_config.xml.

The stock configuration ships use_qmuxd=1 for Eldarion, but the modem
firmware on kugo announces shim-layer support, and qmuxd itself logs

    qmuxd: Shim layer supported by modem, closing client fd[...]

while never being able to open /dev/smdcntl0 (the modem does not allocate
a DATA5_CNTL SMD packet channel at all).  With use_qmuxd=0 the QMI client
library takes the shim path over the IPC router instead:

    qmi_client [...] Shim layer present. Do not use QMUXD

Only the Eldarion block is touched, other targets keep their settings.

Note: qmi_config.xml itself is not part of this repo - it has to be
extracted from the stock vendor image
(/system/vendor/etc/data/ on stock, mounted as /mnt/stock-system here)
into /vendor/etc/data/ together with netmgr_config.xml and dsi_config.xml.
"""

import os
import shutil
import sys

SECTION = 'listitem name = "Eldarion"'


def main(path):
    if not os.path.isfile(path):
        sys.exit("not found: %s" % path)

    lines = open(path).read().split("\n")
    inside = False
    changed = 0

    for i, line in enumerate(lines):
        if SECTION in line:
            inside = True
        elif inside and "</listitem>" in line:
            inside = False
        elif inside and "use_qmuxd" in line and "> 1 <" in line:
            lines[i] = line.replace("> 1 <", "> 0 <")
            changed += 1

    if not changed:
        print("nothing to do (already 0 or section missing): %s" % path)
        return 0

    shutil.copy2(path, path + ".orig")
    open(path, "w").write("\n".join(lines))
    print("patched %s (%d line(s)), backup: %s.orig" % (path, changed, path))
    return 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 \
        else "/vendor/etc/data/qmi_config.xml"
    sys.exit(main(target))

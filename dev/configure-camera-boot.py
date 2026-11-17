#!/usr/bin/env python3
"""Enable the CutiePi OV5647 and AppArmor on the staged boot partition."""
from pathlib import Path
import sys

boot = Path(sys.argv[1]) / 'boot/firmware'
assert (boot / 'overlays/ov5647.dtbo').is_file()
config = boot / 'config.txt'
text = config.read_text()
if 'dtoverlay=ov5647' not in text.splitlines():
    config.write_text(text.rstrip() + '\n\n[cm4]\ndtoverlay=ov5647\n[all]\n')
cmdline = boot / 'cmdline.txt'
args = cmdline.read_text().split()
# The stock Raspberry Pi kernel enables AppArmor but has CONFIG_LSM="".
# Click apps cannot launch through aa-exec until the LSM is activated.
lsm = next((arg for arg in args if arg.startswith('lsm=')), None)
if lsm:
    names = lsm[4:].split(',')
    if 'apparmor' not in names:
        args[args.index(lsm)] = lsm + ',apparmor'
else:
    args.append('lsm=landlock,lockdown,yama,integrity,apparmor,bpf')
cmdline.write_text(' '.join(args) + '\n')

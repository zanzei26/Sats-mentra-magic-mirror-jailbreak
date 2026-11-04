#!/usr/bin/env python3
"""Create a 2048-byte Android bootloader_message (BCB) that makes the stock recovery wipe /data on the next boot.

  make_bcb.py out.bin
Then on the device:  dd if=out.bin of=/dev/block/by-name/misc bs=512 count=4 ; sync ; reboot recovery
(The stock recovery clears the BCB itself once it has run.)
"""
import sys
cmd = b'boot-recovery'.ljust(32, b'\0')
status = b''.ljust(32, b'\0')
recovery = b'recovery\n--wipe_data\n--locale=en_US\n'.ljust(768, b'\0')
rest = b'\0' * (2048 - 32 - 32 - 768)
open(sys.argv[1], 'wb').write(cmd + status + recovery + rest)

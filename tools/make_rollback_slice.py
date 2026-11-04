#!/usr/bin/env python3
"""Cut the rollback slice (super sectors 0..1837000 = LP metadata + original system extent) out of the verified full backup."""
import hashlib
BACKUP = '/path/to/eMMC_full_backup.img'
OUT = '/path/to/work/super_rollback_sectors_0-1837000.bin'
SUPER_LBA = 0x150c00
N_SECT = 1837000
CH = 4 * 1024 * 1024
h_all = hashlib.sha256()
h_sys = hashlib.sha256()
with open(BACKUP, 'rb') as f, open(OUT, 'wb') as o:
    f.seek(SUPER_LBA * 512)
    left = N_SECT * 512
    pos = 0
    while left:
        b = f.read(min(CH, left)); assert b
        o.write(b); h_all.update(b)
        # hash of the system extent only (sector 2048 onward) for comparison with the live device
        if pos + len(b) > 2048 * 512:
            s = max(0, 2048 * 512 - pos)
            h_sys.update(b[s:])
        pos += len(b); left -= len(b)
print('rollback slice bytes:', N_SECT * 512)
print('sha256 whole slice      :', h_all.hexdigest())
print('sha256 system extent A  :', h_sys.hexdigest(), '(sectors 2048..1837000, from the backup)')
open(OUT + '.sha256', 'w').write(f'{h_all.hexdigest()}  super_rollback_sectors_0-1837000.bin\n')

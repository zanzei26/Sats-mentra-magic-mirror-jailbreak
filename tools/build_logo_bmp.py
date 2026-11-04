#!/usr/bin/env python3
"""Build a same-size replacement for the Rockchip boot logos (logo.bmp + logo_kernel.bmp) inside the boot partition.

The boot partition of this device carries a Rockchip resource image (RSCE) as the 'second' part of boot.img. Its
logo.bmp / logo_kernel.bmp are 240x240, 8 bpp, uncompressed, 42-colour-palette BMPs of 57 822 bytes, stored in two
adjacent 113-sector regions. We keep the original BMP header, swap palette + pixels, and keep the original padding bytes,
so no offset or size anywhere changes. Check these numbers on YOUR unit with rsce_inspect.py first.

Usage:
  build_logo_bmp.py <boot_partition_backup.bin> <design_gray.raw> <outdir> [--rotate-cw]

design_gray.raw : 240*240 bytes, top-down luminance (see ../logo/make_logo.ps1).
--rotate-cw     : pre-rotate the bitmap 90 degrees clockwise (needed on this portrait panel).
Writes region_new.bin (226 sectors), region_patch.txt (start count old new fullnew fullold) and a preview PNG.
"""
import hashlib, struct, sys, zlib

boot_path, raw_path, outdir = sys.argv[1:4]
rotate = '--rotate-cw' in sys.argv
LOGO, SZ, REG = 27138048, 57822, 113 * 512      # byte offset of logo.bmp in the boot partition, file size, region size
KERN = LOGO + REG
N = 240

b = open(boot_path, 'rb').read()
orig = b[LOGO:LOGO + SZ]
assert orig[:2] == b'BM' and orig == b[KERN:KERN + SZ], 'unexpected logo layout: run rsce_inspect.py and adjust offsets'
hdr = bytearray(orig[:54])
w, h = struct.unpack('<ii', hdr[18:26])
assert (w, abs(h)) == (N, N) and struct.unpack('<H', hdr[28:30])[0] == 8
pix = struct.unpack('<I', hdr[10:14])[0]
ncol = (pix - 54) // 4
alpha = orig[57]

raw = open(raw_path, 'rb').read()
assert len(raw) == N * N
if rotate:                                        # (x, y) -> (N-1-y, x)
    rot = bytearray(N * N)
    for y in range(N):
        for x in range(N):
            rot[x * N + (N - 1 - y)] = raw[y * N + x]
    raw = bytes(rot)

pal = b''.join(bytes((v, v, v, alpha)) for v in (round(i * 255 / (ncol - 1)) for i in range(ncol)))
idx = bytes(round(p * (ncol - 1) / 255) for p in raw)
rows = [idx[y * N:(y + 1) * N] for y in range(N)]
if h > 0:
    rows = rows[::-1]                             # bottom-up like the original
bmp = bytes(hdr) + pal + b''.join(rows)
assert len(bmp) == SZ

old = b[LOGO:LOGO + 2 * REG]
new = (bmp + b[LOGO + SZ:LOGO + REG]) + (bmp + b[KERN + SZ:KERN + REG])
full_new = bytearray(b); full_new[LOGO:LOGO + 2 * REG] = new
open(f'{outdir}/region_new.bin', 'wb').write(new)
open(f'{outdir}/region_patch.txt', 'w').write(
    f'{LOGO // 512} {2 * REG // 512} {hashlib.sha256(old).hexdigest()} {hashlib.sha256(new).hexdigest()} '
    f'{hashlib.sha256(bytes(full_new)).hexdigest()} {hashlib.sha256(b).hexdigest()}\n')

def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
pr = b''
for y in range(N):
    yy = N - 1 - y if h > 0 else y
    r = bmp[pix + yy * N: pix + yy * N + N]
    pr += b'\x00' + b''.join(bmp[54 + 4 * i: 54 + 4 * i + 3][::-1] for i in r)
open(f'{outdir}/preview.png', 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 2, 0, 0, 0))
                                           + chunk(b'IDAT', zlib.compress(pr)) + chunk(b'IEND', b''))
print('wrote region_new.bin, region_patch.txt, preview.png in', outdir)

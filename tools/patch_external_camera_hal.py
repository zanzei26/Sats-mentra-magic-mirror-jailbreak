#!/usr/bin/env python3
"""Patch the Android 10 external-camera HAL (camera.device@3.4-external-impl.so, 32-bit ARM) so JPEG stills of 2592x1944 no longer crash it.

The bug (an AOSP bug that the Rockchip build still has): ExternalCameraDeviceSession::OutputThread::encodeJpegYU12() feeds libjpeg's raw-data
interface with row pointers for whole 16-row MCU rows. For the chroma planes it clamps the row index with the LUMA height (min(i, height - 1))
instead of the chroma height, so when the image height is not a multiple of 16 (1944 = 121.5 x 16) the last four Cr rows are read past the end of
the YU12 buffer. The buffer (AllocatedFrame, a std::vector<uint8_t> of exactly w*h*3/2 bytes) sits right before a scudo guard page, so
libjpeg's forward_DCT faults (SIGSEGV, SEGV_ACCERR) and the camera provider dies.

The patch makes AllocatedFrame::allocate() allocate 2.5*w*h bytes instead of 1.5*w*h by changing ONE Thumb-2 instruction:
    add.w r3, r3, r3, lsl #1   (r3 = 3*w*h, later halved)      bytes 03 eb 43 03
    add.w r3, r3, r3, lsl #2   (r3 = 5*w*h, later halved)      bytes 03 eb 83 03
The plane layout is unchanged; there is just room after the Cr plane, so the over-read stays inside the allocation. (The four chroma rows
below the picture then hold whatever is in the buffer; they only influence the last block row of the chroma in the bottom 8 pixel rows.)

Usage:  patch_external_camera_hal.py camera.device@3.4-external-impl.so patched.so [--vaddr 0x2f446]
The address is specific to the library of the unit this was done on (sha256 of the original below); for another build, find
AllocatedFrame::allocate() (`objdump -d` with arm-linux-gnueabihf binutils, `-M force-thumb`) and look for `add.w r3, r3, r3, lsl #1` right after the
`mul.w` of width*height. The script refuses to patch anything that does not contain exactly the expected four bytes there.
"""
import hashlib
import struct
import sys

ORIGINAL_SHA256 = '7f9709755376a60b64af35d41c96a361692919f5a0b47b4ce52f70b0d9c58efa'  # the unit's original library
EXPECTED = bytes.fromhex('03eb4303')   # add.w r3, r3, r3, lsl #1
PATCHED = bytes.fromhex('03eb8303')    # add.w r3, r3, r3, lsl #2


def vaddr_to_offset(data, vaddr):
    if data[:4] != b'\x7fELF' or data[4] != 1 or data[5] != 1:
        raise SystemExit('not a 32-bit little-endian ELF file')
    e_phoff, = struct.unpack_from('<I', data, 0x1C)
    e_phentsize, e_phnum = struct.unpack_from('<HH', data, 0x2A)
    for i in range(e_phnum):
        p_type, p_offset, p_vaddr, _, p_filesz, _, p_flags, _ = struct.unpack_from('<IIIIIIII', data, e_phoff + i * e_phentsize)
        if p_type == 1 and p_vaddr <= vaddr < p_vaddr + p_filesz:
            return p_offset + (vaddr - p_vaddr)
    raise SystemExit('address 0x%x is not inside a loadable segment' % vaddr)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    vaddr = 0x2f446
    for a in sys.argv[1:]:
        if a.startswith('--vaddr'):
            vaddr = int(a.split('=', 1)[1], 0) if '=' in a else int(sys.argv[sys.argv.index(a) + 1], 0)
    if len(args) < 2:
        raise SystemExit(__doc__)
    src, dst = args[0], args[1]
    data = bytearray(open(src, 'rb').read())
    sha = hashlib.sha256(data).hexdigest()
    off = vaddr_to_offset(data, vaddr)
    cur = bytes(data[off:off + 4])
    print('input sha256 %s%s' % (sha, '' if sha == ORIGINAL_SHA256 else '  (NOT the library this was written for)'))
    print('address 0x%x -> file offset 0x%x, bytes %s' % (vaddr, off, cur.hex()))
    if cur == PATCHED:
        raise SystemExit('already patched')
    if cur != EXPECTED:
        raise SystemExit('refusing to patch: expected %s (add.w r3, r3, r3, lsl #1)' % EXPECTED.hex())
    data[off:off + 4] = PATCHED
    open(dst, 'wb').write(data)
    print('wrote %s, sha256 %s' % (dst, hashlib.sha256(data).hexdigest()))


if __name__ == '__main__':
    main()

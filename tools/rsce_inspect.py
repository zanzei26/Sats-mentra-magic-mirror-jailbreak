import struct, hashlib
b = open('/path/to/backup-pieces/boot_p7.bin','rb').read()
base = 27025408
toff, esz = b[base+9], b[base+10]
nent = struct.unpack_from('<I', b, base+12)[0]
print('RSCE: tbl_offset', toff, 'entry_size(blocks)', esz, 'entries', nent)
for k in range(nent):
    eo = base + toff*512 + k*esz*512
    e = b[eo:eo+esz*512]
    name = e[4:260].split(b'\0')[0].decode(errors='replace')
    off, size = struct.unpack_from('<II', e, 260)
    dp = base + off*512
    d = b[dp:dp+size]
    extra = ''
    if d[:2] == b'BM':
        fsz, _, _, pix = struct.unpack_from('<IHHI', d, 2)
        hs, w, h, pl, bpp, comp, isz = struct.unpack_from('<IiiHHII', d, 14)
        extra = f'  BMP {w}x{h} {bpp}bpp comp={comp} filesize={fsz} pixel_offset={pix} imagesize={isz}'
    print(f'{k} {name:18s} offset_blocks={off} boot_byte={dp} size={size} sha={hashlib.sha256(d).hexdigest()[:12]}{extra}')

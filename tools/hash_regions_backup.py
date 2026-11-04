import hashlib
B = '/path/to/eMMC_full_backup.img'
SUPER = 0x150c00 * 512
for name, sec, n in (('vendor', 1837056, 467312), ('product', 2306048, 580864), ('odm', 2887680, 40408)):
    h = hashlib.sha256()
    with open(B, 'rb') as f:
        f.seek(SUPER + sec * 512)
        left = n * 512
        while left:
            b = f.read(min(left, 8 << 20)); h.update(b); left -= len(b)
    print(f'{name:8s}{h.hexdigest()}  (backup)')

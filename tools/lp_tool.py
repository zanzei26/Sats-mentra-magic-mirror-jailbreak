#!/usr/bin/env python3
"""Minimal liblp (Android dynamic partitions) metadata parser / rewriter for the SATS mirror super partition.
Usage:
  lp_tool.py dump  <super_head.bin>
  lp_tool.py build <stock_super_head.bin> <out.bin> --system-sectors N --extent-b-start S
"""
import hashlib, struct, sys

GEOM_FMT = '<II32sIII'              # magic, struct_size, checksum, metadata_max_size, slot_count, logical_block_size
GEOM_MAGIC = 0x616c4467
HDR_FMT = '<IHHI32sI32s'            # magic, major, minor, header_size, header_checksum, tables_size, tables_checksum
HDR_MAGIC = 0x414C5030
DESC_FMT = '<III'                   # offset, num_entries, entry_size
PART_FMT = '<36sIIII'               # name, attributes, first_extent_index, num_extents, group_index
EXT_FMT = '<QIQI'                   # num_sectors, target_type, target_data, target_source
GRP_FMT = '<36sIQ'                  # name, flags, maximum_size
BDEV_FMT = '<QIIQ36sI'              # first_logical_sector, alignment, alignment_offset, size, name, flags
RES = 4096
GSZ = 4096


def cstr(b):
    return b.split(b'\0', 1)[0].decode()


def parse_geometry(buf, off):
    magic, ssz, ck, max_size, slots, lbs = struct.unpack_from(GEOM_FMT, buf, off)
    assert magic == GEOM_MAGIC, hex(magic)
    raw = bytearray(buf[off:off + ssz]); raw[8:40] = b'\0' * 32
    assert hashlib.sha256(raw).digest() == ck, 'geometry checksum'
    return dict(struct_size=ssz, max_size=max_size, slots=slots, lbs=lbs)


def parse_metadata(buf, off):
    magic, major, minor, hsz, hck, tsz, tck = struct.unpack_from(HDR_FMT, buf, off)
    assert magic == HDR_MAGIC, hex(magic)
    hdr = bytearray(buf[off:off + hsz]); hdr[12:44] = b'\0' * 32
    assert hashlib.sha256(hdr).digest() == hck, 'header checksum'
    p = off + struct.calcsize(HDR_FMT)
    descs = []
    for _ in range(4):
        descs.append(struct.unpack_from(DESC_FMT, buf, p)); p += 12
    flags = struct.unpack_from('<I', buf, p)[0] if hsz >= p - off + 4 else 0
    tables = bytes(buf[off + hsz: off + hsz + tsz])
    assert hashlib.sha256(tables).digest() == tck, 'tables checksum'
    def ents(d, fmt):
        o, n, sz = d
        assert sz == struct.calcsize(fmt), (sz, fmt)
        return [struct.unpack_from(fmt, tables, o + i * sz) for i in range(n)]
    parts = [dict(name=cstr(a), attr=b, first=c, n=d, group=e) for a, b, c, d, e in ents(descs[0], PART_FMT)]
    exts = [dict(sectors=a, ttype=b, data=c, src=d) for a, b, c, d in ents(descs[1], EXT_FMT)]
    grps = [dict(name=cstr(a), flags=b, max=c) for a, b, c in ents(descs[2], GRP_FMT)]
    bdevs = [dict(first=a, align=b, align_off=c, size=d, name=cstr(e), flags=f) for a, b, c, d, e, f in ents(descs[3], BDEV_FMT)]
    return dict(major=major, minor=minor, hsz=hsz, flags=flags, parts=parts, exts=exts, grps=grps, bdevs=bdevs,
                raw_header=bytes(buf[off:off + hsz]))


def read_all(path):
    buf = open(path, 'rb').read()
    g = parse_geometry(buf, RES)
    g2 = parse_geometry(buf, RES + GSZ)
    assert g == g2, 'primary/backup geometry differ'
    prim = RES + 2 * GSZ
    back = prim + g['max_size'] * g['slots']
    slots = []
    for s in range(g['slots']):
        a = parse_metadata(buf, prim + s * g['max_size'])
        try:
            b = parse_metadata(buf, back + s * g['max_size'])
        except AssertionError as e:
            b = None
        slots.append((a, b))
    return buf, g, slots


def dump(path):
    buf, g, slots = read_all(path)
    print(f'geometry: {g}')
    for s, (a, b) in enumerate(slots):
        print(f'--- slot {s}: v{a["major"]}.{a["minor"]} header_size={a["hsz"]} flags={a["flags"]} backup_equal={b is not None and a["parts"]==b["parts"] and a["exts"]==b["exts"]}')
        for bd in a['bdevs']: print('  block device', bd)
        for gr in a['grps']: print('  group', gr)
        tot = 0
        for p in a['parts']:
            es = a['exts'][p['first']:p['first'] + p['n']]
            sec = sum(e['sectors'] for e in es); tot += sec
            print(f'  part {p["name"]:10s} attr={p["attr"]} group={p["group"]} sectors={sec} ({sec*512/1048576:.1f} MiB)')
            for e in es: print(f'      extent {e["sectors"]:>9d} sectors  type={e["ttype"]} phys_sector={e["data"]} dev={e["src"]}')
        print('  total partition sectors', tot)


def pack_tables(parts, exts, grps, bdevs):
    pt = b''.join(struct.pack(PART_FMT, p['name'].encode().ljust(36, b'\0'), p['attr'], p['first'], p['n'], p['group']) for p in parts)
    et = b''.join(struct.pack(EXT_FMT, e['sectors'], e['ttype'], e['data'], e['src']) for e in exts)
    gt = b''.join(struct.pack(GRP_FMT, g['name'].encode().ljust(36, b'\0'), g['flags'], g['max']) for g in grps)
    bt = b''.join(struct.pack(BDEV_FMT, d['first'], d['align'], d['align_off'], d['size'], d['name'].encode().ljust(36, b'\0'), d['flags']) for d in bdevs)
    offs = []; o = 0
    for t in (pt, et, gt, bt): offs.append(o); o += len(t)
    tables = pt + et + gt + bt
    descs = [(offs[0], len(parts), struct.calcsize(PART_FMT)), (offs[1], len(exts), struct.calcsize(EXT_FMT)),
             (offs[2], len(grps), struct.calcsize(GRP_FMT)), (offs[3], len(bdevs), struct.calcsize(BDEV_FMT))]
    return tables, descs


def build(stock_path, out_path, system_sectors, b_start):
    buf, g, slots = read_all(stock_path)
    a, _ = slots[0]
    assert a['major'] == 10
    bdev = a['bdevs'][0]
    byname = {p['name']: p for p in a['parts']}
    assert set(byname) >= {'system', 'vendor', 'product', 'odm'}, list(byname)
    sys_ext = a['exts'][byname['system']['first']:byname['system']['first'] + byname['system']['n']]
    assert len(sys_ext) == 1 and sys_ext[0]['ttype'] == 0
    A = sys_ext[0]
    extB_sectors = system_sectors - A['sectors']
    assert extB_sectors > 0 and extB_sectors % 8 == 0 and b_start % 8 == 0
    dev_sectors = bdev['size'] // 512
    assert b_start + extB_sectors <= dev_sectors, 'extent B beyond super'
    # B must not overlap any other partition extent
    others = []
    for n in ('vendor', 'product', 'odm'):
        p = byname[n]
        for e in a['exts'][p['first']:p['first'] + p['n']]:
            others.append((e['data'], e['data'] + e['sectors'], n))
    for lo, hi, n in others:
        assert b_start >= hi or b_start + extB_sectors <= lo, f'extent B overlaps {n}'
    new_parts, new_exts = [], []
    for name in ('system', 'vendor', 'product', 'odm'):
        p = dict(byname[name])
        es = [dict(e) for e in a['exts'][p['first']:p['first'] + p['n']]]
        if name == 'system':
            es.append(dict(sectors=extB_sectors, ttype=0, data=b_start, src=A['src']))
        p['first'] = len(new_exts); p['n'] = len(es)
        new_exts += es; new_parts.append(p)
    grp = a['grps'][1] if len(a['grps']) > 1 else a['grps'][0]
    total = sum(e['sectors'] for e in new_exts)
    gi = new_parts[0]['group']
    assert total * 512 <= a['grps'][gi]['max'], f'group max exceeded: {total*512} > {a["grps"][gi]["max"]}'
    tables, descs = pack_tables(new_parts, new_exts, a['grps'], a['bdevs'])
    # header: keep stock header layout (version, header_size, flags), recompute descriptors/size/checksums
    hsz = a['hsz']
    hdr = bytearray(a['raw_header'])
    struct.pack_into('<I', hdr, 44, len(tables))
    struct.pack_into('<32s', hdr, 48, hashlib.sha256(tables).digest())
    p = 80
    for d in descs:
        struct.pack_into(DESC_FMT, hdr, p, *d); p += 12
    hdr[12:44] = b'\0' * 32
    struct.pack_into('<32s', hdr, 12, hashlib.sha256(bytes(hdr)).digest())
    blob = bytes(hdr) + tables
    assert len(blob) <= g['max_size'], 'metadata does not fit'
    out = bytearray(buf)
    prim = RES + 2 * GSZ
    back = prim + g['max_size'] * g['slots']
    pad = blob + b'\0' * (g['max_size'] - len(blob))
    out[prim:prim + g['max_size']] = pad            # slot 0 primary
    out[back:back + g['max_size']] = pad            # slot 0 backup
    open(out_path, 'wb').write(bytes(out))
    print(f'built {out_path}: system {system_sectors} sectors = A {A["sectors"]}@{A["data"]} + B {extB_sectors}@{b_start}; '
          f'group total {total} sectors ({total*512/1048576:.1f} MiB) of max {a["grps"][gi]["max"]/1048576:.1f} MiB; blob {len(blob)} of {g["max_size"]} bytes')


if __name__ == '__main__':
    if sys.argv[1] == 'dump':
        dump(sys.argv[2])
    elif sys.argv[1] == 'build':
        args = dict(zip(sys.argv[4::2], sys.argv[5::2]))
        build(sys.argv[2], sys.argv[3], int(args['--system-sectors']), int(args['--extent-b-start']))

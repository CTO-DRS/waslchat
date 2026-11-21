#!/usr/bin/env python3
"""Minimal ELF64 strip: drop non-alloc sections except .shstrtab (debug info, symtab)."""
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
assert d[:4] == b'\x7fELF' and d[4] == 2 and d[5] == 1
(e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize,
 e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from('<HHIQQQIHHHHHH', d, 16)
SH = '<IIQQQQIIQQ'
secs = [list(struct.unpack_from(SH, d, e_shoff + i * e_shentsize)) for i in range(e_shnum)]
SHF_ALLOC = 2
keep = [i for i, s in enumerate(secs) if i == 0 or (s[2] & SHF_ALLOC) or i == e_shstrndx]
# end of loaded content
end = e_phoff + e_phnum * e_phentsize
for i in range(e_phnum):
    p = struct.unpack_from('<IIQQQQQQ', d, e_phoff + i * e_phentsize)
    end = max(end, p[2] + p[5])
for i in keep:
    s = secs[i]
    if s[2] & SHF_ALLOC and s[1] != 8:  # not NOBITS
        end = max(end, s[4] + s[5])
out = bytearray(d[:end])
remap = {old: new for new, old in enumerate(keep)}
new_secs = []
for i in keep:
    s = list(secs[i])
    if i == e_shstrndx:
        while len(out) % 8: out.append(0)
        data = d[s[4]:s[4] + s[5]]
        s[4] = len(out); out += data
    elif i != 0 and not (s[2] & SHF_ALLOC):
        pass
    s[6] = remap.get(s[6], 0)  # sh_link
    if s[1] in (4, 9):  # RELA/REL: sh_info is section index
        s[7] = remap.get(s[7], 0)
    new_secs.append(s)
while len(out) % 8: out.append(0)
shoff = len(out)
for s in new_secs: out += struct.pack(SH, *s)
struct.pack_into('<Q', out, 40, shoff)
struct.pack_into('<HH', out, 60, len(new_secs), remap[e_shstrndx])
open(dst, 'wb').write(out)
print(f"{len(d)} -> {len(out)} bytes, sections {e_shnum} -> {len(new_secs)}")

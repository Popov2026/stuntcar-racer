#!/usr/bin/env python3
# mkblob.py ELF OBJDUMP BIN RELS : binaire brut lié en 0 (net.ld) + table des mots longs absolus
# à reloger (R_68K_32), pour scrf030.s (incbin "net.bin", include "netrel.s")
import subprocess, sys
elf, objdump, out_bin, out_rel = sys.argv[1:5]
rel = []
for line in subprocess.run([objdump, '-r', elf], capture_output=True, text=True, check=True).stdout.splitlines():
    f = line.split()
    if len(f) >= 3 and f[1] == 'R_68K_32':
        rel.append(int(f[0], 16))
    elif len(f) >= 3 and f[1].startswith('R_68K') and not f[1].startswith('R_68K_PC'):
        sys.exit('relocation inattendue : ' + line)
with open(out_rel, 'w') as o:
    o.write('; netrel.s - produit par mkblob.py : mots longs de net.bin à reloger (+ adresse de net.bin)\n')
    for i in range(0, len(rel), 8):
        o.write('\tdc.l\t' + ','.join('$%x' % r for r in rel[i:i + 8]) + '\n')
    o.write('\tdc.l\t-1\n')
print('%d relocations' % len(rel))

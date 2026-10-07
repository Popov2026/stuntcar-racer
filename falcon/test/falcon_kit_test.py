#!/usr/bin/env python3
"""falcon_kit_test.py - `scr_tool.py falcon` sur la fausse disquette (fake_disk.py).
Le contrôle de version du jeu reçoit un faux programme (pas de données du jeu).

    python3 falcon_kit_test.py FAUSSE.st DOSSIER"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools'))
import scr_tool  # noqa: E402

o = 0x13498 - scr_tool.TEXT_BASE + 0x1C       # noms des circuits dans le programme
fake = bytearray(o + 16)
fake[o:o + 11] = b'LITTLE RAMP'
scr_tool.game_program = lambda img: bytes(fake)
scr_tool.falcon_kit(open(sys.argv[1], 'rb').read(), sys.argv[2])
st = open(os.path.join(sys.argv[2], 'SCR_F030.ST'), 'rb').read()
names = list(scr_tool.fat_list(st))
print('disquette Falcon :', ', '.join(names))
assert names.index('AUTO/F030AUTO.PRG') < names.index('AUTO/DEBUT.PRG'), 'ordre du dossier AUTO'
for k, v in scr_tool.fat_list(open(sys.argv[1], 'rb').read()).items():
    assert scr_tool.fat_list(st)[k] == v, k
print('contenu d\'origine intact, F030AUTO.PRG avant DEBUT.PRG : OK')

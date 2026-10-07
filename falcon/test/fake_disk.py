#!/usr/bin/env python3
"""fake_disk.py - fausse disquette « d'origine » pour tester `scr_tool.py falcon` et la
disquette Falcon produite, sans les données du jeu.

    python3 fake_disk.py SORTIE.st

Contenu : AUTO/DEBUT.PRG = test/build/DEBUT.PRG (doublure du menu, lance GAME.PUT),
GAME.PUT = test/build/GAME.PUT (doublure du jeu), HIGHSCOR.ES. Le BPB annonce
0 secteur par cluster, comme la disquette d'origine."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools'))
import scr_tool  # noqa: E402

build = os.path.join(HERE, 'build')
files = [('AUTO/DEBUT.PRG', open(os.path.join(build, 'DEBUT.PRG'), 'rb').read()),
         ('GAME.PUT', open(os.path.join(build, 'GAME.PUT'), 'rb').read()),
         ('HIGHSCOR.ES', bytes(512))]
img = bytearray(scr_tool.fat12_image(files, spc=1, label='SCR TEST'))
img[13] = 0                                    # BPB d'origine : 0 secteur par cluster
open(sys.argv[1], 'wb').write(img)
print(sys.argv[1], ':', ', '.join(scr_tool.fat_list(bytes(img))))

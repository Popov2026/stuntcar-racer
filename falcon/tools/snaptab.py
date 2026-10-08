#!/usr/bin/env python3
"""snaptab.py - table des zones mémoire que SCRF030 sauvegarde puis restaure autour de
l'image intermédiaire (falcon/src/snaptab.s).

L'image intermédiaire est un appel supplémentaire de la routine de rendu du jeu ($51BCC).
Ce rendu écrit dans des variables (page zéro 6502, générateur pseudo-aléatoire, tampons de
travail) : elles sont remises dans leur état d'avant pour que la logique du jeu reste
exactement celle d'origine.

Zones = octets vus modifiés par $51BCC (24 rendus pendant une course sous Hatari : copies
de la mémoire à l'entrée et au retour, écrans exclus), complétés par des blocs entiers
autour, MOINS les octets écrits par les interruptions (la VBL du jeu, son chrono, le
clavier) et la pile : les restaurer ferait perdre des VBL au chronomètre ou des touches.

    python3 snaptab.py [RELEVÉ.txt] > ../src/snaptab.s
RELEVÉ.txt : « adresse longueur » en hexadécimal/décimal (adresses du jeu chargé à $10100).
"""
import sys

OBSERVED = """
108f0 63
10937 1
10942 10
10954 1
10963 1
1096f 2
10981 16
109a2 9
109be 6
109ce 106
10a43 35
10a6f 13
10aa6 2
10ab7 11
10b44 74
10b98 22
46d8e 4
47a99 1
4fbac 5
50cc2 2
52c16 4
52e50 8
53155 9
53169 9
53534 4
54d02 2
54d90 1
55eec 2
562fb 3
56633 41
56927 97
56b87 177
6ea7c 1
6eb24 56
6ebaa 41
6ec10 8
6ec35 7
6ec5c 64
6ecd5 63
6ed4c 48
6ed9d 63
6ee15 63
6ee91 43
6f6ac 32
6f6ed 31
6f72c 2
6f76d 31
6fd8d 57
702b8 16
702dc 985
708aa 2854
713eb 18
730f2 82
73198 20
"""
# variables mêlées au code (0000-8000) : destinations absolues de toutes les
# instructions d'écriture du jeu (analyse statique du désassemblage)
STATIC = """
4472c 4
45376 3
4537a 1
4537c 58
45814 2
460c0 1
461a8 2
461b6 1
461b8 12
4672c 1
46838 6
469d4 1
46d7e 23
47a98 2
47ca1 1
48b8e 1
48d84 3
4a52c 4
4ad0c 1
4afb6 1
4b0a4 1
4bbde 2
4c0f0 11
4c29c 1
4cc9c 2
4d058 2
4e1fc 1
4e506 1
4eddc 1
4fbac 5
50005 1
501de 11
5031a 1
5034c 2
504be 4
50ae6 3
50cc2 2
50cf5 1
51138 1
51145 1
5118f 1
51894 5
518aa 1
519b6 1
52266 1
52c16 4
52e50 1
52e52 10
52ff6 2
53151 1
53155 1
53159 1
5315d 1
53167 1
53169 1
5316d 1
53171 1
53534 1
53536 6
54d00 6
54d90 2
55062 4
55d8a 2
55eec 2
562f6 8
5662a 1
5662c 13
5663a 1
5663c 1
5663e 1
56642 1
56646 5
5664c 1
56650 12
56926 6
56c6c 16
"""
BLOCKS = [(0x108e0, 0x10c00), (0x56900, 0x56c7c), (0x6ea00, 0x73370)]
# écrits par les interruptions : VBL ($4EC24, chrono $51F38, $4BCC8), clavier ($104B4)
EXCLUDE = (set(range(0x10200, 0x10400)) | set(range(0x10600, 0x10700)) |
           {0x109c4, 0x109c5, 0x109c6, 0x109c7, 0x109cd, 0x10a1e, 0x10a1f,
            0x4ec20, 0x4ec21, 0x4ec22, 0x4ec23, 0x4ed0e, 0x4ed0f, 0x4edd0} |
           set(range(0x6f02c, 0x6f0ac)) |
           set(range(0x10ac2, 0x10ad4)))        # caméra : restaurée à part


def main():
    text = open(sys.argv[1]).read() if len(sys.argv) > 1 else OBSERVED + STATIC
    keep = set()
    for line in text.split('\n'):
        p = line.split()
        if len(p) == 2:
            a, n = int(p[0], 16), int(p[1])
            keep |= set(range(a, a + n))
    for a, b in BLOCKS:
        keep |= set(range(a, b))
    keep -= EXCLUDE
    rng = []
    for a in sorted(keep):
        if rng and a == rng[-1][1] + 1:
            rng[-1][1] = a
        else:
            rng.append([a, a])
    total = sum(e - s + 1 for s, e in rng)
    print('; snaptab.s - produit par falcon/tools/snaptab.py : zones restaurées après')
    print('; l\'image intermédiaire (adresses du jeu chargé à $10100, longueur en octets)')
    print('; %d zones, %d octets' % (len(rng), total))
    print('SNAP_BYTES\tequ\t%d' % total)
    print('snaptab:')
    for s, e in rng:
        print('\tdc.l\t$%05x,%d' % (s, e - s + 1))
    print('\tdc.l\t0')


if __name__ == '__main__':
    main()

# Version Falcon030

## Ce qui est fait : `falcon/`

Le programme d'origine (`GAME.PUT`, sur **votre** disquette) est exécuté **tel quel** par le
68030. Le lanceur `falcon/bin/SCRF030.PRG` (source `falcon/src/scrf030.s`, 2 Ko) prépare la
machine pour qu'elle s'y comporte comme un Atari ST, puis remet tout en place au retour.
Mode d'emploi : `falcon/LISEZMOI.txt`.

| Problème ST → Falcon | Traitement par SCRF030 |
|---|---|
| Le jeu suppose la basse résolution ST (320×200, 16 couleurs, plans entrelacés, base vidéo `$FF8201/03`, palette `$FF8240`) | mode compatible du VIDEL (`Setscreen` mode 3, `STMODES\|BPS4`, lignes doublées en VGA) sur un écran à nous, aligné sur 256 octets, en ST-RAM ; mode, écran et palettes (ST et VIDEL) rétablis |
| Le chargeur JEK de `GAME.PUT` recopie sa dernière routine à **écran + `$7F00`** (sur un ST, l'écran est au sommet de la RAM : cette zone est libre jusqu'à la fin de la mémoire). Avec un écran de 32 000 octets ailleurs, la routine écrase `GAME.PUT` pendant qu'il est recopié (exception « Line F » à `text+$9A`) ; avec l'écran d'EmuTOS en haut des 14 Mo (`$DF8200`), elle sortirait de la RAM | écran de **32 Ko** (`$8000`) dans la BSS du lanceur, comme le haut de la RAM d'un ST, y compris pour `F030AUTO.PRG` (résident) |
| Code décompressé (JEK/ByteKiller) puis relogé avant exécution, code issu du 6502 | caches d'instructions et de données coupés (`CACR = $0808`) |
| Logique, chrono et son moteur cadencés par la VBL (8,33 ticks/s à 50 Hz) : 20 % trop rapides à 60 Hz | table des vecteurs déplacée (`VBR`) vers des relais `move.l (n*4).w,-(sp) ; rts` ; à 60 Hz, le relais de la VBL ne transmet que 5 VBL sur 6. La fréquence est **mesurée** (horloge 200 Hz) |
| `move sr,<ea>` privilégiée sur 68010+ | violation de privilège : `move sr,Dn` et `move sr,-(a7)` émulés en mode utilisateur, sinon renvoi au vecteur du TOS |
| La physique lit l'octet `$FF` (`move.b $FF.l,d0` en `$49718`, au lieu de `#$FF`) : octet faible du vecteur 63, différent sur chaque TOS (EmuTOS : `$02`) | le CPU lisant la table déplacée, l'octet `$FF` reçoit la valeur voulue `$FF` (rétabli au retour) |
| Son YM2149 | PSG dirigé vers l'ADC puis l'additionneur du codec (`Soundcmd`) |
| Disquette d'origine : BPB à 0 secteur par cluster | `scr_tool.py falcon` reconstruit une disquette FAT12 standard, `F030AUTO.PRG` (même lanceur, résident, pour le dossier `AUTO`) avant le menu `DEBUT.PRG` |

Options : `8` / Shift (8 MHz et bus STE via `$FFFF8007`), `C` / Control (caches laissés),
`N` / Alternate (pas de correction 60 Hz) — touches au lancement, ligne de commande ou
première ligne de `SCRF030.INF`.

### Tests sous Hatari

`falcon/test/run_tests.sh` : Hatari en Falcon030 (68030 16 MHz, 14 Mo, EmuTOS 512 Ko),
lancement automatique de `SCRF030.PRG`, compte rendu par NatFeats d'une **doublure** de
`GAME.PUT` (`falcon/test/standin.s`) qui fait avec la machine ce que fait le jeu, sans les
données du jeu. Résultats (Hatari 2.6.1, EmuTOS de septembre 2026) :

| Cas | Vérifié |
|---|---|
| VGA, RVB, TV | ST basse active (`$FF8260 = 0`), double tampon, palette, 50 VBL/s, caches coupés, `move sr` émulé (`$0308` dans Dn, `$0300` en pile), octet `$FF` = `$FF` |
| RVB NTSC (60 Hz) | 50 VBL/s vues par le jeu ; 60 avec l'option `N` |
| 8 MHz | `$FFFF8007 = $40` (CPU et blitter à 8 MHz, bus STE) |
| caches émulés (`--cpu-exact`) | code modifié puis exécuté : correct ; **avec l'option `C`, le 68030 exécute l'ancienne instruction** (le piège évité par défaut) |
| clavier | octets IKBD reçus par le gestionnaire `$118` du jeu à travers la table de relais |
| disquette | `scr_tool.py falcon` sur une fausse disquette au BPB d'origine ; démarrage : `AUTO\F030AUTO.PRG` → menu → `GAME.PUT` |
| retour | VBR = 0, `CACR = $3111`, octet `$FF`, mode 640×480 du bureau : rétablis |

### Le vrai jeu

`falcon/test/game_test.sh disque.st sortie [hd|floppy] [vga|rgb|tv]` : version Falcon
préparée depuis la disquette, puis menus traversés au clavier jusqu'à une course (Espace,
nom « AB », Entrée, *Start the Racing Season*, vue d'ensemble, départ), captures toutes
les 6 s. Essayé avec la disquette « Compact Disk 2.1 » (`Stunt_Car_Racer_1989Micro_Styleb2.st`) :

| Lancement | Résultat |
|---|---|
| disque dur, `SCRF030.PRG`, VGA | décompactage JEK, écran du cracker, titre, générique, menus, nom, pilotes, division 4, course 3 sur Little Ramp : vue d'ensemble, grue (« DROP START »), adversaire qui part, chronomètre qui tourne |
| disque dur, RVB | idem |
| disquette `SCR_F030.ST`, VGA | `AUTO\F030AUTO.PRG`, menu de la compilation (touche 2), puis idem |

Le premier essai a révélé le problème du chargeur JEK (écran + `$7F00`, voir le tableau),
corrigé depuis. Le pilotage se fait au joystick, que les scripts ne savent pas injecter :
`hatari_falcon.sh -w` ouvre une fenêtre avec le joystick sur les flèches et Ctrl droit.
Rien n'a été essayé sur un vrai Falcon.

Particularité de Hatari : en ST basse sur VGA, la fréquence du VIDEL est mal calculée
(480 Hz, ramenés à 50) ; un vrai Falcon est à 60 Hz. SCRF030 mesurant la fréquence, il est
correct dans les deux cas ; la correction 60 Hz est testée en RVB NTSC.

## Pistes suivantes

## Ce qui ne se porte pas tel quel

La version PC (`native/`) **n'est pas une réécriture** du jeu : elle exécute le code 68000
d'origine dans un émulateur (Musashi) et redessine l'image en HD à partir de l'état du jeu.
Elle ne peut donc pas servir directement sur Falcon, qui a de toute façon un vrai 68030.
Un émulateur 68000 écrit en C serait beaucoup trop lent sur un 68030 à 16 MHz. Le moteur HD
(rendu logiciel 1080p multicœur) l'est aussi.

Une version Falcon030 consiste donc à **reprendre le programme d'origine** (code 68000 du jeu,
extrait de votre disquette) et à le modifier. Ce projet fournit les outils et la documentation
nécessaires pour cela.

## Ce qui sert

| Élément | Usage pour le Falcon |
|---|---|
| `tools/scr_tool.py` | lecture de la disquette (FAT12 au BPB faux), décompression JEK/ByteKiller, extraction du programme du jeu (TEXT $5D6C6 + BSS $5BAA) |
| `tools/dasm.c` | désassembleur 68000 pour produire un source réassemblable |
| `tools/stemu.c` | émulateur ST sans affichage : points d'arrêt, journal des PC, surveillance mémoire (pratique pour tester un patch) |
| `docs/RETRO_INGENIERIE.md` | adresses des routines et variables (boucle, physique, rendu, remplissages, sprites, VBL, clavier) |
| `native/src/machine.cpp` | liste exacte de ce que le jeu demande au système : TOS minimal (Super, Cursconf, Keytbl, Jenabint, Physbase, Floprd), registres matériel touchés, vecteurs détournés |
| `native/src/track.cpp` | décodage des circuits (sections gauche/droite, hauteurs) en C lisible |
| `native/src/render3d.cpp` | principe d'un rendu par polygones avec tampon 1/z et découpage aux bords, si vous réécrivez le rendu |
| `native/src/hdview.cpp` | caméra calée sur l'original (focale, centre, hauteur de l'œil), couleurs et alternances (route, flancs, lignes de bord) |

## Points d'attention connus sur 68030 / Falcon

Ce sont des règles générales du portage ST → Falcon, appliquées à ce que l'on sait du jeu.
Celles que traite `SCRF030.PRG` sont dans le tableau du début ; rien n'a été essayé sur un
vrai Falcon.

* **Matériel ST détourné directement** : vecteur clavier `$118` (routine `$104B4`), VBL `$70` →
  `$4EC24`, base vidéo écrite en `$FF8201/03`, YM2149 pour le son. Le Falcon garde ces
  registres en mode compatible ST. Si vous passez à un mode VIDEL, la base vidéo et le
  format de l'écran changent (voir plus bas).
* **Caches du 68030** : le code est décompressé puis relogé en mémoire avant d'être exécuté.
  Il faut vider le cache d'instructions après ces étapes, ou couper les caches.
* **Cadence** : la logique est réglée par la VBL (compteur `$4EC20` rechargé à 6, soit
  8,33 ticks/s). Le jeu ne devrait donc pas accélérer à 16 MHz. Le rendu (`$51BCC`,
  ≈ 91 000 instructions) sera simplement plus rapide, ce qui peut rendre l'image plus fluide.
  En VGA (60 Hz), la VBL est ramenée à 50 par SCRF030.
* **Protection** : la Copylock (mode trace, vecteur `$24`, `$49E38`) est déjà neutralisée sur
  la version étudiée (octet `$51898`). Une autre version de la disquette peut la contenir encore.
* **Code issu du 6502** : variables d'un octet à adresses absolues, pointeurs petit-boutistes
  convertis par `rol.w #8`. Il n'y a rien de spécifique au 68000 là-dedans, mais il faut le
  savoir en lisant le désassemblage.

## Idées d'améliorations propres au Falcon

* **Écran** : toutes les écritures à l'écran passent par peu de routines. Le décor passe par
  les remplissages `$53166`, `$533EC`-`$53456`, `$5461A`-`$546BE` et `$553D8`-`$55442`. Le
  cockpit passe par les blits `$567B0`-`$56880`, le tableau de bord par `$46C3E`-`$46D06`,
  `$4B890` et `$53212`-`$5327C`. Les réécrire suffit pour passer à un autre format d'écran
  (par exemple 256 couleurs en plans entrelacés, ou 16 bits « true colour »), voire à une
  résolution plus haute si la projection est adaptée.
* **DSP 56001** : les transformations 3D et la projection des points du circuit dans `$51BCC`
  sont de bons candidats pour un déport sur le DSP.
* **Son** : le moteur est joué par la VBL sur le YM2149. Le DMA son 16 bits du Falcon permet
  de mieux faire.

## Données du jeu

Aucune donnée ni aucun code du jeu n'est fourni ici. Tout s'extrait de **votre** image disque
`.st` avec `tools/scr_tool.py`.

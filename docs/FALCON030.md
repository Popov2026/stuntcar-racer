# Version Falcon030

## Ce qui est fait : `falcon/`

Le programme d'origine (`GAME.PUT`, sur **votre** disquette) est exécuté **tel quel** par le
68030. Le lanceur `falcon/bin/SCRF030.PRG` (source `falcon/src/scrf030.s`, 4 Ko) prépare la
machine pour qu'elle s'y comporte comme un Atari ST, puis remet tout en place au retour.
Mode d'emploi : `falcon/LISEZMOI.txt`.

| Problème ST → Falcon | Traitement par SCRF030 |
|---|---|
| Le jeu suppose la basse résolution ST (320×200, 16 couleurs, plans entrelacés, base vidéo `$FF8201/03`, palette `$FF8240`) | mode compatible du VIDEL (`Setscreen` mode 3, `STMODES\|BPS4`, lignes doublées en VGA) sur un écran à nous, aligné sur 256 octets, en ST-RAM ; mode, écran et palettes (ST et VIDEL) rétablis |
| Le chargeur JEK de `GAME.PUT` recopie sa dernière routine à **écran + `$7F00`** (sur un ST, l'écran est au sommet de la RAM : cette zone est libre jusqu'à la fin de la mémoire). Avec un écran de 32 000 octets ailleurs, la routine écrase `GAME.PUT` pendant qu'il est recopié (exception « Line F » à `text+$9A`) ; avec l'écran d'EmuTOS en haut des 14 Mo (`$DF8200`), elle sortirait de la RAM | écran de **32 Ko** (`$8000`) dans la BSS du lanceur, comme le haut de la RAM d'un ST, y compris pour `F030AUTO.PRG` (résident) |
| Code décompressé (JEK/ByteKiller) puis relogé avant exécution, code issu du 6502 | caches d'instructions et de données coupés (`CACR = $0808`) pendant le chargement ; rallumés quand le jeu installe sa VBL (mode fluide), le cache d'instructions étant vidé à chaque VBL |
| Logique, chrono et son moteur cadencés par la VBL (8,33 ticks/s à 50 Hz) : 20 % trop rapides à 60 Hz | table des vecteurs déplacée (`VBR`) vers des relais `move.l (n*4).w,-(sp) ; rts` ; à 60 Hz, le relais de la VBL ne transmet que 5 VBL sur 6. La fréquence est **mesurée** (horloge 200 Hz) |
| `move sr,<ea>` privilégiée sur 68010+ | violation de privilège : `move sr,Dn` et `move sr,-(a7)` émulés en mode utilisateur, sinon renvoi au vecteur du TOS |
| La physique lit l'octet `$FF` (`move.b $FF.l,d0` en `$49718`, au lieu de `#$FF`) : octet faible du vecteur 63, différent sur chaque TOS (EmuTOS : `$02`) | le CPU lisant la table déplacée, l'octet `$FF` reçoit la valeur voulue `$FF` (rétabli au retour) |
| Le chargeur JEK écrit la palette en `$0FFF8240` : ce n'est `$FF8240` qu'en adressage 24 bits (8 bits forts ignorés, Falcon d'origine) ; en 32 bits (Hatari avec TT-RAM, cartes accélératrices), erreur de bus | `GAME.PUT` chargé sans être lancé (`Pexec` 3), les trois adresses corrigées en `$FFFF8240` (texte `+$80`, `+$172`, `+$216`, chacune vérifiée avec l'opcode qui la précède), caches vidés, puis lancé (`Pexec` 6). Le jeu lui-même n'écrit qu'en `$00FFxxxx`, que les Falcon à 68060 (CT60, CT63) décodent aussi |
| Son YM2149 | PSG dirigé vers l'ADC puis l'additionneur du codec (`Soundcmd`) |
| Disquette d'origine : BPB à 0 secteur par cluster | `scr_tool.py falcon` reconstruit une disquette FAT12 standard, `F030AUTO.PRG` (même lanceur, résident, pour le dossier `AUTO`) avant le menu `DEBUT.PRG` |

Options : `8` / Shift (8 MHz et bus STE via `$FFFF8007`), `C` / Control (caches laissés),
`N` / Alternate (pas de correction 60 Hz), `O` (jeu d'origine : ni caches, ni routines
réécrites), `T` (sans les routines réécrites), `K` (caches coupés), `F` (images extrapolées, expérimental), `3` (F1 en logique ×3), `6` (F1 en logique ×6, d'office sur 68040/68060) — touches au
lancement, ligne de commande ou première ligne de `SCRF030.INF`.

Commandes : le jeu se pilote au **joystick** (port 1), menus compris (sa routine de lecture
des touches, `$46DAC`, traduit le joystick en codes de flèches). SCRF030 ajoute le clavier :
à chaque VBL, la table des touches du jeu (`$6F02C`, `$B3` = enfoncée) donne flèches et
Espace, écrits dans le joystick du jeu (`$106A6`, format de son `$118`) tant qu'une de ces
touches est enfoncée. Sous Hatari, sans émulation du joystick comme avec `--joystick 1`.

### Logique accélérée (touche F1) : 8,33 → 16,7, 25 ou 50 vraies images/s

F1 bascule entre normal et fluide (×2 : un tour toutes les 3 VBL, cadence stable sur un
Falcon030 à 16 MHz) ; avec l'option `3`, entre normal et très fluide (×3 : toutes les 2 VBL,
adaptatif ; sur 16 MHz la cadence varie entre 2 et 3 VBL selon la scène, d'où l'option,
pour les Falcon accélérés). À la place de `jsr $4B0A6` (attente de fin de tour, en
`$4AB90`), `tick_hook` décide à chaque tour : niveau demandé si la course est en cours
(compte à rebours `$109C9` nul ; la grue, le départ et la remise en piste comptent en tours
et gardent le rythme d'origine). En très fluide, on reste à 2 VBL tant que le tour y tient
(compteur de VBL non nul à l'entrée), on passe à 3 VBL pour le tour suivant sinon, et on
revient à 2 après 8 tours de suite à 3 VBL qui ont pris moins de 2 VBL. `dbl_patch` pose le niveau, chaque
site vérifié (une des valeurs connues), puis vide le cache d'instructions :

| Site | ×1 | ×2 | ×3 | ×6 | Pourquoi |
|---|---|---|---|---|---|
| 22 × `move.b #$EE,Dn` (`$48A08`, `$4B124`, `$4EFAA`…`$4F1B0`, `$507FE`, `$509EA`, `$50ED4`…`$50F50`) | `$EE` | `$77` | `$4F`/`$50` | `$27`/`$28` | `$EE` × n / 6 par tour de n VBL, reste gardé ;  facteur de pas : intégrations de la physique, avance de l'adversaire, accumulateur `$109B9` qui cadence les compteurs en temps de jeu (`$109B7` : dégâts, compte à rebours, carburant du turbo) |
| `$4B0C2` `move.b #6,$4EC20` | 6 | 3 | 2 | 1 | VBL par tour |
| `$4E6FC`-`$4E703` (`muls`, `asl`, `swap`, `lsr.w #7`) | d'origine | `jsr yaw_div` | `jsr yaw_div` | `jsr yaw_div` | réalignement du cap vers la piste, ajouté au lacet à chaque tour sans pas de temps : même calcul, × 1/2, 1/3 ou 1/6 (`mulu.w #$8000` / `#$5556` / `#$2AAB`, `swap`) |
| `$4EE64` | `$114` | `$228` | `$33C` | `$678` | amortisseur : proportionnel à la variation de compression d'un tour à l'autre (`$10B04`) |
| `$4B514` `move.b #$13,d0` | `$13` | 13 × n / 6 | 13 × n / 6 | 13 × n / 6 | chrono (`$11002` minutes, `$1101A` secondes, `$11032` centièmes, BCD) : 0,13 s par tour de 6 VBL, donc 13 × n / 6 centièmes par tour de n VBL, reste gardé (le jeu d'origine compte 8 % de trop : un tour dure 0,12 s) |

Validation dans le moteur fidèle (`replica/js/engine.js`, le code 68000 du jeu exécuté en
JavaScript), `falcon/test/double_test.js` : course normale contre course accélérée, mêmes
commandes au même instant : vitesse, lacet, chrono à 1 % près jusqu'au premier saut, en ×2
comme en ×3 (sans les corrections du cap et de l'amortisseur : départ 15 % plus lent,
voiture qui se réaligne deux fois trop vite). Après un saut, les deux parties divergent
comme deux parties réelles. Dégâts : comparer des parties entières ne veut rien dire (un
saut raté change tout) ; on rejoue donc les mêmes 12 tours depuis un même état, en normal
puis accéléré, toutes les 6 tours de 8 parties (1 167 passages, 8 circuits) : 5 789 points
de dégâts en normal, 6 524 en ×2 (+ 13 %), 6 664 en ×3 (+ 15 %), sans correction. Sur un saut
donné les pics de force diffèrent (2 496 et 3 271 en normal, 1 851 et 2 229 puis 1 454 et
1 845 en ×2), mais majorer la force pour les dégâts surcompense (× 1,17 : + 46 %).

Sous Hatari (`--cpu-exact on`, 68030 à 16 MHz), en course : ×2, un échange d'écran toutes
les 3 VBL (724 sur 865, le reste : grue à 6 VBL, et 6 tours à 4 ou 5 ; dans une autre partie,
470 à 3 VBL et 11 à 4, tous regroupés sur une seconde, la voiture en tonneau contre un mur
juste avant une chute) ; ×3 adaptatif, par
tranches de 10 s : 166, 249, 76, 189, 143 et 77 images à 2 VBL contre 38, 1, 32, 18, 1 et
14 à 3 VBL et quelques-unes à 4 (le reste : grue). Un tour de course prend le plus souvent
moins de 2 VBL (profil : 1,85 VBL en moyenne grue comprise ; à la fin du calcul, 2 VBL
restantes sur 3 dans 81 % des tours) ; le profil est plat (routines réécrites 28 % du
travail, une trentaine de routines du jeu entre 1 et 6 %).

### Falcon à 68060 (CT60, CT63) et 68040 : VGA, adressage 32 bits, logique ×6

Le même `SCRF030.PRG` reconnaît le processeur (cookie `_CPU` = 40 ou 60) :

* **adressage 32 bits** : `GAME.PUT` est chargé par `Pexec` 3, les trois écritures du
  chargeur JEK en `$0FFF8240` corrigées en `$FFFF8240` (voir le tableau du haut), puis lancé
  par `Pexec` 6. TT-RAM permise : `GAME.PUT` (drapeaux 0) et l'écran du lanceur restent en
  ST-RAM, seule visible du VIDEL ;
* **caches** à recopie (copyback) des 68040/68060 : l'ancien bit CI du CACR n'existe plus.
  Au chargement : `CPUSHA BC` (cache de données écrit en mémoire), `CACR = 0`, `CINVA BC`.
  Le jeu en place : `CACR` du TOS (ou `$A0808000` sur 68060 : données, tampon d'écriture,
  branchements, instructions, s'il les avait coupés). Code modifié (relais, routines posées,
  niveau de logique, chrono, à chaque VBL) : `CPUSHA BC` puis `CABC` (cache de branchements,
  68060). Couleur du tracé de pixel (`t_color`) : `CPUSHL BC` sur les deux lignes concernées
  au lieu de `CAAR` + `CEI`. Les instructions sont posées en `dc.w` (assemblage en 68030) ;
* **`$FFFF8007`** (horloge et bus du Falcon) laissé tel quel ;
* **logique ×6** : un tour par VBL, **50 vraies images/s**, fluide dès le départ (F1 : retour
  au jeu normal). Pas de temps `$EE` / 6 (`$27`/`$28` avec le reste), 1 VBL par tour,
  amortisseur `$678`, cap × 1/6. Adaptatif : un tour qui déborde (compteur nul à l'entrée)
  fait descendre d'un niveau (×6 → ×3 → ×2) ; après 8 tours de suite qui tiennent dans le
  niveau au-dessus (compteur ≥ 2), on remonte. L'option `6` l'active sur 68030 (inutile à
  16 MHz), l'option `3` limite à ×3. Moteur fidèle (`double_test.js traj 6`) : vitesses à
  2 % près jusqu'au premier saut.

**À 60 Hz** (VGA, RVB NTSC), la correction 60 Hz garde la VBL du jeu (son, compteurs) à
50 Hz, mais une cadence de 50 tours/s sur un écran à 60 Hz tiendrait une image sur six deux
VBL. En logique accélérée, le compteur de VBL du tour (`$4EC20`) suit donc les **vraies**
VBL : la VBL retenue le décrémente aussi (comme le fait la VBL du jeu en `$4EC2C`). Les
niveaux deviennent 4, 3 et 2 vraies VBL par tour : **15, 20 et 30 images/s à cadence
fixe**, avec un pas de temps `$EE` × 5n / 36 (reste gardé), un chrono 65 × n / 36,
l'amortisseur et le cap au facteur 36 / 5n (1,8, 2,4 et 3,6 : `$1F1`, `$296`, `$3E2` ;
`#$8E39`, `#$6AAB`, `#$471C`). Sur 68040/68060 en VGA : 30 images/s. Sur Falcon030 en VGA,
F1 donne 15 images/s régulières (au lieu de 16,7 irrégulières), l'option 3 20 images/s.
Sous Hatari en RVB NTSC (Hatari affiche le VGA en ST basse à 50 Hz) : 68060 à 128 MHz,
1 115 images à 2 VBL ; Falcon030 16 MHz exact avec F1, 570 à 4 VBL, sans exception (le
reste : grue et départ, au rythme d'origine). Même partie, mêmes commandes : écart avec
l'adversaire 1 547 et −1 230 à 30 images/s, 1 517 et −1 259 à 15 images/s.

Sous Hatari (`--machine falcon --cpulevel 6 --addr24 off --ttram 64 --fpu internal`,
EmuTOS) : le jeu se charge et tourne en adressage 32 bits avec TT-RAM. Hatari ne dépasse pas
32 MHz et n'émule pas la vitesse d'un 68060 ; avec une horloge portée à 64 et 128 MHz
(Hatari modifié pour les essais), en course : à 64 MHz, 505 images à 1 VBL, 235 à 2, 24 à 3 ;
à 128 MHz, 945 à 1 VBL, 24 à 2 et 7 à 3 ; à 32 MHz, entre 2 et 3 VBL (×3 / ×2). Les caches
du 68060 ne sont pas émulés par Hatari : leur gestion n'a pas pu être essayée sur une
vraie CT60.

### Mode HD (F2) et mode texturé (F3) : Falcon à 68060/68040 avec FPU, VGA

Lanceur à part : `SCRCT60.PRG` (même source, `-DCT60=1`) ; `SCRF030.PRG` n'a pas les modes
HD. Conditions, vérifiées au lancement et affichées : 68040/68060 (`_CPU`), FPU essayée
(`fnop` sous un vecteur « ligne F » provisoire, le cookie `_FPU` n'étant pas fiable), moniteur
VGA, 1,1 Mo (TT-RAM de préférence) + 32 Ko + 300 Ko de ST-RAM. `SCRCT60.LOG` (écrit au
lancement) : cookies, essai de la FPU, moniteur, raison d'un refus, registres du VIDEL.

`falcon/hd/hd.c` (C sans bibliothèque, `m68k-elf-gcc -m68060`, lié en 0 par `hd.ld`, binaire
`hd.bin` et table de relogement `hdrel.s` produits par `mkblob.py`, inclus dans `SCRF030.PRG`
et relogés au lancement) redessine la scène à partir de l'état du jeu, port du mode HD de
`native/` : géométrie des 8 circuits décodée dans le programme du jeu (port de `$48390`),
caméra `$10AC2` (œil, focale 259 × 2, centre 153,2 / 82,3, rapport 0,895), adversaire
(`$10907`, `$108F6`, `$109D6`, boîtes orientées selon la route), sol, collines, route en
triangles, lignes de bord, flancs. Peintre (cases de profondeur de 64 unités, dessinées dans
l'ordre d'ajout), découpage au plan proche puis en 2D, remplissage par lignes dans un tampon
d'octets de la fenêtre 3D seule (512 × 256), textures 16 × 16 à deux couleurs en
perspective (une division par groupe de 16 pixels). Sortie : écran 640 × 480 en 16 couleurs
(4 plans, palette du VIDEL `$FF9800` remplie à chaque VBL depuis la palette de course du jeu
`$6EA3C`), 400 lignes utiles ; la fenêtre est convertie en plans par table, le cockpit hors
fenêtre recopié du jeu en plans directement (bits et lignes doublés).

Côté jeu, en mode HD :

| Modification | Pourquoi |
|---|---|
| `$10824` : `move.l $56C74,d3` → `move.l #brouillon,d3` | la fenêtre 3D `$56C78` (= d3 + `$A10`) pointe dans un écran brouillon : le décor du jeu y est dessiné, invisible. Neutraliser les remplissages ne marche pas : ils remettent à zéro les listes de bords que le tracé des bords (`$5353C`) fait avancer, qui écrasaient alors le jeu |
| `$5313E` : `rts` | le tracé de pixel (lignes du décor) écrit dans `$56C74`, l'écran de travail : supprimé (sans effet de bord ; moteur fidèle : même partie) |
| après chaque échange, fenêtre de l'écran de travail en couleur 1 | la couleur 1 (route) n'est jamais employée par le cockpit (moteur fidèle : histogramme des couleurs de la fenêtre, décor supprimé) : elle marque la scène, le reste est incrusté |
| `$1083E`, `$10846` : `nop` | le jeu n'écrit plus l'adresse d'écran ; on affiche nos deux écrans HD |

L'image HD est calculée dans le tour (à la place de l'attente), à partir de l'écran affiché du
jeu (`$56C70`, image précédente, roues dessinées par la VBL comprises). Tour déjà débordé :
image sautée (au plus 3 de suite). Plus de tour pendant une seconde (menus) : retour au mode
du jeu. Registres du VIDEL des deux modes relevés au lancement (`Setscreen` du TOS).

Au passage : le second chargeur du jeu recopie sa routine de relogement en
`Physbase - $7D00` (sur un ST, sous l'écran en haut de la RAM) ; le lanceur place donc
32 Ko inutilisés au chargement (les écrans de l'option F) juste sous son écran.

**Bordures sur 68060** : le choix de couleur `$53094` réécrit les `bset`/`bclr` du tracé de
pixel `$5313E` (le seul code que le jeu modifie en course : moteur fidèle, écritures dans du
code déjà exécuté, 8 circuits). Sur 68030, le cache d'instructions de 256 octets est vidé
ligne par ligne (`t_color`) ; sur 68060, `CPUSHL` ne suffisait pas : bordure d'une seule
couleur, qui clignotait. Sur 68040/68060, `$5313E` est remplacé par `t_pixel`, qui lit la
couleur notée par `t_color` (mêmes écritures, même d0, même Z).

Sous Hatari (68060 à 128 MHz modifié, VGA) : F2 et F3 s'affichent, F2 revient au jeu. Le 68060
de Hatari est très lent : environ 30 VBL par image HD, 50 en texturé. Profil : découpage et
projection 48 %, remplissage 26 % (70 % en texturé). La vitesse sur une vraie CT60 n'a pas pu
être mesurée.

### Images extrapolées (option `F`, expérimentale) : 8,33 → 20 images/s

**Par défaut depuis le 13/10 : désactivées.** Le lanceur rallume les caches et pose les routines
réécrites (mêmes images, octet pour octet), sans images supplémentaires : chaque image est une
vraie image du jeu, 8,33 images/s. Les images extrapolées ont deux défauts de fond, visibles
en jeu : la caméra prolongée se trompe dès que le mouvement change (bosses, sauts, virages :
l'image tressaute), et le jeu dessine une partie du cockpit (roues avant qui suivent la
suspension, lignes 122-175, depuis sa VBL) et du tableau de bord directement dans l'écran
affiché (`$56C70`, motif « `G_DRAW` = `G_DISP` » le temps du dessin, `$10450` et une dizaine
d'autres) : ces dessins manquent sur les images extrapolées, des morceaux de l'image sautent.
La voie propre est la logique accélérée (touche F1, ci-dessus).


Le jeu fait un tour (logique + rendu `$51BCC` + échange d'écran) au plus toutes les 6 VBL
(compteur `$4EC20` rechargé à 6) : 8,33 images/s sur Falcon (6,5 environ sur ST, dont le rendu
dépasse parfois 6 VBL). Quand le jeu installe sa VBL, le relais le reconnaît (signature à
`$4EC24`, `$4B0C2`, nom du circuit, appels `$4AA8C`/`$4AB90`) et :

1. **caches rallumés** : un tour passe de 2,9 à 1,8 VBL ;
2. **routines réécrites pour le 68030** (`falcon/src/turbo.s`, voir plus bas) ;
3. **images extrapolées** : l'appel de l'attente de fin de tour (`jsr $4B0A6`, en `$4AB90`)
   est détourné. Pendant cette attente, après le rendu normal du tour N (qui sera affiché par
   le jeu à V0, début du tour suivant), le rendu du jeu est rappelé une ou deux fois, caméra
   (`$10AC2`, 18 octets) et adversaire (pièce, section, position latérale) **prolongés** de
   3/6 de tour, ou de 2/6 et 4/6, dans le sens N-1 → N, dans quatre écrans à nous (deux par
   tour, en alternance). Une file préparée pendant le tour devient active à la VBL qui le
   termine ; la VBL affiche ensuite chaque image à V0+3, ou V0+2 et V0+4 (`$FF8201/03`).
   Deux images sont tentées dès que deux fois la durée mesurée tient dans le temps restant ;
   en attendant la seconde, la première est déjà en file à V0+3 (la VBL bascule d'une file à
   l'autre sur un seul mot) : si la seconde ne tient pas, le rythme reste 3/3.
   Interpoler entre N-1 et N n'aurait permis de montrer l'image qu'à V0+4 au mieux (elle ne
   peut être dessinée qu'après le rendu normal) : rythme 4/2.
   * L'écran supplémentaire ne reçoit de l'image du tour que ce que le rendu ne repeint pas et
     qui change : la fenêtre 3D (128 lignes de 128 octets) est toujours entièrement repeinte
     (40 rendus relevés), et hors d'elle seuls changent d'un tour à l'autre le haut du cadre
     (lignes 0-15) et le bas entre les montants (lignes 144-199, octets 16-143) : 9,7 Ko par
     image, le reste (15,6 Ko) à la 1re utilisation de l'écran puis une fois sur 8.
   * Les variables que le rendu modifie (`falcon/src/snaptab.s`, 71 zones, 5,0 Ko, produit par
     `falcon/tools/snaptab.py` à partir de relevés mémoire avant/après rendu et de l'analyse
     statique des écritures) sont sauvegardées puis rétablies, **sauf** celles qu'écrivent les
     interruptions (VBL, chrono, clavier), la pile, et les tampons de travail que chaque rendu
     réécrit avant de les lire (bords `$70510`-`$716FF`, `$6FD80`, `$6EF6A`) : vérifié en les
     remplissant au hasard avant et après chacun de 400 rendus, mêmes images.
   * Nombre d'images d'après le temps restant et leur durée mesurée (horloge 200 Hz) ; aucune
     si la caméra saute (grue). **Sûreté** : si une image n'est pas finie quand le tour se
     termine, la VBL détourne son retour d'interruption vers une routine qui abandonne le
     rendu, rétablit l'état et rend la main au jeu à temps — le jeu échange donc toujours ses
     écrans à la même VBL que l'original.
   * **Adversaire** : sa position est « pièce, section.fraction » (`$10907`, `$108F6`, octet
     fort = section) ; il avance d'environ 0,85 section par tour et change de pièce tous les
     3 ou 4 tours. Le rendu le dessine à la position qu'il a en entrant, puis le fait avancer
     d'un tour (`$5079C`, `$5081E`) : la position relevée après le rendu N est celle du rendu
     N+1, celle relevée après N-1 est celle dessinée en N. L'image à k/6 le place entre les
     deux : position de N-1 + avance × k/6 (longueur de la pièce ajoutée s'il en a changé),
     pièce suivante au-delà de la dernière section (nombre de sections : type de la pièce
     `$10CE6`, données `$13670`, comme `$4D3D2`/`$4D4D6`). Mesuré sous Hatari, image par
     image depuis la mémoire vidéo : taille et position de l'adversaire progressent sans
     retour en arrière. (Avant le 12/10 : prolongé seulement sans changement de section,
     soit 15 % des tours, et à partir de la position du tour suivant ; il avançait et
     reculait d'une image à l'autre.)
   * **Bogue corrigé** (version du 12/10) : la reconnaissance du jeu, faite dans la VBL quand
     il installe la sienne, modifiait le registre a1 sans le rendre. Si la VBL tombait dans la
     boucle du jeu qui recopie le tableau des pilotes par a1 (`$49E0C`), ce tableau
     (« -------- ») était écrit dans le code du lanceur (`set_extrap`) : images extrapolées
     fausses, partie qui dérape (collisions, adversaire figé, plus de direction), plantage.
     Selon l'adresse de chargement, donc le mode de lancement (.TOS ou .PRG), la boucle était
     touchée ou non.

Mesures sous Hatari (`--cpu-exact on`, caches du 68030 émulés), accélérateur enfoncé sur Little
Ramp, voiture en course : **20,5 images/s** en moyenne sur quatre alignements du jeu en mémoire
(20 à 21 ; deux images extrapolées dans environ la moitié des tours, une ailleurs ; une image
extrapolée coûte 35 à 45 ms, il en faudrait au plus 35 pour en mettre deux dans chaque tour,
soit 25 images/s). L'alignement du code sur les lignes du cache d'instructions fait varier le
résultat de quelques pour cent : les comparaisons se font sur quatre décalages. Même partie
rejouée depuis un instantané, avec et sans le mode fluide : position, vitesse, caméra,
adversaire, générateur pseudo-aléatoire relevés à chaque tour de physique (`$4EEB0`) : **tous
les états identiques, aux mêmes VBL** (1357 sur 1357).

### Routines réécrites pour le 68030

`falcon/src/turbo.s` : un `jmp` posé à l'entrée de la routine d'origine (adresses du jeu
relogées à l'installation) ; mêmes octets écrits, mêmes registres au retour (mots forts
compris), même CCR ; les cas rares (découpage d'un bord, table pleine) retournent au code
d'origine avant toute écriture. Option `T` : sans elles.

| Routine | Original | Réécrite |
|---|---|---|
| `$5353C` tracé d'un bord de polygone (12 % du temps) | Bresenham pas à pas en x : 5 instructions par pixel pour les bords plus larges que hauts | un pas par ligne : x = x0 ± ⌈((j-1)·dx + f)/dy⌉, f = dx/2+1, en q ou q+1 (dx = q·dy + r) ; erreur finale et extrémités démontrées identiques ; 2 fois moins d'instructions |
| `$53ACA` même tracé après découpage d'un bord | idem | idem, avec l'en-tête conditionnel (`$5353A`) et le prolongement du bord (`$53536`/`$53538`) ; `a1` et le mot fort de `d0` conservés |
| `$552C0`, `$53304` boucles par ligne du remplissage des polygones et des triangles | 400 octets, cas rares mêlés au chemin courant : rechargées dans le cache d'instructions (256 octets) à chaque ligne | mêmes instructions dans le même ordre, chemin courant d'un seul tenant ; cas rares renvoyés au code d'origine à l'instruction exacte |
| `$56762` sprite masqué du cockpit | lecture + écriture de l'écran pour chaque bloc de 16 pixels | bloc opaque (masque nul) : écrit sans lire ; masque plein et plans nuls : rien ; ≈ 27 % d'accès en moins |

**Code que le jeu modifie** : `$53094` (choix de la couleur) réécrit, à chaque couleur, les
opcodes `bset`/`bclr` du tracé de pixel `$5313E` (un par plan) ; le cache d'instructions du
68030 ne voit pas ces écritures et pourrait exécuter l'ancienne couleur. Avec les caches
allumés, `t_color` appelle l'original puis, si la couleur a changé, retire du cache les mots
longs modifiés (`CAAR` + `CEI`, drapeaux de l'original rendus). Relevé sous Hatari : en course,
ce sont les seuls octets d'instructions exécutées qui changent (121 copies de la mémoire
comparées) ; l'analyse statique des écritures à adresse fixe ne trouve rien d'autre après le
démarrage. Coût : 0,8 image/s.

Vérification :

* `falcon/test/bench/` (Musashi en 68030, même version que `native/`) : l'original et la
  réécrite sur une copie de la mémoire prise en course, entrées au hasard (registres, sommets
  dans et hors de la fenêtre, table pleine, fond d'écran), comparaison de toute la mémoire et
  des registres : 300 000 bords, **toutes les pentes** (dx 0-255, dy 0-127, deux sens, deux
  ordres : 131 072 cas), 30 000 tracés après découpage, 5 000 sprites — aucune différence ;
* rejeu (`bench replay`) : mémoire et registres relevés sous Hatari à l'entrée d'appels réels,
  rejoués avec le code d'origine puis avec le code réécrit : 60 polygones, 60 triangles,
  120 lignes de décor (pixel et couleur) — aucune différence ;
* dans le jeu sous Hatari, variante de contrôle (`-DSELFCHECK=1 -DCHKEDGE=1` ou `-DCHKSPR=1`) :
  chaque appel réel exécute l'original puis la réécrite sur les mêmes entrées et compare
  registres, CCR et mémoire : 40 941 bords et 1 108 sprites d'une course, **aucun écart**.

Remarque : le rendu du jeu lit des variables que la VBL modifie pendant qu'il dessine
(chrono, tableau de bord…) ; dès qu'il va plus vite ou plus lentement, ses images diffèrent de
quelques octets à quelques centaines (essai : le rendu d'origine retardé de 7 ms change les 40
images relevées). Comparer des images entières ne permet donc pas de juger une réécriture :
d'où les contrôles appel par appel ci-dessus.

**Pourquoi pas le DSP** : profil du 68030 (profileur de Hatari, 10 s de course, mode fluide) :

| Poste | Part du temps |
|---|---|
| attente de la VBL (`$4B0A6`) | 26 % |
| tracé des bords de polygones et remplissages (`$53000`-`$55500`), sprites du cockpit (`$56700`) | ≈ 30 % |
| copies du mode fluide (avant les réductions ci-dessus) | 15 % |
| **multiplications et divisions** (rotations, projection) | **1,6 %** |
| VBL du jeu, dont le **son** du moteur sur le YM2149 (`$4EC24`) et le chrono | **0,4 %** |
| reste du jeu (logique, tri, découpage, tableau de bord) | ≈ 27 % |

Le rendu est limité par les écritures en mémoire. Le DSP n'a pas accès à la mémoire du
Falcon : tout ce qu'il calcule repasserait mot par mot par le port hôte, au prix de ce qu'on
voulait gagner. Le déport des calculs 3D rapporterait au mieux 2 %, celui du son 0,3 % (le
YM2149 est une vraie puce du Falcon : le 68030 n'y écrit que quelques registres par VBL).

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

(La doublure n'étant pas reconnue comme le jeu, le mode fluide ne s'y enclenche pas : ces
cas vérifient la préparation de la machine ; le mode fluide est vérifié avec le vrai jeu.)

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
* **DSP 56001** : mesuré, les transformations 3D et la projection ne font que 2 % du temps
  (voir « Mode fluide ») ; un déport n'apporterait presque rien tant que le 68030 écrit
  lui-même l'écran.
* **Son** : le moteur est joué par la VBL sur le YM2149. Le DMA son 16 bits du Falcon permet
  de mieux faire.

## Données du jeu

Aucune donnée ni aucun code du jeu n'est fourni ici. Tout s'extrait de **votre** image disque
`.st` avec `tools/scr_tool.py`.

#!/bin/sh
# hatari_falcon.sh - exécute Stunt Car Racer (ou la doublure de test) dans Hatari
# en Falcon030 : 68030 à 16 MHz, VIDEL, 14 Mo, sans DSP.
#
# usage : hatari_falcon.sh [options] SORTIE
#   -c DOSSIER  dossier monté en C: ; C:\SCRF030.PRG y est lancé automatiquement
#   -f IMAGE    démarrer sur cette disquette (dossier AUTO), au lieu de -c
#   -t TOS      image TOS : EmuTOS 512 Ko (etos512*.img) ou TOS 4.0x   [$TOS]
#   -H HATARI   exécutable de Hatari                                   [$HATARI, sinon hatari]
#   -m MONITEUR vga | rgb | tv                                         [vga]
#   -v N        nombre de VBL émulées avant de quitter                 [3000]
#   -s N        capture d'écran à la VBL N (option répétable)
#   -k N:CODE   appui sur la touche CODE (code clavier ST, décimal : 57 = espace,
#               28 = Entrée, 59 = F1) vers la VBL N (option répétable, N croissants)
#   -n          NVRAM réglée en NTSC (60 Hz) : moniteur RVB/TV à 60 Hz
#   -x          CPU « cycle exact » : caches du 68030 émulés
#   -w          fenêtre visible, vitesse réelle, son (sinon : sans affichage, accéléré)
#
# Résultats dans SORTIE : console.txt (sortie de Hatari, dont les messages NatFeats
# de la doublure), vblN.png (captures).
set -e

HATARI=${HATARI:-hatari}
MON=vga
VBLS=3000
SHOTS=""
KEYS=""
CDIR=""
FLOPPY=""
EXACT=off
WINDOW=0
NTSC=0

while getopts "c:f:t:H:m:v:s:k:nxw" o; do
	case $o in
	c) CDIR=$OPTARG ;;
	f) FLOPPY=$OPTARG ;;
	t) TOS=$OPTARG ;;
	H) HATARI=$OPTARG ;;
	m) MON=$OPTARG ;;
	v) VBLS=$OPTARG ;;
	s) SHOTS="$SHOTS $OPTARG" ;;
	k) KEYS="$KEYS $OPTARG" ;;
	n) NTSC=1 ;;
	x) EXACT=on ;;
	w) WINDOW=1 ;;
	*) sed -n '2,20p' "$0"; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || { sed -n '2,20p' "$0"; exit 2; }
[ -n "$TOS" ] && [ -f "$TOS" ] || { echo "image TOS manquante (-t ou \$TOS)"; exit 2; }
[ -n "$CDIR$FLOPPY" ] || { echo "il faut -c DOSSIER ou -f IMAGE"; exit 2; }

OUT=$(mkdir -p "$1" && cd "$1" && pwd)
abs() { (cd "$(dirname "$1")" && echo "$(pwd)/$(basename "$1")"); }
TOS=$(abs "$TOS")

# captures : points d'arrêt du débogueur de Hatari sur le compteur de VBL
: > "$OUT/breakpoints.ini"
for n in $SHOTS; do
	echo "screenshot $OUT/vbl$n.png" > "$OUT/shot$n.ini"
	echo "b VBL = $n :once :trace :quiet :file $OUT/shot$n.ini" >> "$OUT/breakpoints.ini"
done
# touches : à la VBL N, le débogueur crée un fichier témoin ; ce script envoie alors
# l'événement clavier par la FIFO de commandes de Hatari (quelques VBL de décalage)
for k in $KEYS; do
	n=${k%%:*}
	rm -f "$OUT/.key$n.png"
	echo "screenshot $OUT/.key$n.png" > "$OUT/key$n.ini"
	echo "b VBL = $n :once :trace :quiet :file $OUT/key$n.ini" >> "$OUT/breakpoints.ini"
done

set -- --configfile /dev/null --machine falcon --cpulevel 3 --cpuclock 16 \
	--cpu-exact "$EXACT" --dsp none --memsize 14 --monitor "$MON" \
	--tos "$TOS" --natfeats on --statusbar off --drive-led off \
	--log-level error --parse "$OUT/breakpoints.ini" --run-vbls "$VBLS"
if [ -n "$FLOPPY" ]; then
	set -- "$@" --disk-a "$(abs "$FLOPPY")" --fastfdc on
	[ -n "$CDIR" ] && set -- "$@" --harddrive "$(cd "$CDIR" && pwd)"
else
	set -- "$@" --harddrive "$(cd "$CDIR" && pwd)" --auto 'C:\SCRF030.PRG'
fi
if [ -n "$KEYS" ]; then
	rm -f "$OUT/cmd.fifo"
	set -- "$@" --cmd-fifo "$OUT/cmd.fifo"
fi
if [ $WINDOW = 1 ]; then
	set -- "$@" --sound 44100
else
	set -- "$@" --sound off --fast-forward on
	export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
fi

# NVRAM du Falcon : mode vidéo de démarrage 640x400 16 couleurs, NTSC (bit PAL à 0)
if [ $NTSC = 1 ]; then
	mkdir -p "$OUT/.config/hatari"
	{ printf '\000\000\000\000\000\000\000\000\021\056\040\001\377\000\001\012'
	  head -c 34 /dev/zero; } > "$OUT/.config/hatari/hatari.nvram"
fi

cd "$OUT"
HOME="$OUT" "$HATARI" "$@" < /dev/null > console.txt 2>&1 &
HPID=$!
for k in $KEYS; do
	n=${k%%:*}
	while [ ! -s "$OUT/.key$n.png" ] && kill -0 $HPID 2>/dev/null; do sleep 0.01; done
	[ -p "$OUT/cmd.fifo" ] && kill -0 $HPID 2>/dev/null &&
		echo "hatari-event keypress ${k#*:}" > "$OUT/cmd.fifo"
done
wait $HPID || { echo "Hatari a échoué, voir $OUT/console.txt"; exit 1; }
grep -a "STANDIN" console.txt || true
ls "$OUT"/*.png 2>/dev/null || true

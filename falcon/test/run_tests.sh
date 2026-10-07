#!/bin/sh
# run_tests.sh - batterie de tests de la version Falcon030 sous Hatari, avec la doublure
# de GAME.PUT (aucune donnée du jeu nécessaire).
#
# usage : HATARI=/chemin/hatari TOS=/chemin/etos512us.img ./run_tests.sh [SORTIE]
#
# Prérequis : `make` dans falcon/ (vasm), Python 3. Chaque cas lance Hatari en Falcon030
# (EmuTOS ou TOS 4), démarre SCRF030.PRG (ou la disquette Falcon), lit le compte rendu
# NatFeats de la doublure et le compare aux valeurs attendues.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$HERE/build/results}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
BIN=$HERE/../bin
FAIL=0

# cas NOM MONITEUR OPTIONS_INF "OPTIONS_HATARI" VBL ATTENDUS...
# (attendus : clé=valeur ou clé~regex, lus dans le compte rendu de la doublure)
cas() {
	name=$1; mon=$2; inf=$3; hopts=$4; vbls=$5; shift 5
	c=$OUT/$name/C
	rm -rf "$OUT/$name"; mkdir -p "$c"
	cp "$BIN/SCRF030.PRG" "$HERE/build/GAME.PUT" "$c/"
	[ -n "$inf" ] && printf '%s\r\n' "$inf" > "$c/SCRF030.INF"
	# shellcheck disable=SC2086
	"$HERE/hatari_falcon.sh" -c "$c" -m "$mon" $hopts -v "$vbls" -s $((vbls - 10)) "$OUT/$name" > /dev/null
	check "$name" "$@"
}

check() {
	name=$1; shift
	line=$(grep -a '^STANDIN' "$OUT/$name/console.txt" | tail -1)
	if [ -z "$line" ]; then
		echo "ÉCHEC  $name : pas de compte rendu de la doublure"; FAIL=1; return
	fi
	ok=1
	for e in "$@"; do
		k=${e%%[=~]*}
		v=$(echo "$line" | tr ' ' '\n' | sed -n "s/^$k=//p")
		case $e in
		*=*) [ "$v" = "${e#*=}" ] || { ok=0; echo "  $name : $k=$v, attendu ${e#*=}"; } ;;
		*~*) echo "$v" | grep -Eq "^(${e#*~})$" || { ok=0; echo "  $name : $k=$v, attendu ${e#*~}"; } ;;
		esac
	done
	if [ $ok = 1 ]; then echo "OK     $name"; else echo "ÉCHEC  $name"; FAIL=1; fi
	echo "       $line"
}

COMMON="sr_dn~FFFF03.. sr_predec~03.. guard=1234 frames=150 ff8260=0000 byte_ff=00FF"

V50="vbl_per_sec~49|50|51"

# VGA. Remarque : en ST basse sur VGA, Hatari calcule mal la fréquence du VIDEL et
# produit 50 VBL/s (un vrai Falcon : 60). SCRF030 mesure la fréquence au lieu de la
# supposer : ici il ne corrige donc rien, et la correction 60 Hz est testée en NTSC.
cas vga         vga ""  ""    2300 $COMMON smc=2 "$V50" cacr=00000000 "ff8007~00[6-7][5d]"
# RVB PAL (50 Hz) et TV : rien à corriger
cas rgb         rgb ""  ""    2300 $COMMON smc=2 "$V50"
cas tv          tv  ""  ""    2300 $COMMON smc=2 "$V50"
# RVB NTSC (60 Hz) : une VBL sur six n'est pas transmise -> le jeu voit 50 VBL/s
cas rgb_ntsc    rgb ""  "-n"  2400 $COMMON smc=2 "$V50"
# même chose avec l'option N (pas de correction) : 60 VBL/s
cas rgb_ntsc_n  rgb "N" "-n"  2400 $COMMON smc=2 "vbl_per_sec~59|60|61"
# 8 MHz + bus STE : bits 0, 2 et 5 de $FFFF8007 à 0 (la doublure est alors lente)
cas mhz8        vga "8" ""    3000 $COMMON smc=2 "$V50" "ff8007~00[04][04]"
# CPU exact (caches émulés) : caches coupés par SCRF030 -> le code modifié est bien exécuté
cas exact       vga ""  "-x"  2300 $COMMON smc=2 cacr=00000000
# CPU exact, option C (caches laissés allumés par le TOS) : le cache d'instructions
# rend l'ancienne instruction (smc=1) ; c'est le piège que SCRF030 évite par défaut
cas exact_cache vga "C" "-x"  2300 $COMMON smc=1 "cacr~0000[0-9A-F]{3}[1-9A-F]"
# clavier : IKBD -> ACIA -> MFP -> table des vecteurs relais -> gestionnaire $118 du jeu
cas clavier     vga ""  "-k 1600:57 -k 1700:28 -k 1800:30" 2300 $COMMON smc=2 kbd=6

# disquette Falcon : F030AUTO.PRG (AUTO) -> DEBUT.PRG (menu) -> GAME.PUT
python3 "$HERE/fake_disk.py" "$OUT/fake.st" > /dev/null
rm -rf "$OUT/kit"
python3 "$HERE/falcon_kit_test.py" "$OUT/fake.st" "$OUT/kit" > "$OUT/kit.txt" || { cat "$OUT/kit.txt"; FAIL=1; }
grep -a "OK" "$OUT/kit.txt" | sed 's/^/OK     kit : /'
rm -rf "$OUT/floppy"
"$HERE/hatari_falcon.sh" -f "$OUT/kit/SCR_F030.ST" -m vga -v 3600 -s 2400 -s 3590 "$OUT/floppy" > /dev/null
check floppy $COMMON smc=2 "$V50" cacr=00000000

[ $FAIL = 0 ] && echo "Tous les tests sont passés." || echo "Des tests ont échoué."
exit $FAIL

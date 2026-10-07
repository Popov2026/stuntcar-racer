#!/bin/sh
# game_test.sh - le vrai jeu sur Falcon030 dans Hatari, à partir de VOTRE disquette.
#
# usage : HATARI=... TOS=... ./game_test.sh DISQUETTE.st SORTIE [hd|floppy] [vga|rgb|tv]
#
# Prépare la version Falcon (tools/scr_tool.py falcon), démarre le jeu depuis le disque
# dur (SCRF030.PRG lancé automatiquement, par défaut) ou depuis la disquette Falcon
# produite (menu de la compilation : touche 2), puis traverse les menus au clavier
# jusqu'à une course : Espace (écran du cracker, titre, Single Player League), nom « AB »,
# Entrée, Espace, 3 (Start the Racing Season), Espace (vue d'ensemble, départ).
# Captures toutes les 300 VBL (6 s) ; planche : SORTIE/planche.png (Pillow).
# Le pilotage se fait au joystick : pour jouer, ajouter -w à la commande affichée.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 2 ] || { sed -n '2,11p' "$0"; exit 2; }
DISK=$1; OUT=$2; MODE=${3:-hd}; MON=${4:-vga}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/kit"
python3 "$HERE/../../tools/scr_tool.py" falcon "$DISK" "$OUT/kit"

# repères en VBL (Hatari, Falcon VGA, EmuTOS) ; depuis la disquette, le menu de la
# compilation reçoit « 2 » et le jeu arrive au même moment
if [ "$MODE" = floppy ]; then SRC="-f $OUT/kit/SCR_F030.ST"; D=0; MENU="-k 2500:3"
else SRC="-c $OUT/kit/SCR"; D=0; MENU=""; fi
k() { echo "-k $(($1 + D)):$2"; }
KEYS="$MENU $(k 3600 57) $(k 5000 57) $(k 6000 57) $(k 7700 30) $(k 7750 48) $(k 7800 28)"
KEYS="$KEYS $(k 8100 57) $(k 8400 4) $(k 8700 57) $(k 9000 57) $(k 9300 57)"
SHOTS=""; for n in $(seq 1500 300 11100); do SHOTS="$SHOTS -s $((n + D))"; done
VBLS=$((11200 + D))
echo "$HERE/hatari_falcon.sh $SRC -m $MON -v $VBLS ... $OUT/run"
# shellcheck disable=SC2086
"$HERE/hatari_falcon.sh" $SRC -m "$MON" -v $VBLS $SHOTS $KEYS "$OUT/run" > /dev/null
grep -a -i "panic\|crash" "$OUT/run/console.txt" && echo "PLANTAGE : voir $OUT/run/console.txt"

python3 - "$OUT" <<'PY' || true
import glob, os, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
shots = sorted(glob.glob(os.path.join(out, 'run', 'vbl*.png')), key=lambda f: int(f.split('vbl')[-1][:-4]))
W, H = 320, 240
sheet = Image.new('RGB', (4 * W, ((len(shots) + 3) // 4) * (H + 14)), (20, 20, 20))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(shots):
    x, y = (i % 4) * W, (i // 4) * (H + 14)
    sheet.paste(Image.open(f).convert('RGB').resize((W, H)), (x, y + 14))
    d.text((x + 4, y + 2), os.path.basename(f)[:-4], fill=(255, 255, 255))
sheet.save(os.path.join(out, 'planche.png'))
print('planche :', os.path.join(out, 'planche.png'))
PY

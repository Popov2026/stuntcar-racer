#!/bin/sh
# game_test.sh - le vrai jeu sur Falcon030 dans Hatari, à partir de VOTRE disquette.
#
# usage : HATARI=... TOS=... ./game_test.sh DISQUETTE.st SORTIE [hd|floppy] [vga|rgb|tv]
#
# Prépare la version Falcon (tools/scr_tool.py falcon), démarre le jeu depuis le disque
# dur (C:\SCR\SCRF030.PRG, par défaut) ou depuis la disquette Falcon produite, appuie sur
# Espace pour passer l'écran titre, et fait une capture toutes les 250 VBL (5 s) pendant
# 90 s. Planche des captures : SORTIE/planche.png (Pillow). Pour jouer : ajouter -w dans
# la commande hatari_falcon.sh affichée.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 2 ] || { sed -n '2,11p' "$0"; exit 2; }
DISK=$1; OUT=$2; MODE=${3:-hd}; MON=${4:-vga}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/kit"
python3 "$HERE/../../tools/scr_tool.py" falcon "$DISK" "$OUT/kit"

SHOTS=""; for n in $(seq 1000 250 5500); do SHOTS="$SHOTS -s $n"; done
KEYS="-k 2500:57 -k 2750:57"
if [ "$MODE" = floppy ]; then SRC="-f $OUT/kit/SCR_F030.ST"; else SRC="-c $OUT/kit/SCR"; fi
echo "$HERE/hatari_falcon.sh $SRC -m $MON -v 5600 $SHOTS $KEYS $OUT/run"
# shellcheck disable=SC2086
"$HERE/hatari_falcon.sh" $SRC -m "$MON" -v 5600 $SHOTS $KEYS "$OUT/run"

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

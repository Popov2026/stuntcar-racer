#!/bin/sh
# build.sh [DOSSIER] : construit « bench » (Musashi, même version figée que native/)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
B=${1:-$HERE/../build/bench}
mkdir -p "$B"
B=$(cd "$B" && pwd)
if [ ! -d "$B/musashi" ]; then
	git clone -q https://github.com/kstenerud/Musashi.git "$B/musashi"
	git -C "$B/musashi" checkout -q 313ebf1bd9f4d0d93341eb5ce21fd8a119e9dbdd
fi
M=$B/musashi
cc -O2 -o "$B/m68kmake" "$M/m68kmake.c"
mkdir -p "$B/gen"
(cd "$B/gen" && "$B/m68kmake" "$B/gen" "$M/m68k_in.c" > /dev/null)
cc -O2 -w -I"$M" -I"$B/gen" -o "$B/bench" "$HERE/bench.c" "$M/m68kcpu.c" "$M/m68kdasm.c" \
	"$M/softfloat/softfloat.c" "$B/gen/m68kops.c" -lm
echo "$B/bench"

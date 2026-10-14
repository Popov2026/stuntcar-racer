/* hdtest.c - essai du mode HD sur PC : mémoire du Falcon (savebin de Hatari) -> image PPM
 * usage : hdtest ram.bin base sortie.ppm [mode] */
#include <stdio.h>
#include <stdlib.h>
#include "hd.h"
int main(int argc, char **argv) {
	if (argc < 4) return 1;
	FILE *f = fopen(argv[1], "rb");
	static u8 ram[16 << 20];
	size_t n = fread(ram, 1, sizeof ram, f); fclose(f);
	unsigned base = strtoul(argv[2], 0, 0);
	int mode = argc > 4 ? atoi(argv[4]) : 1; extern int hd_nowin; hd_nowin = argc > 5;
	static struct hdws ws;
	const u8 *G = ram + base - 0x10100;
	if (hd_init(G, &ws)) { puts("init"); return 1; }
	unsigned disp = (G[0x56c70] << 24 | G[0x56c71] << 16 | G[0x56c72] << 8 | G[0x56c73]) & 0xffffff;
	static u16 out[640 * 400 / 4];
	int r = hd_frame(ram + disp, out, mode);
	printf("polygones %d, sections %d, ecran du jeu %x (%zu octets lus)\n", r, ws.nsec, disp, n);
	/* palette de course du jeu ($6EA3C, format ST) */
	unsigned pal[16];
	for (int i = 0; i < 16; i++) {
		unsigned c = (G[0x6ea3c + 2 * i] << 8) | G[0x6ea3c + 2 * i + 1];
		unsigned r = (c >> 8) & 7, g = (c >> 4) & 7, b = c & 7;
		pal[i] = (r * 255 / 7) << 16 | (g * 255 / 7) << 8 | (b * 255 / 7);
	}
	FILE *o = fopen(argv[3], "wb");
	fprintf(o, "P6 640 400 255\n");
	for (int y = 0; y < 400; y++) for (int x = 0; x < 640; x++) {
		const u16 *g = out + (y * 640 + x) / 16 * 4; int b = 15 - (x & 15);
		int c = ((g[0] >> b) & 1) | (((g[1] >> b) & 1) << 1) | (((g[2] >> b) & 1) << 2) | (((g[3] >> b) & 1) << 3);
		unsigned v = pal[c]; fputc(v >> 16, o); fputc((v >> 8) & 255, o); fputc(v & 255, o);
	}
	fclose(o);
	return 0;
}

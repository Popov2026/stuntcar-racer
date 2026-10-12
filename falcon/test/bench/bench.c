/* bench.c - routine d'origine du jeu contre routine réécrite (falcon/src/turbo.s)
 *
 * Exécute les deux sur un 68030 émulé (Musashi), à partir d'une copie de la mémoire
 * prise en pleine course sous Hatari, avec des entrées tirées au hasard, et compare
 * TOUTE la mémoire (hors pile) et tous les registres au retour.
 *
 * usage : bench RAM.bin BASE SCRF030.PRG LISTING ROUTINE [N [GRAINE]]
 *   RAM.bin   copie de la mémoire à partir de 0 (savebin 0 $100000 dans Hatari)
 *   BASE      base TEXT du jeu dans cette copie (doc : $10100)
 *   LISTING   listing vasm de SCRF030.PRG (-L) : adresses des symboles
 *   ROUTINE   edge
 * Aucune donnée du jeu ici : la copie de la mémoire vient de votre disquette.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "m68k.h"

#define MEMSIZE  0x1000000
#define GAMEMEM  0x100000          /* comparé : la copie de la mémoire */
#define LOADADR  0xc00000          /* SCRF030.PRG chargé ici */
#define STACKTOP 0xf00000
#define SENTINEL 0xeffff0          /* adresse de retour : fin de l'appel */

static uint8_t mem[MEMSIZE], pristine[GAMEMEM], resA[GAMEMEM];
static uint32_t base;

unsigned int m68k_read_memory_8(unsigned int a) { return mem[a & (MEMSIZE - 1)]; }
unsigned int m68k_read_memory_16(unsigned int a) { a &= MEMSIZE - 1; return mem[a] << 8 | mem[a + 1]; }
unsigned int m68k_read_memory_32(unsigned int a) { return m68k_read_memory_16(a) << 16 | m68k_read_memory_16(a + 2); }
/* journal des écritures (diagnostic : BENCH_LOG=1) */
static int wlog_on, wlog_n;
static struct { uint32_t a, v, pc; } wlog[2][200000];
static int wlog_k;
static void logw(unsigned a, unsigned v)
{
	if (wlog_on && wlog_n < 200000 && a < 0xe00000) {
		wlog[wlog_k][wlog_n].a = a; wlog[wlog_k][wlog_n].v = v;
		wlog[wlog_k][wlog_n].pc = m68k_get_reg(NULL, M68K_REG_PPC); wlog_n++;
	}
}
void m68k_write_memory_8(unsigned int a, unsigned int v) { logw(a, v & 0xff); mem[a & (MEMSIZE - 1)] = v; }
void m68k_write_memory_16(unsigned int a, unsigned int v) { logw(a, v & 0xffff); a &= MEMSIZE - 1; mem[a] = v >> 8; mem[a + 1] = v; }
void m68k_write_memory_32(unsigned int a, unsigned int v) { m68k_write_memory_16(a, v >> 16); m68k_write_memory_16(a + 2, v); }
static void wlog_cmp(void)
{
	static int na;
	(void)na;
}
unsigned int m68k_read_disassembler_16(unsigned int a) { return m68k_read_memory_16(a); }
unsigned int m68k_read_disassembler_32(unsigned int a) { return m68k_read_memory_32(a); }

static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static uint32_t G(uint32_t doc) { return base + doc - 0x10100; }   /* adresse du jeu */
static void w16(uint32_t a, uint16_t v) { m68k_write_memory_16(a, v); }
static void w32(uint32_t a, uint32_t v) { m68k_write_memory_32(a, v); }

static uint64_t rng = 88172645463325252ull;
static uint32_t rnd(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (uint32_t)(rng >> 16); }
static int rint_(int lo, int hi) { return lo + (int)(rnd() % (uint32_t)(hi - lo + 1)); }

/* symboles du listing vasm : « nom   SS:DECALAGE » */
static long sym(const char *lst, const char *name, int *sec)
{
	FILE *f = fopen(lst, "r");
	char l[512], n[256];
	unsigned s, off;
	long r = -1;
	if (!f) { perror(lst); exit(2); }
	while (fgets(l, sizeof l, f))
		if (sscanf(l, "%255s %x:%x", n, &s, &off) == 3 && !strcmp(n, name)) { r = off; *sec = s; }
	fclose(f);
	if (r < 0) { fprintf(stderr, "symbole %s absent\n", name); exit(2); }
	return r;
}

/* charge un programme TOS à LOADADR, relogé */
static uint32_t tlen, dlen;
static void load_prg(const char *path)
{
	static uint8_t f[1 << 20];
	FILE *fp = fopen(path, "rb");
	size_t n;
	if (!fp) { perror(path); exit(2); }
	n = fread(f, 1, sizeof f, fp);
	fclose(fp);
	if (n < 28 || f[0] != 0x60 || f[1] != 0x1a) { fprintf(stderr, "%s : pas un programme TOS\n", path); exit(2); }
	tlen = rd32(f + 2); dlen = rd32(f + 6);
	uint32_t blen = rd32(f + 10), slen = rd32(f + 14);
	memcpy(mem + LOADADR, f + 28, tlen + dlen);
	memset(mem + LOADADR + tlen + dlen, 0, blen);
	const uint8_t *r = f + 28 + tlen + dlen + slen;
	uint32_t off = rd32(r);
	r += 4;
	if (off) {
		uint32_t a = LOADADR + off;
		w32(a, m68k_read_memory_32(a) + LOADADR);
		for (; *r; r++) {
			if (*r == 1) { a += 254; continue; }
			a += *r;
			w32(a, m68k_read_memory_32(a) + LOADADR);
		}
	}
}

typedef struct { uint32_t d[8], a[8], sr; } regs_t;
static const int DREG[8] = { M68K_REG_D0, M68K_REG_D1, M68K_REG_D2, M68K_REG_D3, M68K_REG_D4, M68K_REG_D5, M68K_REG_D6, M68K_REG_D7 };
static const int AREG[8] = { M68K_REG_A0, M68K_REG_A1, M68K_REG_A2, M68K_REG_A3, M68K_REG_A4, M68K_REG_A5, M68K_REG_A6, M68K_REG_A7 };

static long call(uint32_t pc, const regs_t *in, regs_t *out)
{
	long n = 0;
	for (int i = 0; i < 8; i++) m68k_set_reg(DREG[i], in->d[i]);
	for (int i = 0; i < 7; i++) m68k_set_reg(AREG[i], in->a[i]);
	m68k_set_reg(M68K_REG_SR, 0x2700 | (in->sr & 0x1f));
	m68k_set_reg(M68K_REG_A7, STACKTOP - 4);
	w32(STACKTOP - 4, SENTINEL);
	m68k_set_reg(M68K_REG_PC, pc);
	static FILE *tr; static int trn;
	const char *tre = getenv("BENCH_TRACE");
	if (tre && !tr) tr = fopen(tre, "w");
	while (m68k_get_reg(NULL, M68K_REG_PC) != SENTINEL) {
		if (tr && trn < 2) fprintf(tr, "%d %06x d0=%08x d1=%08x d2=%08x d3=%08x d4=%08x d5=%08x a4=%08x a5=%08x\n", trn,
			m68k_get_reg(NULL, M68K_REG_PC), m68k_get_reg(NULL, M68K_REG_D0), m68k_get_reg(NULL, M68K_REG_D1),
			m68k_get_reg(NULL, M68K_REG_D2), m68k_get_reg(NULL, M68K_REG_D3), m68k_get_reg(NULL, M68K_REG_D4),
			m68k_get_reg(NULL, M68K_REG_D5), m68k_get_reg(NULL, M68K_REG_A4), m68k_get_reg(NULL, M68K_REG_A5));
		m68k_execute(1);
		if (++n > 2000000) return -1;
	}
	if (tr) trn++;
	for (int i = 0; i < 8; i++) out->d[i] = m68k_get_reg(NULL, DREG[i]);
	for (int i = 0; i < 8; i++) out->a[i] = m68k_get_reg(NULL, AREG[i]);
	out->sr = m68k_get_reg(NULL, M68K_REG_SR);
	return n;
}

/* --- entrées de $5353C (tracé d'un bord) --- */
static uint32_t edge_buf0;
static void gen_edge(regs_t *r)
{
	for (int i = 0; i < 8; i++) { r->d[i] = rnd() << 16 ^ rnd(); r->a[i] = rnd() << 16 ^ rnd(); }
	r->sr = rnd();
	int i1 = rint_(0, 0x9f) * 2, i2 = rint_(0, 0x9f) * 2;
	r->d[1] = (r->d[1] & 0xffff0000) | i1;
	r->d[2] = (r->d[2] & 0xffff0000) | i2;
	int big = rint_(0, 99) < 12;
	int x1 = big ? rint_(-300, 600) : rint_(0, 255), x2 = big ? rint_(-300, 600) : rint_(0, 255);
	int y1 = big ? rint_(-200, 300) : rint_(0, 127), y2 = big ? rint_(-200, 300) : rint_(0, 127);
	switch (rint_(0, 9)) {          /* cas particuliers */
	case 0: y2 = y1; break;         /* horizontal */
	case 1: x2 = x1; break;         /* vertical */
	case 2: x2 = x1 + (y2 - y1); if (x2 < 0 || x2 > 255) x2 = x1; break;  /* 45° */
	case 3: x1 = rint_(0, 1) ? 0 : 255; x2 = 255 - x1; break;  /* très large */
	}
	if (i1 == i2) { x2 = x1; y2 = y1; }
	w16(G(0x6ec5c) + i1, x1); w16(G(0x6ec5c) + i2, x2);
	w16(G(0x6ed9c) + i1, y1); w16(G(0x6ed9c) + i2, y2);
	w16(G(0x54d04), rint_(0, 11) * 4);
	uint32_t lim = G(0x72c50);
	w32(G(0x54d00), rint_(0, 99) < 5 ? lim + rint_(-12, 4) * 2 : edge_buf0 + rint_(0, 200) * 2);
	m68k_write_memory_8(G(0x10961), rnd());
	w16(G(0x53536), rnd()); w16(G(0x53538), rnd());
}

/* toutes les pentes : dx 0-255, dy 0-127, deux sens en x, deux ordres des sommets */
static long all_idx;
static void gen_edge_all(regs_t *r)
{
	gen_edge(r);
	long k = all_idx++;
	int dx = k % 256, dy = (k / 256) % 128, dir = (k / 32768) % 2, ord = (k / 65536) % 2;
	int xa = dx ? (int)(rnd() % (256 - dx)) : (int)(rnd() % 256), ya = (int)(rnd() % (128 - dy));
	int x0 = dir ? xa + dx : xa, x1 = dir ? xa : xa + dx;
	int y0 = ya + dy, y1 = ya;
	int i1 = r->d[1] & 0xffff, i2 = r->d[2] & 0xffff;
	if (i1 == i2) { i2 = (i1 + 2) % 0x140; r->d[2] = (r->d[2] & 0xffff0000) | i2; }
	if (ord) { int t = x0; x0 = x1; x1 = t; t = y0; y0 = y1; y1 = t; }
	w16(G(0x6ec5c) + i1, x0); w16(G(0x6ec5c) + i2, x1);
	w16(G(0x6ed9c) + i1, y0); w16(G(0x6ed9c) + i2, y1);
	w32(G(0x54d00), edge_buf0 + rint_(0, 200) * 2);
}

/* --- entrées de $56762 (sprite masqué) : sprite, position, fond d'écran au hasard --- */
static void gen_sprite(regs_t *r)
{
	for (int i = 0; i < 8; i++) { r->d[i] = rnd() << 16 ^ rnd(); r->a[i] = rnd() << 16 ^ rnd(); }
	r->sr = rnd();
	int idx;
	uint32_t desc;
	int wd, ht;
	do {
		idx = rint_(0, 39);
		desc = G(0x5692c) + 4 + idx * 16;
		wd = m68k_read_memory_16(desc); ht = m68k_read_memory_16(desc + 2);
	} while (wd > 19 || ht > 199);
	r->d[0] = (r->d[0] & 0xffffff00) | idx;
	w16(desc + 4, (rnd() & 0xff00) | rint_(0, 19 - wd));       /* x (octet faible) */
	w16(desc + 6, (rnd() & 0xff00) | rint_(0, 199 - ht));      /* y */
	uint32_t scr = m68k_read_memory_32(G(0x56c74));
	for (int i = 0; i < 32000; i += 2) w16(scr + i, rint_(0, 3) ? rnd() : 0);
}

/* --- entrées de $53ACA (tracé, aussi atteint après découpage) --- */
static void gen_trace(regs_t *r)
{
	for (int i = 0; i < 8; i++) { r->d[i] = rnd() << 16 ^ rnd(); r->a[i] = rnd() << 16 ^ rnd(); }
	r->sr = rnd();
	int big = rint_(0, 99) < 3;
	int x0 = big ? rint_(-3000, 3000) : rint_(0, 255), x1 = big ? rint_(-3000, 3000) : rint_(0, 255);
	int y1 = rint_(0, 127), y0 = big ? y1 + rint_(0, 3000) : rint_(y1, 127);
	switch (rint_(0, 7)) { case 0: y0 = y1; break; case 1: x1 = x0; break; }
	r->d[4] = (r->d[4] & 0xffff0000) | (x0 & 0xffff);
	r->d[6] = (r->d[6] & 0xffff0000) | (x1 & 0xffff);
	r->d[5] = (r->d[5] & 0xffff0000) | (y0 & 0xffff);
	r->d[7] = (r->d[7] & 0xffff0000) | (y1 & 0xffff);
	uint32_t a2 = edge_buf0 + rint_(0, 200) * 2;
	r->a[2] = a2; r->a[0] = a2 + 8;
	w16(G(0x5353a), rnd());
	w16(G(0x53536), rint_(0, 9) < 7 ? 0xffff : rint_(0, 40));
	w16(G(0x53538), rnd());
}

/* rejeu : bench replay DOSSIER BASE ENTRÉE PATCH... (adresses du jeu, doc)
 * DOSSIER/NNN.bin : mémoire (0-$100000) relevée à l'entrée d'un appel réel, dans le
 * jeu modifié ; DOSSIER/regs.txt : « NNN d0..d7 a0..a7 sr » en hexadécimal.
 * Exécution A : octets d'origine (copie du jeu, game.bin) remis aux adresses PATCH ;
 * exécution B : telle quelle (les « jmp » vers les routines réécrites, chargées avec
 * le lanceur dans la même mémoire). */
static int replay(int argc, char **argv)
{
	const char *dir = argv[2];
	base = strtoul(argv[3], NULL, 0);
	uint32_t entry = strtoul(argv[4], NULL, 0);
	static uint8_t game[0x70000];
	char fn[512];
	snprintf(fn, sizeof fn, "%s/game.bin", dir);
	FILE *g = fopen(fn, "rb");
	if (!g) { perror(fn); return 2; }
	size_t gl = fread(game, 1, sizeof game, g);
	fclose(g);
	snprintf(fn, sizeof fn, "%s/regs.txt", dir);
	FILE *rf = fopen(fn, "r");
	if (!rf) { perror(fn); return 2; }
	m68k_init();
	m68k_set_cpu_type(M68K_CPU_TYPE_68030);
	m68k_pulse_reset();
	char line[1024];
	long n = 0, bad = 0, ia = 0, ib = 0;
	while (fgets(line, sizeof line, rf)) {
		regs_t in, a, b;
		int id;
		unsigned v[17];
		if (sscanf(line, "%d %x %x %x %x %x %x %x %x %x %x %x %x %x %x %x %x %x", &id,
		           &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8], &v[9], &v[10],
		           &v[11], &v[12], &v[13], &v[14], &v[15], &v[16]) != 18) continue;
		for (int i = 0; i < 8; i++) { in.d[i] = v[i]; in.a[i] = v[8 + i]; }
		in.sr = v[16];
		snprintf(fn, sizeof fn, "%s/%03d.bin", dir, id);
		FILE *f = fopen(fn, "rb");
		if (!f) continue;
		if (fread(pristine, 1, GAMEMEM, f) != GAMEMEM) { fclose(f); continue; }
		fclose(f);
		/* A : code d'origine aux adresses remplacées */
		memcpy(mem, pristine, GAMEMEM);
		for (int k = 5; k < argc; k++) {
			uint32_t d = strtoul(argv[k], NULL, 0), o = d - 0x10100;
			if (o + 6 <= gl) memcpy(mem + G(d), game + o, 6);
			uint32_t l = rd32(game + o + 2);	/* adresse du jeu après le mot d'instruction : relogée */
			if (l >= 0x10100 && l < 0x73370) w32(G(d) + 2, l + base - 0x10100);
		}
		int lg = getenv("BENCH_LOG") != NULL, nA;
		wlog_on = lg; wlog_k = 0; wlog_n = 0;
		long ca = call(G(entry), &in, &a);
		nA = wlog_n;
		memcpy(resA, mem, GAMEMEM);
		memcpy(mem, pristine, GAMEMEM);
		wlog_k = 1; wlog_n = 0;
		long cb = call(G(entry), &in, &b);
		wlog_on = 0;
		if (lg) {	/* écritures hors pile, dans l'ordre */
			int i = 0, j = 0;
			while (i < nA && j < wlog_n) {
				if (wlog[0][i].a >= 0xe00000 - 0x100000) { i++; continue; }
				if (wlog[1][j].a >= 0xe00000 - 0x100000) { j++; continue; }
				if (wlog[0][i].a != wlog[1][j].a || wlog[0][i].v != wlog[1][j].v) {
					printf("appel %d : écriture n° %d/%d diffère : A $%06x=%x (pc $%06x)  B $%06x=%x (pc $%06x)\n", id, i, j,
					       wlog[0][i].a, wlog[0][i].v, wlog[0][i].pc, wlog[1][j].a, wlog[1][j].v, wlog[1][j].pc);
					if (i > 0) printf("   précédente A pc $%06x, B pc $%06x\n", wlog[0][i-1].pc, wlog[1][j-1].pc);
					break;
				}
				i++; j++;
			}
		}
		ia += ca; ib += cb;
		/* les octets de code restaurés en A ne comptent pas */
		for (int k = 5; k < argc; k++) memcpy(resA + G(strtoul(argv[k], NULL, 0)), mem + G(strtoul(argv[k], NULL, 0)), 6);
		int diff = ca < 0 || cb < 0;
		for (int i = 0; i < 8; i++) diff |= a.d[i] != b.d[i];
		for (int i = 0; i < 7; i++) diff |= a.a[i] != b.a[i];
		diff |= (a.sr & 0x1f) != (b.sr & 0x1f);
		long md = -1;
		long ign = getenv("BENCH_IGNORE_BELOW") ? strtol(getenv("BENCH_IGNORE_BELOW"), NULL, 0) : 0;
		for (long i = ign; i < GAMEMEM; i++)	/* (au-dessous : variables du lanceur) */
			if (mem[i] != resA[i] && !(i >= (long)(in.a[7] - 0x400) && i < (long)in.a[7])) { md = i; break; }
		diff |= md >= 0;
		if (diff && bad < 5) {
			printf("DIFFÉRENCE appel %d (instructions %ld / %ld)%s\n", id, ca, cb, md >= 0 ? " mémoire" : "");
			if (md >= 0) printf("  mémoire $%06lx : %02x / %02x\n", md, resA[md], mem[md]);
			for (int i = 0; i < 8; i++) printf("  d%d %08x / %08x   a%d %08x / %08x\n", i, a.d[i], b.d[i], i, a.a[i], b.a[i]);
		}
		bad += diff; n++;
	}
	printf("rejeu : %ld appels réels, %ld différences ; instructions %.0f -> %.0f par appel\n", n, bad,
	       n ? (double)ia / n : 0, n ? (double)ib / n : 0);
	return bad != 0;
}

int main(int argc, char **argv)
{
	if (argc > 1 && !strcmp(argv[1], "replay")) return replay(argc, argv);
	if (argc < 6) { fprintf(stderr, "usage : bench RAM.bin BASE SCRF030.PRG LISTING ROUTINE [N [GRAINE]]\n"); return 2; }
	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror(argv[1]); return 2; }
	if (fread(mem, 1, GAMEMEM, f) != GAMEMEM) { fprintf(stderr, "copie trop courte\n"); return 2; }
	fclose(f);
	base = strtoul(argv[2], NULL, 0);
	load_prg(argv[3]);
	long n = argc > 6 ? atol(argv[6]) : 100000;
	if (argc > 7) rng ^= strtoull(argv[7], NULL, 0) * 0x9e3779b97f4a7c15ull;

	/* adresses du jeu dans les routines réécrites : comme turbo_install */
	int sec;
	long gs = sym(argv[4], "grel_start", &sec), ge = sym(argv[4], "grel_end", &sec);
	uint32_t dbase = LOADADR + (sec ? tlen : 0);
	for (long o = gs; o < ge; o += 4) {
		uint32_t a = m68k_read_memory_32(dbase + o);
		w32(a, m68k_read_memory_32(a) + base - 0x10100);
	}

	uint32_t orig, repl;
	void (*gen)(regs_t *);
	if (!strcmp(argv[5], "edge")) {
		orig = G(0x5353c);
		repl = LOADADR + sym(argv[4], "t_edge", &sec);
		gen = gen_edge;
		edge_buf0 = m68k_read_memory_32(G(0x54d00));
	} else if (!strcmp(argv[5], "sprite")) {
		orig = G(0x56762);
		repl = LOADADR + sym(argv[4], "t_sprite", &sec);
		gen = gen_sprite;
	} else if (!strcmp(argv[5], "trace")) {
		orig = G(0x53aca);
		repl = LOADADR + sym(argv[4], "t_trace", &sec);
		gen = gen_trace;
		edge_buf0 = m68k_read_memory_32(G(0x54d00));
	} else if (!strcmp(argv[5], "edge_all")) {
		orig = G(0x5353c);
		repl = LOADADR + sym(argv[4], "t_edge", &sec);
		gen = gen_edge_all;
		edge_buf0 = m68k_read_memory_32(G(0x54d00));
		n = 256 * 128 * 4;
	} else { fprintf(stderr, "routine inconnue\n"); return 2; }

	if (getenv("REPL")) repl = LOADADR + sym(argv[4], getenv("REPL"), &sec);   /* autre remplaçante */
	m68k_init();
	m68k_set_cpu_type(M68K_CPU_TYPE_68030);
	m68k_pulse_reset();
	memcpy(pristine, mem, GAMEMEM);
	long bad = 0, ccr = 0, slowA = 0, slowB = 0;
	for (long t = 0; t < n; t++) {
		regs_t in, a, b;
		memcpy(mem, pristine, GAMEMEM);
		gen(&in);
		static uint8_t *st = NULL;
		if (!st) st = malloc(GAMEMEM);
		memcpy(st, mem, GAMEMEM);
		long ca = call(orig, &in, &a);
		memcpy(resA, mem, GAMEMEM);
		memcpy(mem, st, GAMEMEM);
		long cb = call(repl, &in, &b);
		slowA += ca; slowB += cb;
		int diff = ca < 0 || cb < 0;
		for (int i = 0; i < 8; i++) diff |= a.d[i] != b.d[i];
		for (int i = 0; i < 7; i++) diff |= a.a[i] != b.a[i];
		long md = -1;
		for (long i = 0; i < GAMEMEM; i++) if (mem[i] != resA[i]) { md = i; break; }
		diff |= md >= 0;
		if ((a.sr & 0x1f) != (b.sr & 0x1f)) {
			if (ccr < 5) printf("CCR %02x / %02x au test %ld (instructions %ld / %ld)\n", a.sr & 0x1f, b.sr & 0x1f, t, ca, cb);
			ccr++;
		}
		if (diff) {
			if (bad < 10) {
				printf("DIFFÉRENCE au test %ld (instructions %ld / %ld)%s\n", t, ca, cb, md >= 0 ? " mémoire" : "");
				if (md >= 0) printf("  mémoire $%06lx : %02x / %02x\n", md, resA[md], mem[md]);
				for (int i = 0; i < 8; i++) printf("  d%d %08x -> %08x / %08x\n", i, in.d[i], a.d[i], b.d[i]);
				for (int i = 0; i < 7; i++) printf("  a%d %08x -> %08x / %08x\n", i, in.a[i], a.a[i], b.a[i]);
			}
			bad++;
		}
	}
	printf("%s : %ld essais, %ld différences ; CCR différent %ld fois ; instructions %.1f -> %.1f par appel\n",
	       argv[5], n, bad, ccr, (double)slowA / n, (double)slowB / n);
	return bad != 0;
}

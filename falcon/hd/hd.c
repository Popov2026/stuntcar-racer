/* hd.c - mode HD (touche F2) et mode texturé (F3) de SCRF030 sur Falcon à 68060.
 *
 * La logique du jeu d'origine tourne sans changement ; seul son décor 3D n'est plus dessiné
 * (remplissages et tracé de pixel neutralisés, fond de la fenêtre 3D en couleur 1, que le
 * cockpit n'emploie jamais). Ce module redessine la scène en 640x400, 16 couleurs (la palette
 * du jeu), à partir de l'état du jeu lu en mémoire : caméra ($10AC2), circuit ($1112D, géométrie
 * décodée depuis le programme du jeu, port de native/src/track.cpp), adversaire ($10907,
 * $108F6, $109D6). Le cockpit du jeu (tout sauf la couleur 1 dans la fenêtre) est incrusté,
 * agrandi deux fois, puis l'image est convertie en 4 plans de bits pour le VIDEL.
 *
 * Compilé sans bibliothèque (m68k-elf-gcc -m68060 -mpcrel), assemblé en binaire brut et
 * inclus dans SCRF030.PRG ; table d'entrée en tête (hd_entry.s). Aussi compilable sur PC pour
 * les essais (falcon/hd/hdtest.c).
 */
#include "hd.h"

/* rendu en octets (1 par pixel) de la seule fenêtre 3D : 256x128 pixels du jeu en (32,16),
 * soit 512x256 en (64,32) de l'image HD ; le reste de l'image est le cockpit du jeu */
#define W 512
#define H 256
#define WX 64
#define WY 32

/* ------------------------------------------------------------------ mémoire du jeu */
/* G : adresse de base du jeu moins $10100 (G + adresse documentée = octet du jeu) */
static const u8 *G;
static u8 b8(u32 a) { return G[a]; }
static u32 le16(u32 a) { return G[a] | (G[a + 1] << 8); }
static u32 be16(u32 a) { return (G[a] << 8) | G[a + 1]; }
static s32 be32(u32 a) { return (s32)(((u32)G[a] << 24) | ((u32)G[a + 1] << 16) | ((u32)G[a + 2] << 8) | G[a + 3]); }

/* ------------------------------------------------------------------ mathématiques */
#define PI 3.14159265358979f
static float fabsf_(float x) { return x < 0 ? -x : x; }
static float sqrtf_(float x) { return __builtin_sqrtf(x); }
/* sinus sur [-pi, pi] (polynôme, erreur < 1e-6) */
static float sinf_(float x) {
	while (x > PI) x -= 2 * PI;
	while (x < -PI) x += 2 * PI;
	float s = 1;
	if (x < 0) { x = -x; s = -1; }
	if (x > PI / 2) x = PI - x;
	float x2 = x * x;
	return s * x * (1 - x2 / 6 * (1 - x2 / 20 * (1 - x2 / 42 * (1 - x2 / 72 * (1 - x2 / 110)))));
}
static float cosf_(float x) { return sinf_(x + PI / 2); }

/* ------------------------------------------------------------------ circuits (port de track.cpp) */
#define BLOB 0x13670
#define TRACK_TABLE 0x13790
#define SHAPE_TABLE 0x13670
#define PROFILE_TABLE 0x13690
#define SPECIAL_BBA 0x48802
#define SPECIAL_C1E 0x48804
#define CELL 0x800

static u32 p6502(u32 a) { return BLOB + (a - 0xb100); }
static s32 sx16(u32 v) { return (s16)(u16)v; }
static u32 profile(u32 ptr, int neg, int i) {
	u32 a = p6502(ptr);
	if (neg) return ((b8(a + 2 * i) & 0x7f) << 8) | b8(a + 2 * i + 1);
	u32 x = b8(a + i);
	return ((x & 0xf) << 8) | ((x << 1) & 0xe0);
}
static int profileFlag(u32 ptr, int neg, int i) { return b8(p6502(ptr) + (neg ? 2 * i : i)) & 0x80; }



static int decode_track(struct hdws *ws, int track) {
	struct hdpiece_ *pieces = ws->pieces;
	int np = 0;
	u32 ptr = p6502(le16(TRACK_TABLE + 2 * track)), pos = 0;
	int hdr[4], k;
	for (k = 0; k < 4; k++) hdr[k] = b8(ptr + pos++);
	u32 lo = b8(ptr + pos++), hi = b8(ptr + pos++), hl = (hi << 8) | lo, hr = hl;
	int c6 = 0, repeat = 0, prevType = 0, prevCoord = 0;
	if (hdr[0] > HD_MAXPIECES) return -1;
	while (np < hdr[0]) {
		int t, ce6, dirb, c, bba, v;
		if (repeat) {
			repeat--; t = prevType; ce6 = dirb = t;
			if (t & 0x10) dirb ^= 0xc0;
			int step = (dirb & 0x40) ? 1 : 0x10;
			c = ((dirb & 0x80) ? prevCoord - step : prevCoord + step) & 0xff;
		} else {
			t = b8(ptr + pos++);
			if ((t & 0xf) == 0xf) { repeat = t >> 4; continue; }
			ce6 = dirb = prevType = t; c = b8(ptr + pos++);
		}
		prevCoord = c;
		int b905 = (c6 & 2) ? 0x80 : 0;
		if ((dirb & 0xf) >= 12) {
			ce6 &= 0xf0; bba = b8(SPECIAL_BBA + (dirb & 0xf)); v = b8(SPECIAL_C1E + (dirb & 0xf));
		} else {
			bba = b8(ptr + pos++); v = (dirb & 0x20) ? bba : b8(ptr + pos++);
		}
		int c1e = (v & 0x7f) | b905;
		u32 pL = le16(PROFILE_TABLE + ((bba << 1) & 0xff)), pR = le16(PROFILE_TABLE + ((c1e << 1) & 0xff));
		int neg = bba & 0x80;
		c6 = (c1e & 0x80) ? 2 : 0;
		u32 shape = p6502(le16(SHAPE_TABLE + 2 * (ce6 & 0xf)));
		int nsec = b8(shape + b8(shape)), segs = ((nsec >> 1) - 1) & 0xff;
		u32 startL = (hl - profile(pL, neg, 0)) & 0xffff; hl = (startL + profile(pL, neg, segs)) & 0xffff;
		u32 startR = (hr - profile(pR, neg, 0)) & 0xffff; hr = (startR + profile(pR, neg, segs)) & 0xffff;
		struct hdpiece_ *p = &pieces[np++];
		p->x = c & 0xf; p->z = c >> 4; p->type = ce6; p->hL = startL; p->hR = startR; p->profL = pL; p->profR = pR; p->neg = neg;
		c6 = (c6 + nsec - 2) & 2;
	}

	struct hdsec *all = ws->tmp;
	int nall = 0, pi;
	for (pi = 0; pi < np; pi++) {
		const struct hdpiece_ *p = &pieces[pi];
		int typ = p->type;
		u32 a = p6502(le16(SHAPE_TABLE + 2 * (typ & 0xf))), o = b8(a), n = b8(a + o), base = a + o + 7, i;
		int px[64], pz[64], ns = 0;
		struct { int lx, lz, rx, rz; u32 hl, hr; int fl; } secs[32], rev[32];
		if (n > 64) return -2;
		for (i = 0; i < n; i++) { px[i] = sx16(le16(base + 4 * i)); pz[i] = sx16(le16(base + 4 * i + 2)); }
		for (i = 0; i + 1 < n && ns < 32; i += 2) {
			int s = (int)(i / 2);
			secs[ns].lx = px[i]; secs[ns].lz = pz[i]; secs[ns].rx = px[i + 1]; secs[ns].rz = pz[i + 1];
			secs[ns].hl = (p->hL + profile(p->profL, p->neg, s)) & 0xffff;
			secs[ns].hr = (p->hR + profile(p->profR, p->neg, s)) & 0xffff;
			secs[ns].fl = (profileFlag(p->profL, p->neg, s) ? 1 : 0) | (profileFlag(p->profR, p->neg, s) ? 2 : 0);
			ns++;
		}
		if (typ & 0x10) {	/* parcours inverse : sections à l'envers, gauche/droite permutés */
			int kk;
			for (kk = 0; kk < ns; kk++) {
				int s = ns - 1 - kk;
				rev[kk].lx = secs[s].rx; rev[kk].lz = secs[s].rz; rev[kk].rx = secs[s].lx; rev[kk].rz = secs[s].lz;
				rev[kk].hl = secs[kk].hl; rev[kk].hr = secs[kk].hr; rev[kk].fl = secs[kk].fl;
			}
			for (kk = 0; kk < ns; kk++) secs[kk] = rev[kk];
		}
		int rot = (typ >> 6) & 3, kk;
		for (kk = 0; kk < ns; kk++) {
			if (pi > 0 && kk == 0) continue;	/* section partagée avec la pièce précédente */
			int q, xs[2] = {secs[kk].lx, secs[kk].rx}, zs[2] = {secs[kk].lz, secs[kk].rz}, X[2], Z[2];
			for (q = 0; q < 2; q++) {
				int x = xs[q], z = zs[q];
				switch (rot) {
				case 1: X[q] = z; Z[q] = CELL - x; break;
				case 2: X[q] = CELL - x; Z[q] = CELL - z; break;
				case 3: X[q] = CELL - z; Z[q] = x; break;
				default: X[q] = x; Z[q] = z;
				}
			}
			if (nall >= HD_MAXSECS) return -3;
			struct hdsec *d = &all[nall++];
			d->lx = (float)(X[0] + p->x * CELL); d->ly = (float)secs[kk].hl; d->lz = (float)(Z[0] + p->z * CELL);
			d->rx = (float)(X[1] + p->x * CELL); d->ry = (float)secs[kk].hr; d->rz = (float)(Z[1] + p->z * CELL);
			d->flag = secs[kk].fl; d->piece = pi;
		}
	}
	if (nall > 2 && fabsf_(all[0].lx - all[nall - 1].lx) + fabsf_(all[0].lz - all[nall - 1].lz) < 64) nall--;
	int first = 0, j;
	while (first < nall && all[first].piece != hdr[2]) first++;
	if (first >= nall) first = 0;
	for (j = 0; j < nall; j++) ws->secs[j] = all[(first + j) % nall];
	ws->nsec = nall;
	ws->npieces = np;
	return 0;
}

/* ------------------------------------------------------------------ caméra et projection */
struct vec { float x, y, z; };
static struct { float px, py, pz, cyw, syw, cp, sp, cr, sr, f, fy, cx, cy, nearz; } cam;

static struct vec tocam(float x, float y, float z) {
	struct vec r;
	x -= cam.px; y -= cam.py; z -= cam.pz;
	float x1 = x * cam.cyw - z * cam.syw, z1 = x * cam.syw + z * cam.cyw;
	float y2 = y * cam.cp - z1 * cam.sp, z2 = y * cam.sp + z1 * cam.cp;
	r.x = x1 * cam.cr - y2 * cam.sr; r.y = y2 * cam.cr + x1 * cam.sr; r.z = z2;
	return r;
}

/* ------------------------------------------------------------------ liste de polygones (peintre) */
#define NBUCKET 1024
static struct hdws *ws;

/* polygone en coordonnées caméra -> découpé au plan proche, projeté, découpé aux bords d'une
 * zone un peu plus grande que l'écran (en 2D : 1/z, u/z et v/z y sont linéaires), rangé par
 * profondeur (depth > 1e8 : fond, dessiné d'abord dans l'ordre d'ajout) */
static void addpoly(const struct vec *in, const float *tu, const float *tv, int n, int color, float depth, int tex) {
	struct vec out[12];
	float ou[12], ov[12];
	int m = 0, i, e;
	float zn = cam.nearz;
	int any = 0;
	for (i = 0; i < n; i++) any |= in[i].z >= zn;
	if (!any || ws->npoly >= HD_MAXPOLYS) return;
	for (i = 0; i < n && m < 11; i++) {
		const struct vec *a = &in[i], *b = &in[(i + 1) % n];
		int ain = a->z >= zn, bin = b->z >= zn;
		int j = (i + 1) % n;
		if (ain) { ou[m] = tu[i]; ov[m] = tv[i]; out[m++] = *a; }
		if (ain != bin) {
			float t = (zn - a->z) / (b->z - a->z);
			ou[m] = tu[i] + (tu[j] - tu[i]) * t; ov[m] = tv[i] + (tv[j] - tv[i]) * t;
			out[m].x = a->x + (b->x - a->x) * t; out[m].y = a->y + (b->y - a->y) * t; out[m].z = zn; m++;
		}
	}
	if (m < 3) return;
	/* sommets projetés : X, Y, 1/z, u/z, v/z (u, v : coordonnées de texture, dans le monde) */
	float P[5][24], Q[5][24];
	for (i = 0; i < m; i++) {
		float iz = 1.0f / out[i].z;
		P[0][i] = cam.cx + cam.f * out[i].x * iz; P[1][i] = cam.cy - cam.fy * out[i].y * iz;
		P[2][i] = iz; P[3][i] = ou[i] * iz; P[4][i] = ov[i] * iz;
	}
	const float lim[4] = {-W, 2 * W, -H, 2 * H};
	int k = m, inside = 1;
	for (i = 0; i < m; i++)
		if (P[0][i] < lim[0] || P[0][i] > lim[1] || P[1][i] < lim[2] || P[1][i] > lim[3]) { inside = 0; break; }
	for (e = inside ? 4 : 0; e < 4 && k >= 3; e++) {
		int q = 0, c = e >> 1, hi = e & 1;
		for (i = 0; i < k && q < 22; i++) {
			int j = i + 1 == k ? 0 : i + 1, r;
			float va = P[c][i], vb = P[c][j];
			int ai = hi ? va <= lim[e] : va >= lim[e], bi = hi ? vb <= lim[e] : vb >= lim[e];
			if (ai) { for (r = 0; r < 5; r++) Q[r][q] = P[r][i]; q++; }
			if (ai != bi) {
				float t = (lim[e] - va) / (vb - va);
				for (r = 0; r < 5; r++) Q[r][q] = P[r][i] + (P[r][j] - P[r][i]) * t;
				Q[c][q] = lim[e]; q++;
			}
		}
		k = q;
		for (i = 0; i < k; i++) { int r; for (r = 0; r < 5; r++) P[r][i] = Q[r][i]; }
	}
	if (k < 3) return;
	if (k > HD_MAXV) k = HD_MAXV;
	struct hdpoly *p = &ws->polys[ws->npoly];
	float xmin = 1e30f, xmax = -1e30f, ymin = 1e30f, ymax = -1e30f;
	for (i = 0; i < k; i++) {
		p->x[i] = P[0][i]; p->y[i] = P[1][i]; p->w[i] = P[2][i]; p->u[i] = P[3][i]; p->v[i] = P[4][i];
		if (P[0][i] < xmin) xmin = P[0][i]; if (P[0][i] > xmax) xmax = P[0][i];
		if (P[1][i] < ymin) ymin = P[1][i]; if (P[1][i] > ymax) ymax = P[1][i];
	}
	if (xmax < 0 || xmin >= W || ymax < 0 || ymin >= H) return;
	p->n = k; p->color = color; p->tex = tex; p->next = -1;
	int idx = ws->npoly++;
	if (depth > 1e8f) { if (ws->nbg < HD_MAXBG) ws->bg[ws->nbg++] = (s16)idx; return; }
	if (depth < 0) {
		float z = 0;
		for (i = 0; i < n; i++) z += in[i].z;
		depth = z / n;
	}
	int bk = (int)(depth * (1.0f / 64));
	if (bk < 0) bk = 0;
	if (bk >= NBUCKET) bk = NBUCKET - 1;
	/* file par case : dessinée dans l'ordre d'ajout (route, puis ses lignes) */
	if (ws->bucket[bk] < 0) ws->bucket[bk] = (s16)idx;
	else ws->polys[ws->btail[bk]].next = (s16)idx;
	ws->btail[bk] = (s16)idx;
}

/* texture : sols et route en (x, z) du monde, flancs en (x + z, y) */
static void addworld(const struct vec *w, int n, int color, float depth, int tex) {
	struct vec c[12];
	float tu[12], tv[12];
	int i;
	for (i = 0; i < n; i++) {
		c[i] = tocam(w[i].x, w[i].y, w[i].z);
		if (tex == 3) { tu[i] = w[i].x + w[i].z; tv[i] = w[i].y * 4; }
		else { tu[i] = w[i].x; tv[i] = w[i].z; }
	}
	addpoly(c, tu, tv, n, color, depth, tex);
}

/* ------------------------------------------------------------------ remplissage */
static s16 xl[H], xr[H];

static void edge(float x0, float y0, float x1, float y1) {
	if (y0 > y1) { float t = x0; x0 = x1; x1 = t; t = y0; y0 = y1; y1 = t; }
	int ya = (int)(y0 + 0.999f), yb = (int)(y1 + 0.999f);	/* lignes y telles que y0 <= y < y1 */
	if (y0 < 0) ya = 0;
	if (yb > H) yb = H;
	if (ya >= yb) return;
	float dx = (x1 - x0) / (y1 - y0), x = x0 + (ya - y0) * dx;
	int y;
	for (y = ya; y < yb; y++, x += dx) {
		int xi = (int)(x + 1e4f + 0.5f) - 10000;
		if (xi < xl[y]) xl[y] = (s16)xi;
		if (xi > xr[y]) xr[y] = (s16)xi;
	}
}

/* motifs des textures (F3) : 16x16, 1 bit = seconde couleur */
static const u16 TEX_ROAD[16] = {0x0821, 0x4004, 0x0100, 0x2088, 0x0002, 0x8420, 0x0010, 0x1102,
				 0x0040, 0x4208, 0x0001, 0x2080, 0x0410, 0x0002, 0x9040, 0x0004};
static const u16 TEX_GRASS[16] = {0x1248, 0x8421, 0x2412, 0x4884, 0x1248, 0x0421, 0x2410, 0x4884,
				  0x1240, 0x8021, 0x2412, 0x4884, 0x0248, 0x8421, 0x2412, 0x4804};
static const u16 TEX_WALL[16] = {0xffff, 0x8080, 0x8080, 0x8080, 0xffff, 0x0808, 0x0808, 0x0808,
				 0xffff, 0x8080, 0x8080, 0x8080, 0xffff, 0x0808, 0x0808, 0x0808};

static void fill(u8 *scr, const struct hdpoly *p, int textured) {
	int i, ymin = H, ymax = -1;
	for (i = 0; i < p->n; i++) {
		int y0 = (int)(p->y[i]), y1 = y0 + 1;
		if (y0 < ymin) ymin = y0;
		if (y1 > ymax) ymax = y1;
	}
	if (ymin < 0) ymin = 0;
	if (ymax > H) ymax = H;
	if (ymin >= ymax) return;
	int y;
	for (y = ymin; y < ymax; y++) { xl[y] = 32767; xr[y] = -32768; }
	for (i = 0; i < p->n; i++) {
		int j = i + 1 == p->n ? 0 : i + 1;
		edge(p->x[i], p->y[i], p->x[j], p->y[j]);
	}
	int c = p->color & 15, c2 = (p->color >> 4) & 15;
	const u16 *pat = 0;
	if (textured && p->tex) pat = p->tex == 1 ? TEX_ROAD : p->tex == 2 ? TEX_GRASS : TEX_WALL;
	/* texture : motif fixé à la surface (plan du polygone), u = x caméra, v = z caméra, interpolés
	 * en perspective par 1/z ; une division par groupe de 16 pixels */
	float A = 0, B = 0, C = 0, Au = 0, Bu = 0, Cu = 0, Av = 0, Bv = 0, Cv = 0;
	if (pat) {
		/* plan de 1/z, u/z, v/z en fonction de (X, Y) écran, par les 3 premiers sommets */
		float x0 = p->x[0], y0 = p->y[0], x1 = p->x[1], y1 = p->y[1], x2 = p->x[2], y2 = p->y[2];
		float d = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
		if (fabsf_(d) < 1e-3f) pat = 0;
		else {
			float id = 1.0f / d;
#define PLANE(q0, q1, q2, a, b, cc) do { float e1 = (q1) - (q0), e2 = (q2) - (q0); \
	a = (e1 * (y2 - y0) - e2 * (y1 - y0)) * id; b = (e2 * (x1 - x0) - e1 * (x2 - x0)) * id; cc = (q0) - a * x0 - b * y0; } while (0)
			PLANE(p->w[0], p->w[1], p->w[2], A, B, C);
			PLANE(p->u[0], p->u[1], p->u[2], Au, Bu, Cu);
			PLANE(p->v[0], p->v[1], p->v[2], Av, Bv, Cv);
		}
	}
	u32 cl = c * 0x01010101u;
	for (y = ymin; y < ymax; y++) {
		int a = xl[y], b = xr[y];
		if (a < 0) a = 0;
		if (b > W) b = W;
		if (a >= b) continue;
		u8 *d = scr + y * W + a;
		int n = b - a;
		if (!pat) {
			while (n && ((unsigned long)d & 3)) { *d++ = (u8)c; n--; }
			while (n >= 4) { *(u32 *)d = cl; d += 4; n -= 4; }
			while (n--) *d++ = (u8)c;
			continue;
		}
		float fy = (float)y + 0.5f;
		int x = a;
		while (x < b) {
			int xe = x + 16 > b ? b : x + 16;
			float fx0 = (float)x + 0.5f, fx1 = (float)xe + 0.5f;
			float w0 = A * fx0 + B * fy + C, w1 = A * fx1 + B * fy + C;
			if (w0 <= 1e-9f) w0 = 1e-9f;
			if (w1 <= 1e-9f) w1 = 1e-9f;
			float u0 = (Au * fx0 + Bu * fy + Cu) / w0, v0 = (Av * fx0 + Bv * fy + Cv) / w0;
			float u1 = (Au * fx1 + Bu * fy + Cu) / w1, v1 = (Av * fx1 + Bv * fy + Cv) / w1;
			/* 1 texel = 16 unités ; coordonnées 16.16 */
			s32 U = (s32)(u0 * 4096), V = (s32)(v0 * 4096);
			s32 dU = (s32)((u1 - u0) * 4096) / (xe - x), dV = (s32)((v1 - v0) * 4096) / (xe - x);
			for (; x < xe; x++) {
				int tu = (U >> 16) & 15, tv = (V >> 16) & 15;
				*d++ = (u8)((pat[tv] >> tu) & 1 ? c2 : c);
				U += dU; V += dV;
			}
		}
	}
}

/* ------------------------------------------------------------------ scène */
#define HSCALE 0.261f
#define GROUND_RAW 512.0f

/* couleurs (index de la palette du jeu) */
enum { C_SKY = 7, C_GROUND = 13, C_HILL = 5, C_ROAD = 1, C_ROAD2 = 2, C_LINE = 3, C_LINE2 = 9, C_WALL = 10, C_WALL2 = 15 };

static float hills[2][65];
static void init_hills(void) {
	u32 r = 12345;
	int l, i;
	for (l = 0; l < 2; l++) {
		float v = 0.03f;
		for (i = 0; i <= 64; i++) {
			r = r * 1103515245u + 12345u;
			float rnd = ((r >> 8) & 0xffff) / 65535.0f;
			v += (rnd - 0.5f) * (l ? 0.02f : 0.035f);
			if (v < 0.004f) v = 0.004f;
			if (v > (l ? 0.045f : 0.07f)) v = l ? 0.045f : 0.07f;
			hills[l][i] = v;
		}
		hills[l][64] = hills[l][0];
	}
}

static void lerp3(struct vec *o, const struct vec *a, const struct vec *b, float t) {
	o->x = a->x + (b->x - a->x) * t; o->y = a->y + (b->y - a->y) * t; o->z = a->z + (b->z - a->z) * t;
}

static void add_car(void) {
	const struct hdsec *S = ws->secs;
	int n = ws->nsec, piece = b8(0x10907), sec = b8(0x108f6), first = -1, i;
	float fr = b8(0x108f7) / 256.0f, u = be16(0x109d6) / 256.0f;
	if (u > 1) u = 1;
	for (i = 0; i < n; i++) if (S[i].piece == piece) { first = i; break; }
	if (first < 0) return;
	int g0 = ((first - 1 + sec) % n + n) % n, g1 = (g0 + 1) % n;
	const struct hdsec *A = &S[g0], *B = &S[g1];
#define LR(a, b) ((a) + ((b) - (a)) * fr)
	float lx = LR(A->lx, B->lx), lz = LR(A->lz, B->lz), rx = LR(A->rx, B->rx), rz = LR(A->rz, B->rz), hl = LR(A->ly, B->ly), hr = LR(A->ry, B->ry);
	float ox = lx + (rx - lx) * u, oz = lz + (rz - lz) * u, base = (hl + (hr - hl) * u) * HSCALE;
	float fx = (B->lx + B->rx - A->lx - A->rx) / 2, fz = (B->lz + B->rz - A->lz - A->rz) / 2, fy = (B->ly + B->ry - A->ly - A->ry) / 2 * HSCALE;
	float fl = sqrtf_(fx * fx + fy * fy + fz * fz);
	if (fl < 1e-6f) { fx = 0; fy = 0; fz = 1; fl = 1; }
	if (sqrtf_(fx * fx + fz * fz) < 1) { fy = 0; fl = sqrtf_(fx * fx + fz * fz); if (fl < 1e-6f) fl = 1; }
	struct vec F = {fx / fl, fy / fl, fz / fl};
	float ry = (hr - hl) * HSCALE, rl = sqrtf_((rx - lx) * (rx - lx) + ry * ry + (rz - lz) * (rz - lz));
	if (rl < 1e-6f) return;
	struct vec R = {(rx - lx) / rl, ry / rl, (rz - lz) / rl};
	struct vec U = {F.y * R.z - F.z * R.y, F.z * R.x - F.x * R.z, F.x * R.y - F.y * R.x};
	if (U.y < 0) { U.x = -U.x; U.y = -U.y; U.z = -U.z; }
	const float K = 0.55f;
	/* distance de la voiture : une seule profondeur pour toutes ses faces (rangée comme un bloc),
	 * faces arrière éliminées : la boîte est convexe */
	struct vec cc = tocam(ox, base, oz);
	static const float q0u[4] = {0, 0, 0, 0};
	if (cc.z < cam.nearz) return;
	static const struct { s16 x0, x1, y0, y1, z0, z1; u8 top, side, end; } boxes[] = {
		{-52, 52, 14, 34, -130, 120, 11, 10, 9}, {-34, 34, 14, 30, 120, 150, 11, 10, 9},
		{-46, 46, 34, 58, -120, -10, 10, 9, 10}, {-40, 40, 58, 64, -70, -20, 12, 10, 12},
		{-60, 60, 50, 56, -138, -118, 11, 9, 9}, {-95, -61, 0, 60, -120, -60, 0, 0, 0},
		{61, 95, 0, 60, -120, -60, 0, 0, 0}, {-83, -57, 0, 48, 71, 119, 0, 0, 0}, {57, 83, 0, 48, 71, 119, 0, 0, 0}};
	int bxi;
	for (bxi = 0; bxi < (int)(sizeof boxes / sizeof boxes[0]); bxi++) {
		struct vec c[8];
		int k;
		for (k = 0; k < 8; k++) {
			float x = (k & 1 ? boxes[bxi].x1 : boxes[bxi].x0) * K, y = (k & 2 ? boxes[bxi].y1 : boxes[bxi].y0) * K,
			      z = (k & 4 ? boxes[bxi].z1 : boxes[bxi].z0) * K;
			c[k] = tocam(ox + R.x * x + U.x * y + F.x * z, base + R.y * x + U.y * y + F.y * z, oz + R.z * x + U.z * y + F.z * z);
		}
		/* faces : sommets (bits x, y, z) */
		static const u8 face[6][4] = {{2, 6, 7, 3}, {0, 1, 5, 4}, {0, 4, 6, 2}, {1, 3, 7, 5}, {4, 5, 7, 6}, {0, 2, 3, 1}};
		int col[6] = {boxes[bxi].top, 0, boxes[bxi].side, boxes[bxi].side, boxes[bxi].end, boxes[bxi].end};
		int f;
		for (f = 0; f < 6; f++) {
			struct vec q[4];
			for (k = 0; k < 4; k++) q[k] = c[face[f][k]];
			/* face vue de dos : normale vers l'arrière */
			float ax = q[1].x - q[0].x, ay = q[1].y - q[0].y, az = q[1].z - q[0].z;
			float bx = q[2].x - q[0].x, by = q[2].y - q[0].y, bz = q[2].z - q[0].z;
			float nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
			float dot = nx * q[0].x + ny * q[0].y + nz * q[0].z;
			if (dot >= 0) continue;
			addpoly(q, q0u, q0u, 4, col[f], cc.z - 1, 0);
		}
	}
}

/* état de la caméra (18 octets en $10AC2) -> caméra du rendu */
static void setup_camera(void) {
	float x = be32(0x10ac2) / 65536.0f * 16, y = be32(0x10ac6) / 65536.0f * 16, z = be32(0x10aca) / 65536.0f * 16;
	float pitch = (s16)be16(0x10ace) * (2 * PI / 65536), yaw = be16(0x10ad0) * (2 * PI / 65536), roll = (s16)be16(0x10ad2) * (2 * PI / 65536);
	const float eyeSide = -27, eyeUp = 40, eyeFwd = -27, pitchOffset = -0.0056f;
	float sy = sinf_(yaw), cyw = cosf_(yaw);
	cam.px = x + sy * eyeFwd + cyw * eyeSide;
	cam.py = y * HSCALE / 0.5f + eyeUp;
	cam.pz = z + cyw * eyeFwd - sy * eyeSide;
	cam.cyw = cyw; cam.syw = sy;
	cam.cp = cosf_(pitch + pitchOffset); cam.sp = sinf_(pitch + pitchOffset);
	cam.cr = cosf_(roll); cam.sr = sinf_(roll);
	/* projection du jeu (320x200 : focale 259, centre 153,2 / 82,3, focale verticale x 0,895), x 2 */
	cam.f = 259 * 2; cam.fy = 259 * 2 * 0.895f; cam.cx = 153.2f * 2 - WX; cam.cy = 82.3f * 2 - WY; cam.nearz = 2;
}

static void build_scene(int textured) {
	int i;
	for (i = 0; i < NBUCKET; i++) ws->bucket[i] = -1;
	ws->npoly = 0; ws->nbg = 0;
	const float gy = GROUND_RAW * HSCALE, Rr = 2e5f;
	/* sol : un grand carré découpé au plan proche, toujours au plus loin */
	struct vec g[4] = {{cam.px - Rr, gy, cam.pz - Rr}, {cam.px + Rr, gy, cam.pz - Rr}, {cam.px + Rr, gy, cam.pz + Rr}, {cam.px - Rr, gy, cam.pz + Rr}};
	addworld(g, 4, C_GROUND | (C_HILL << 4), 1e9f, 2);
	const float dist = 1e5f;
	int l;
	for (l = 1; l >= 0; l--)
		for (i = 0; i < 64; i++) {
			float a0 = i / 64.0f * 2 * PI, a1 = (i + 1) / 64.0f * 2 * PI, k = l ? 1.25f : 1;
			float s0 = sinf_(a0), c0 = cosf_(a0), s1 = sinf_(a1), c1 = cosf_(a1);
			struct vec q[4] = {{cam.px + s0 * dist, gy, cam.pz + c0 * dist}, {cam.px + s1 * dist, gy, cam.pz + c1 * dist},
					   {cam.px + s1 * dist, gy + hills[l][i + 1] * dist * k, cam.pz + c1 * dist},
					   {cam.px + s0 * dist, gy + hills[l][i] * dist * k, cam.pz + c0 * dist}};
			addworld(q, 4, l ? 6 : C_HILL, l ? 9e8f : 8e8f, 0);
		}
	const struct hdsec *S = ws->secs;
	int n = ws->nsec;
	const float lw = 0.035f;
	/* sommets de chaque section en coordonnées caméra, calculés une fois : bords gauche et
	 * droit, et leur pied au sol (flancs) ; la section i+1 sert de fin à la section i */
	struct sv { struct vec L, R, Lg, Rg, w[4]; } sa, sb;
#define SV(o, A) do { (o).w[0].x = (A)->lx; (o).w[0].y = (A)->ly * HSCALE; (o).w[0].z = (A)->lz; \
	(o).w[1].x = (A)->rx; (o).w[1].y = (A)->ry * HSCALE; (o).w[1].z = (A)->rz; \
	(o).w[2] = (o).w[0]; (o).w[2].y = gy; (o).w[3] = (o).w[1]; (o).w[3].y = gy; \
	(o).L = tocam((o).w[0].x, (o).w[0].y, (o).w[0].z); (o).R = tocam((o).w[1].x, (o).w[1].y, (o).w[1].z); \
	(o).Lg = tocam((o).w[2].x, gy, (o).w[2].z); (o).Rg = tocam((o).w[3].x, gy, (o).w[3].z); } while (0)
	SV(sb, &S[0]);
	for (i = 0; i < n; i++) {
		const struct hdsec *A = &S[i], *B = &S[(i + 1) % n];
		sa = sb;
		SV(sb, B);
		/* rejet rapide : section loin derrière la caméra ou trop loin */
		if (sa.L.z < -2000 && sb.R.z < -2000 && sa.R.z < -2000 && sb.L.z < -2000) continue;
		if (sa.L.z > 60000 && sb.R.z > 60000) continue;
		int lc = (i & 1) ? C_LINE : C_LINE2;
		int wc = (A->piece & 1) ? C_WALL2 : C_WALL, wt = wc | ((wc == C_WALL ? C_WALL2 : C_WALL) << 4);
		struct vec q[4], w[4];
		float tu[4], tv[4];
		int k;
#define POLY(n, col, dep, tex) do { for (k = 0; k < (n); k++) { \
		if ((tex) == 3) { tu[k] = w[k].x + w[k].z; tv[k] = w[k].y * 4; } else { tu[k] = w[k].x; tv[k] = w[k].z; } } \
		addpoly(q, tu, tv, (n), (col), (dep), (tex)); } while (0)
		float dz = (sa.L.z + sb.R.z) * 0.5f;
		/* flancs jusqu'au sol */
		if (sa.w[0].y > gy + 0.5f || sb.w[0].y > gy + 0.5f) {
			q[0] = sa.L; q[1] = sb.L; q[2] = sb.Lg; q[3] = sa.Lg;
			w[0] = sa.w[0]; w[1] = sb.w[0]; w[2] = sb.w[2]; w[3] = sa.w[2];
			POLY(4, wt, dz + 0.4f, 3);
		}
		if (sa.w[1].y > gy + 0.5f || sb.w[1].y > gy + 0.5f) {
			q[0] = sb.R; q[1] = sa.R; q[2] = sa.Rg; q[3] = sb.Rg;
			w[0] = sb.w[1]; w[1] = sa.w[1]; w[2] = sa.w[3]; w[3] = sb.w[3];
			POLY(4, wt, dz + 0.4f, 3);
		}
		float hx = (B->lx + B->rx - A->lx - A->rx) * 0.5f, hz = (B->lz + B->rz - A->lz - A->rz) * 0.5f;
		if (hx * hx + hz * hz < 1) continue;	/* section verticale (saut) */
		int rc = (A->piece & 1) ? C_ROAD2 : C_ROAD, rt = rc | ((rc == C_ROAD ? C_ROAD2 : C_ROAD) << 4);
		/* bords intérieurs des lignes (interpolation : la même en caméra et dans le monde) */
		struct vec aL1, aR1, bL1, bR1, waL1, waR1, wbL1, wbR1;
		lerp3(&aL1, &sa.L, &sa.R, lw); lerp3(&aR1, &sa.R, &sa.L, lw); lerp3(&bL1, &sb.L, &sb.R, lw); lerp3(&bR1, &sb.R, &sb.L, lw);
		lerp3(&waL1, &sa.w[0], &sa.w[1], lw); lerp3(&waR1, &sa.w[1], &sa.w[0], lw);
		lerp3(&wbL1, &sb.w[0], &sb.w[1], lw); lerp3(&wbR1, &sb.w[1], &sb.w[0], lw);
		/* route en triangles (virages relevés : 4 coins non coplanaires), puis ses lignes */
		q[0] = aL1; q[1] = aR1; q[2] = bR1; w[0] = waL1; w[1] = waR1; w[2] = wbR1; POLY(3, rt, dz + 0.2f, 1);
		q[0] = aL1; q[1] = bR1; q[2] = bL1; w[0] = waL1; w[1] = wbR1; w[2] = wbL1; POLY(3, rt, dz + 0.2f, 1);
		q[0] = sa.L; q[1] = aL1; q[2] = bL1; q[3] = sb.L; w[0] = sa.w[0]; w[1] = waL1; w[2] = wbL1; w[3] = sb.w[0]; POLY(4, lc, dz, 0);
		q[0] = aR1; q[1] = sa.R; q[2] = sb.R; q[3] = bR1; w[0] = waR1; w[1] = sa.w[1]; w[2] = sb.w[1]; w[3] = wbR1; POLY(4, lc, dz, 0);
	}
	if (b8(0x1111c) & 0x80) add_car();	/* adversaire en course */
	(void)textured;
}

/* ------------------------------------------------------------------ cockpit et plans de bits */
/* écran du jeu gs (320x200, 4 plans) ; dans la fenêtre 3D, la couleur 1 = scène HD, le reste =
 * cockpit (agrandi deux fois dans les octets) ; hors fenêtre, tout est cockpit, recopié
 * directement en plans de bits (chaque bit doublé, chaque ligne doublée) */
int hd_nowin;
static u16 dbl[256];		/* octet -> mot, chaque bit doublé */
static u32 lane[16];		/* couleur -> un bit par octet (plans 0..3 = octets 3..0) */
static void init_tables(void) {
	int i, b;
	for (i = 0; i < 256; i++) {
		u16 v = 0;
		for (b = 0; b < 8; b++) if (i & (1 << b)) v |= (u16)(3 << (2 * b));
		dbl[i] = v;
	}
	for (i = 0; i < 16; i++) lane[i] = ((u32)(i & 1) << 24) | ((u32)((i >> 1) & 1) << 16) | ((u32)((i >> 2) & 1) << 8) | (u32)((i >> 3) & 1);
}

static void overlay(u8 *scr, const u8 *gs) {
	int y, gx;
	for (y = 16; y < 16 + 128; y++) {
		const u8 *row = gs + y * 160;
		u8 *o0 = scr + (2 * (y - 16)) * W, *o1 = o0 + W;
		for (gx = 2; gx < 18; gx++) {
			const u8 *g = row + gx * 8;
			u16 p0 = (g[0] << 8) | g[1], p1 = (g[2] << 8) | g[3], p2 = (g[4] << 8) | g[5], p3 = (g[6] << 8) | g[7];
			/* bloc entièrement en couleur 1 (plan 0 plein, autres vides) : rien */
			if (p0 == 0xffff && !(p1 | p2 | p3)) continue;
			int bit;
			for (bit = 15; bit >= 0; bit--) {
				int c = ((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1) | (((p2 >> bit) & 1) << 2) | (((p3 >> bit) & 1) << 3);
				if (c == 1 || hd_nowin) continue;
				int x = ((gx - 2) * 16 + 15 - bit) * 2;
				o0[x] = o0[x + 1] = o1[x] = o1[x + 1] = (u8)c;
			}
		}
	}
}

/* sortie : 640x400, 4 plans entrelacés (Falcon 16 couleurs : 4 mots par groupe de 16 pixels,
 * 320 octets par ligne) */
static void cockpit_planar(u16 *out, const u8 *gs) {
	int y, gx, p;
	for (y = 0; y < 200; y++) {
		const u8 *row = gs + y * 160;
		u16 *o0 = out + (2 * y) * 160, *o1 = o0 + 160;
		int inwin = y >= 16 && y < 144;
		for (gx = 0; gx < 20; gx++) {
			if (inwin && gx >= 2 && gx < 18) continue;
			const u8 *g = row + gx * 8;
			u16 *a = o0 + gx * 8, *b = o1 + gx * 8;
			for (p = 0; p < 4; p++) {
				u16 hi = dbl[g[2 * p]], lo = dbl[g[2 * p + 1]];
				a[p] = b[p] = hi;
				a[4 + p] = b[4 + p] = lo;
			}
		}
	}
}

static void c2p_window(u16 *out, const u8 *src) {
	int y, gx;
	for (y = 0; y < H; y++) {
		u16 *o = out + (WY + y) * 160 + (WX / 16) * 4;
		const u8 *s = src + y * W;
		for (gx = 0; gx < W / 16; gx++) {
			u32 h = 0, l = 0;
			int k;
			for (k = 0; k < 8; k++) h = (h << 1) | lane[s[k]];
			for (k = 8; k < 16; k++) l = (l << 1) | lane[s[k]];
			o[0] = (u16)(((h >> 16) & 0xff00) | (l >> 24));
			o[1] = (u16)(((h >> 8) & 0xff00) | ((l >> 16) & 0xff));
			o[2] = (u16)((h & 0xff00) | ((l >> 8) & 0xff));
			o[3] = (u16)(((h << 8) & 0xff00) | (l & 0xff));
			o += 4; s += 16;
		}
	}
}

/* ------------------------------------------------------------------ entrées */
/* gbase : adresse réelle du jeu moins $10100 ; w : espace de travail (sizeof(struct hdws)) */
int hd_init(const u8 *gbase, struct hdws *w) {
	G = gbase; ws = w;
	ws->track = -1;
	init_hills();
	init_tables();
	if (b8(0x13498) != 'L' || b8(0x13499) != 'I') return -1;
	return 0;
}

/* une image : écran du jeu gs (320x200), sortie planaire out (640x400, 4 plans), mode 1 = HD,
 * 2 = texturé ; rend le nombre de polygones dessinés (< 0 : erreur) */
int hd_frame(const u8 *gs, u16 *out, int mode) {
	int track = b8(0x1112d) & 7, i;
	if (track != ws->track) {
		int r = decode_track(ws, track);
		if (r < 0) { ws->track = -1; return r; }
		ws->track = track;
	}
	setup_camera();
	build_scene(mode == 2);
	u8 *scr = ws->chunky;
	/* ciel */
	{
		u32 *d = (u32 *)scr, v = C_SKY * 0x01010101u;
		for (i = 0; i < W * H / 4; i++) d[i] = v;
	}
	for (i = 0; i < ws->nbg; i++) fill(scr, &ws->polys[ws->bg[i]], mode == 2);
	for (i = NBUCKET - 1; i >= 0; i--) {
		int k = ws->bucket[i];
		while (k >= 0) { fill(scr, &ws->polys[k], mode == 2); k = ws->polys[k].next; }
	}
	overlay(scr, gs);
	c2p_window(out, scr);
	cockpit_planar(out, gs);
	return ws->npoly;
}

/* ------------------------------------------------------------------ sans bibliothèque */
#ifdef __mc68000__
void *memcpy(void *d, const void *s, unsigned long n) {
	u8 *a = d; const u8 *b = s;
	while (n--) *a++ = *b++;
	return d;
}
void *memset(void *d, int c, unsigned long n) {
	u8 *a = d;
	while (n--) *a++ = (u8)c;
	return d;
}
/* table d'entrée, en tête du binaire : +0 hd_init, +4 hd_frame (arguments sur la pile, résultat
 * en d0, d0-d1/a0-a1/fp0-fp1 détruits) */
__asm__(".section .entry,\"ax\"\n"
	"\tbra.w hd_init\n"
	"\tbra.w hd_frame\n"
	"\t.text\n");
#endif

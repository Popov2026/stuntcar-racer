/* hd.h - mode HD de SCRF030 (voir hd.c) */
#ifndef HD_INC
#define HD_INC
typedef unsigned char u8;
typedef signed short s16;
typedef unsigned short u16;
typedef signed int s32;
typedef unsigned int u32;

#define HD_W 640
#define HD_H 400
#define HD_MAXPIECES 128
#define HD_MAXSECS 2048
#define HD_MAXPOLYS 3000
#define HD_MAXBG 80
#define HD_MAXV 12

struct hdsec { float lx, ly, lz, rx, ry, rz; s16 flag, piece; };
struct hdpoly { float x[HD_MAXV], y[HD_MAXV], w[HD_MAXV], u[HD_MAXV], v[HD_MAXV]; s16 n, next; u8 color, tex; };
struct hdpiece_ { int x, z, type; u32 hL, hR, profL, profR; int neg; };

struct hdws {
	int track, nsec, npieces, npoly, nbg;
	s16 bucket[1024], btail[1024], bg[HD_MAXBG];
	struct hdpiece_ pieces[HD_MAXPIECES];
	struct hdsec secs[HD_MAXSECS], tmp[HD_MAXSECS];
	struct hdpoly polys[HD_MAXPOLYS];
	u8 chunky[HD_W * HD_H];
};

int hd_init(const u8 *gbase, struct hdws *w);
int hd_frame(const u8 *gs, u16 *out, int mode);
#endif

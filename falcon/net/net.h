/* net.h - multijoueur en ligne de SCRCT60 (voir net.c) */
#ifndef NET_INC
#define NET_INC
typedef unsigned char u8;
typedef signed short s16;
typedef unsigned short u16;
typedef signed int s32;
typedef unsigned int u32;

/* transport fourni par le lanceur (convention gcc : arguments 32 bits sur la pile, d0) */
struct nio {
	s32 (*send)(const u8 *p, s32 n);	/* octets acceptés (0 : plus tard), < 0 : erreur */
	s32 (*avail)(void);			/* octets reçus en attente, < 0 : connexion fermée */
	s32 (*get)(u8 *p, s32 n);		/* lit au plus n octets */
	u32 (*ms)(void);			/* horloge en millisecondes */
};

enum { NS_FAILED = -1, NS_JOINING = 1, NS_WAITING = 2, NS_HANDSHAKE = 3, NS_CONNECTED = 4 };

#define RXSIZE 4096
/* état partagé avec le lanceur (assembleur) : décalages fixes, voir scrf030.s (NET_*) */
struct net {
	struct nio *io;		/* +0 */
	s32 state;		/* +4 */
	s32 master;		/* +8 : 1 = maître (mène les menus et la poignée de main du jeu) */
	s32 params_ok;		/* +12 : physique du serveur = celle du jeu d'origine */
	u32 hash;		/* +16 : empreinte du programme du jeu (FNV-1a, comme la version PC) */
	char version[8];	/* +20 : « v45 » */
	char name[16];		/* +28 : pseudo */
	char room[16];		/* +44 : salle privée (vide : premier joueur disponible) */
	char peer[24];		/* +60 : pseudo de l'adversaire */
	char text[64];		/* +84 : état en clair */
	/* privé */
	u32 last_rx;
	u32 last_keep;		/* attente d'un adversaire : signe de vie au relais */
	s32 picked;
	s32 olen, ilen, dlen, rhead, rtail;
	u8 obuf[1024], ibuf[2048], dbuf[64], rx[RXSIZE];
};

int net_start(struct net *n);
int net_poll(void);
void net_put(int b);
int net_avail(void);
int net_get(void);
void net_bye(void);
#endif

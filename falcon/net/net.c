/* net.c - multijoueur en ligne de SCRCT60 : le câble « Computer Link » du jeu d'origine passe
 * par le serveur relais de la version PC (native/src/net.cpp, native/server/scr_relay.cpp).
 *
 * Trames (comme la version PC) : type (1 octet), longueur (2 octets, gros-boutiste), données.
 *   vers le relais : JOIN2 « AUTO|SALLE \0 code \0 version \0 nom », PICK « numéro »
 *   du relais      : INFO « WAIT » | « PAIRED 1|2 » | « GONE » | « BUSY » | « FULL » | « ERR ... »,
 *                    LIST « numéro\tnom\n... », PARAMS « gravity=1 ... »
 *   entre les jeux : HELLO « SCR1 \0 version \0 empreinte(4) nom \0 réglages », DATA (octets du
 *                    câble), PING / PONG (8 octets renvoyés tels quels), BYE
 * Le transport (connexion TCP par STinG, ou flux brut sur le port série) est fourni par le
 * lanceur : fonctions de struct nio. Calcul entier, sans bibliothèque : marche sur tout 680x0.
 */
#include "net.h"

enum { NF_HELLO = 1, NF_DATA = 2, NF_PING = 3, NF_PONG = 4, NF_BYE = 5, NF_JOIN = 10, NF_INFO = 11, NF_JOIN2 = 12,
       NF_LIST = 13, NF_PICK = 14, NF_PROBE = 15, NF_PARAMS = 16, NF_CHAT = 17 };

static struct net *N;

static int slen(const char *s) { int n = 0; while (s[n]) n++; return n; }
static int sbegins(const u8 *p, int n, const char *s) {
	int k = slen(s);
	if (n < k) return 0;
	while (k--) if (p[k] != (u8)s[k]) return 0;
	return 1;
}
static void scopy(char *d, const char *s, int max) {
	int i = 0;
	while (s[i] && i < max - 1) { d[i] = s[i]; i++; }
	d[i] = 0;
}
static void fail(const char *why) {
	if (N->state == NS_FAILED) return;
	scopy(N->text, why, sizeof N->text);
	N->state = NS_FAILED;
}

/* --------------------------------------------------------------- émission */
static void flush(void) {
	while (N->olen > 0) {
		s32 k = N->io->send(N->obuf, N->olen);
		if (k < 0) { fail("connexion perdue (envoi)"); N->olen = 0; return; }
		if (k == 0) return;		/* plus tard */
		s32 i;
		for (i = k; i < N->olen; i++) N->obuf[i - k] = N->obuf[i];
		N->olen -= k;
	}
}
static void frame(int type, const u8 *p, int n) {
	if (N->olen + 3 + n > (s32)sizeof N->obuf) flush();
	if (N->olen + 3 + n > (s32)sizeof N->obuf) { fail("connexion bloquée (tampon plein)"); return; }
	u8 *o = N->obuf + N->olen;
	o[0] = (u8)type; o[1] = (u8)(n >> 8); o[2] = (u8)n;
	int i;
	for (i = 0; i < n; i++) o[3 + i] = p[i];
	N->olen += 3 + n;
}
/* octets du câble émis par le jeu : regroupés dans une trame DATA */
static void flush_data(void) {
	if (N->dlen > 0) { frame(NF_DATA, N->dbuf, N->dlen); N->dlen = 0; }
}

static void send_hello(void) {
	u8 h[160];
	int n = 0, i;
	const char *t = "SCR1";
	for (i = 0; t[i]; i++) h[n++] = (u8)t[i];
	h[n++] = 0;
	for (i = 0; N->version[i]; i++) h[n++] = (u8)N->version[i];
	h[n++] = 0;
	h[n++] = (u8)(N->hash >> 24); h[n++] = (u8)(N->hash >> 16); h[n++] = (u8)(N->hash >> 8); h[n++] = (u8)N->hash;
	for (i = 0; N->name[i]; i++) h[n++] = (u8)N->name[i];
	h[n++] = 0;
	t = "1 1 1 1 1 1 0";		/* réglages de physique du jeu d'origine (seuls possibles ici) */
	for (i = 0; t[i]; i++) h[n++] = (u8)t[i];
	frame(NF_HELLO, h, n);
	N->state = NS_HANDSHAKE;
	scopy(N->text, "Poignee de main avec l'adversaire", sizeof N->text);
}

/* --------------------------------------------------------------- réception */
static void handle(int type, const u8 *p, int n) {
	N->last_rx = N->io->ms();
	switch (type) {
	case NF_INFO:
		if (sbegins(p, n, "PAIRED")) {
			N->master = n > 7 ? p[7] == '1' : 0;
			send_hello();
		} else if (sbegins(p, n, "WAIT")) {
			if (N->state < NS_WAITING) {
				N->state = NS_WAITING;
				scopy(N->text, N->room[0] ? "Salle privee : en attente d'un adversaire" : "En attente d'un adversaire", sizeof N->text);
			}
		} else if (sbegins(p, n, "FULL")) fail("salle deja complete");
		else if (sbegins(p, n, "GONE")) fail("l'autre joueur s'est deconnecte");
		else if (sbegins(p, n, "ERR ")) {
			char b[64]; int i, k = 0;
			const char *pre = "relais : ";
			for (i = 0; pre[i]; i++) b[k++] = pre[i];
			for (i = 4; i < n && k < 63; i++) if (p[i] >= 32 && p[i] < 127) b[k++] = (char)p[i];
			b[k] = 0;
			fail(b);
		}
		break;
	case NF_LIST:			/* salle privée : on choisit le premier joueur libre présent */
		if (N->state == NS_WAITING && n > 0 && !N->picked) {
			int k = 0;
			while (k < n && p[k] != '\t' && p[k] != '\n') k++;
			if (k > 0 && k < 12) { frame(NF_PICK, p, k); N->picked = 1; }
		}
		break;
	case NF_PARAMS: {		/* physique imposée par le serveur : seule celle d'origine est possible */
		const char *def = "gravity=1 thrust=1 brake=1 timestep=1 damping=1 boostuse=1 shock=0";
		N->params_ok = sbegins(p, n, def);
		break;
	}
	case NF_HELLO: {
		/* « SCR1 \0 version \0 empreinte nom \0 réglages » */
		int z1 = 0, z2, i;
		if (!sbegins(p, n, "SCR1")) { fail("l'autre programme n'est pas Stunt Car Racer"); return; }
		while (z1 < n && p[z1]) z1++;
		z2 = z1 + 1;
		while (z2 < n && p[z2]) z2++;
		if (z2 + 5 > n) { fail("poignee de main incomplete"); return; }
		int vl = z2 - z1 - 1;
		if (vl != slen(N->version)) { fail("versions differentes (il faut la v45 en face)"); return; }
		for (i = 0; i < vl; i++) if (p[z1 + 1 + i] != (u8)N->version[i]) { fail("versions differentes (il faut la v45 en face)"); return; }
		u32 h = ((u32)p[z2 + 1] << 24) | ((u32)p[z2 + 2] << 16) | ((u32)p[z2 + 3] << 8) | p[z2 + 4];
		if (h != N->hash) { fail("jeu different de celui de l'autre joueur (meme disquette requise)"); return; }
		int k = 0;
		for (i = z2 + 5; i < n && p[i] && k < (int)sizeof N->peer - 1; i++) if (p[i] >= 32 && p[i] < 127) N->peer[k++] = (char)p[i];
		N->peer[k] = 0;
		N->state = NS_CONNECTED;
		scopy(N->text, "Relie a l'adversaire", sizeof N->text);
		break;
	}
	case NF_DATA: {
		int i;
		for (i = 0; i < n; i++) {
			s32 nx = (N->rhead + 1) & (RXSIZE - 1);
			/* plein : le jeu ne lit pas encore le câble (menus) ; le maître répète $80 jusqu'à la
			 * réponse $40, les plus anciens octets peuvent être perdus */
			if (nx == N->rtail) N->rtail = (N->rtail + 1) & (RXSIZE - 1);
			N->rx[N->rhead] = p[i];
			N->rhead = nx;
		}
		break;
	}
	case NF_PING: frame(NF_PONG, p, n); break;
	case NF_BYE: fail("l'autre joueur a quitte la partie"); break;
	default: break;			/* PONG, CHAT, course à plusieurs : ignorés */
	}
}

/* lit ce qui est arrivé et découpe les trames */
static void receive(void) {
	for (;;) {
		s32 room = (s32)sizeof N->ibuf - N->ilen;
		if (room <= 0) { fail("trame trop longue"); return; }
		s32 k = N->io->avail();
		if (k < 0) { fail(N->state >= NS_CONNECTED ? "l'autre joueur s'est deconnecte" : "connexion fermee par le serveur"); return; }
		if (k == 0) break;
		if (k > room) k = room;
		k = N->io->get(N->ibuf + N->ilen, k);
		if (k <= 0) break;
		N->ilen += k;
	}
	s32 pos = 0;
	while (N->ilen - pos >= 3 && N->state != NS_FAILED) {
		s32 n = (N->ibuf[pos + 1] << 8) | N->ibuf[pos + 2];
		if (N->ilen - pos < 3 + n) break;
		handle(N->ibuf[pos], N->ibuf + pos + 3, (int)n);
		pos += 3 + n;
	}
	if (pos > 0) {
		s32 i;
		for (i = pos; i < N->ilen; i++) N->ibuf[i - pos] = N->ibuf[i];
		N->ilen -= pos;
	}
}

/* --------------------------------------------------------------- entrées */
/* inscription au relais (la connexion TCP est ouverte par le lanceur) */
int net_start(struct net *n) {
	N = n;
	n->state = NS_JOINING; n->olen = n->ilen = n->dlen = 0; n->rhead = n->rtail = 0;
	n->master = 0; n->picked = 0; n->params_ok = 1; n->peer[0] = 0;
	n->last_rx = n->io->ms();
	u8 j[96];
	int k = 0, i;
	const char *mode = n->room[0] ? "SALLE" : "AUTO";
	for (i = 0; mode[i]; i++) j[k++] = (u8)mode[i];
	j[k++] = 0;
	for (i = 0; n->room[i]; i++) j[k++] = (u8)n->room[i];
	j[k++] = 0;
	for (i = 0; n->version[i]; i++) j[k++] = (u8)n->version[i];
	j[k++] = 0;
	for (i = 0; n->name[i]; i++) j[k++] = (u8)n->name[i];
	frame(NF_JOIN2, j, k);
	scopy(n->text, "Inscription au serveur relais", sizeof n->text);
	flush();
	return 0;
}

/* à appeler souvent : réception, réponses, envoi */
int net_poll(void) {
	if (N->state == NS_FAILED) return N->state;
	receive();
	flush_data();
	flush();
	if (N->state == NS_JOINING && N->io->ms() - N->last_rx > 20000) fail("pas de reponse du serveur relais");
	return N->state;
}

/* câble du jeu (BIOS, périphérique 1) */
void net_put(int b) {
	N->dbuf[N->dlen++] = (u8)b;
	if (N->dlen >= (s32)sizeof N->dbuf) flush_data();
}
int net_avail(void) { return N->rhead != N->rtail; }
int net_get(void) {
	if (N->rhead == N->rtail) return -1;
	int b = N->rx[N->rtail];
	N->rtail = (N->rtail + 1) & (RXSIZE - 1);
	return b;
}
/* fin de partie : BYE */
void net_bye(void) {
	if (N->state == NS_CONNECTED) { frame(NF_BYE, (const u8 *)"fin", 3); flush(); }
}

/* ------------------------------------------------------------------ sans bibliothèque */
#ifdef __mc68000__
/* table d'entrée, en tête du binaire (arguments sur la pile, résultat en d0, d0-d1/a0-a1 détruits) */
__asm__(".section .entry,\"ax\"\n"
	"\tbra.w net_start\n"		/* +0  net_start(struct net *) */
	"\tbra.w net_poll\n"		/* +4  net_poll() */
	"\tbra.w net_put\n"		/* +8  net_put(octet) */
	"\tbra.w net_avail\n"		/* +12 net_avail() */
	"\tbra.w net_get\n"		/* +16 net_get() */
	"\tbra.w net_bye\n"		/* +20 net_bye() */
	"\t.text\n");
#endif

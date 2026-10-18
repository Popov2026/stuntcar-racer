; ---------------------------------------------------------------------------
; online.s - multijoueur en ligne de SCRCT60 (inclus par scrf030.s, -DCT60=1)
;
; Comme la version PC (v45), le menu de départ du jeu reçoit un 4e choix, « 4. Online
; Multiplayer ». Le jeu l'envoie à son Computer Link ($453B6), qui n'accède au câble que par le
; BIOS, périphérique 1 (Bconstat, Bconin, Bconout : docs/RETRO_INGENIERIE.md §10) : après ce
; choix, ces appels sont détournés (trap #13, par la table des vecteurs déplacée) vers le serveur
; relais de la version PC ; les octets du câble partent dans des trames DATA, comme le fait la
; version PC (native/src/net.cpp). Protocole dans falcon/net/net.c (C, relogé ici).
; « 3. Computer Link » reste le câble null modem d'origine : BIOS laissé au TOS.
;
; Transport : STinG (cookie « STiK » : STinG sous TOS, GlueSTiK sous MiNT ; carte réseau de la
; CT60), ou flux brut sur le port série (modem WiFi, passerelle PC, essais sous Hatari).
; Réglages dans SCRCT60.INF, après la première ligne :
;   nom = pseudo        salle = code (vide : premier joueur disponible)
;   relais = adresse[:port] (vide : serveur officiel)    transport = sting | serie
;   modem = commande envoyée au modem (transport série, ex. ATDT relais.exemple:27420)
;   empreinte = empreinte du jeu (FNV-1a, écrite par scr_tool.py)
; ---------------------------------------------------------------------------

NET_STATE	equ	4
NET_MASTER	equ	8
NET_PARAMSOK	equ	12
NET_HASH	equ	16
NET_VERSION	equ	20
NET_NAME	equ	28
NET_ROOM	equ	44
NET_PEER	equ	60
NET_TEXT	equ	84
NET_BYTES	equ	8192			; >= sizeof(struct net)
NS_CONNECTED	equ	4
NET_PORT	equ	27420

; appel du module C : a0 = point d'entrée ; arguments déjà sur la pile (convention gcc)
NETCALL	macro
	jsr	net_blob+\1
	endm

; --------------------------------------------------------------- configuration
; lignes « clé = valeur » de SCRCT60.INF après la première : a0 = texte, d1.w = longueur
net_parse:
	movem.l	d0-d3/a0-a3,-(sp)
	lea	(a0,d1.w),a3			; fin
	clr.b	(a3)
.line:	cmp.l	a3,a0				; début de ligne
	bhs	.done
	lea	.keys(pc),a1
.key:	move.w	(a1)+,d2			; décalage du texte de la clé
	beq.s	.skip
	move.w	(a1)+,d3			; décalage de la destination
	move.w	(a1)+,d0			; taille
	lea	.keys(pc,d2.w),a2
	move.l	a0,-(sp)
.cmp:	move.b	(a2)+,d1
	beq.s	.match
	cmp.b	(a0)+,d1
	beq.s	.cmp
	move.l	(sp)+,a0
	bra.s	.key
.match:	addq.l	#4,sp
.sp:	cmp.b	#' ',(a0)			; « = » entouré d'espaces
	bne.s	.eq
	addq.l	#1,a0
	bra.s	.sp
.eq:	cmp.b	#'=',(a0)+
	bne.s	.skip
.sp2:	cmp.b	#' ',(a0)
	bne.s	.val
	addq.l	#1,a0
	bra.s	.sp2
.val:	lea	net_cfg,a2
	add.w	d3,a2
	move.l	a2,a1				; début de la valeur
	subq.w	#2,d0
.cp:	move.b	(a0),d1
	cmp.b	#13,d1
	beq.s	.end
	cmp.b	#10,d1
	beq.s	.end
	tst.b	d1
	beq.s	.end
	cmp.b	#';',d1				; commentaire
	beq.s	.end
	move.b	d1,(a2)+
	addq.l	#1,a0
	dbf	d0,.cp
.end:	clr.b	(a2)
.tr:	cmp.l	a1,a2				; espaces de fin retirés
	bls.s	.skip
	cmp.b	#' ',-1(a2)
	bne.s	.skip
	clr.b	-(a2)
	bra.s	.tr
.skip:	cmp.l	a3,a0				; ligne suivante
	bhs.s	.done
	move.b	(a0)+,d1
	cmp.b	#10,d1
	bne.s	.skip
	bra	.line
.done:	movem.l	(sp)+,d0-d3/a0-a3
	rts
.keys:	dc.w	.k1-.keys,cfg_name-net_cfg,16
	dc.w	.k2-.keys,cfg_room-net_cfg,16
	dc.w	.k3-.keys,cfg_relay-net_cfg,64
	dc.w	.k4-.keys,cfg_transport-net_cfg,8
	dc.w	.k5-.keys,cfg_modem-net_cfg,64
	dc.w	.k6-.keys,cfg_hash-net_cfg,12
	dc.w	.k7-.keys,cfg_name-net_cfg,16
	dc.w	0
.k1:	dc.b	"nom",0
.k2:	dc.b	"salle",0
.k3:	dc.b	"relais",0
.k4:	dc.b	"transport",0
.k5:	dc.b	"modem",0
.k6:	dc.b	"empreinte",0
.k7:	dc.b	"pseudo",0
	even

; --------------------------------------------------------------- transport : STinG
; fonctions STinG (cdecl, entiers 16 bits, d0-d2/a0-a1 détruits) ; table TPL (transprt.h)
TPL_TCP_OPEN	equ	40
TPL_TCP_CLOSE	equ	44
TPL_TCP_SEND	equ	48
TPL_TCP_WAIT	equ	52
TPL_CNBYTES	equ	76
TPL_CNGETBLOCK	equ	88
TPL_RESOLVE	equ	96
E_NODATA	equ	-2
E_OBUFFULL	equ	-1
E_USERTIMEOUT	equ	-15
E_CNTIMEOUT	equ	-16
TPL_ERRTEXT	equ	28

; d0 = 0 si STinG est là (tpl posé), sinon -1 (superviseur)
sting_find:
	move.l	$5a0.w,d0
	beq.s	.no
	move.l	d0,a0
.c:	move.l	(a0)+,d0
	beq.s	.no
	move.l	(a0)+,d1
	cmp.l	#'STiK',d0
	bne.s	.c
	move.l	d1,a0				; DRV_LIST : « STiKmagic », get_dftab en +10
	cmp.l	#'STiK',(a0)
	bne.s	.no
	move.l	10(a0),a1
	pea	.tname(pc)
	jsr	(a1)				; get_dftab("TRANSPORT_TCPIP")
	addq.l	#4,sp
	move.l	d0,sting_tpl
	beq.s	.no
	moveq	#0,d0
	rts
.no:	moveq	#-1,d0
	rts
.tname:	dc.b	"TRANSPORT_TCPIP",0
	even

; nom ou adresse (net_host) -> net_ip ; d0 = 0 si trouvée, sinon code d'erreur STinG (< 0).
; Au lancement, dans le contexte normal du TOS (la résolution peut attendre le serveur DNS)
sting_resolve:
	movem.l	d1-d7/a0-a6,-(sp)
	move.l	sting_tpl,a5
	move.w	#1,-(sp)			; resolve(nom, NULL, &adresse, 1)
	pea	net_ip
	clr.l	-(sp)
	pea	net_host
	move.l	TPL_RESOLVE(a5),a0
	jsr	(a0)
	lea	14(sp),sp
	ext.l	d0
	bgt.s	.ok
	tst.l	d0
	bmi.s	.out
	moveq	#-1,d0				; aucune adresse
	bra.s	.out
.ok:	moveq	#0,d0
.out:	movem.l	(sp)+,d1-d7/a0-a6
	rts

; connexion TCP vers net_ip:net_port, attente par tranches d'une seconde, 15 s au plus ;
; d1 = 0 : sans Échap (lancement), sinon Échap du jeu. d0 = 0 si établie (sting_cn), sinon
; code d'erreur STinG (< 0), connexion refermée
sting_connect:
	movem.l	d1-d7/a0-a6,-(sp)
	move.l	d1,d6
	move.l	sting_tpl,a5
	move.w	#2048,-(sp)			; TCP_open(adresse, port, 0, 2048)
	clr.w	-(sp)
	move.w	net_port,-(sp)
	move.l	net_ip,-(sp)
	move.l	TPL_TCP_OPEN(a5),a0
	jsr	(a0)
	lea	10(sp),sp
	ext.l	d0
	bmi.s	.out
	move.w	d0,sting_cn
	moveq	#15-1,d7
.w:	move.w	#1,-(sp)			; TCP_wait_state(cn, TESTABLISH, 1 s)
	move.w	#4,-(sp)
	move.w	sting_cn,-(sp)
	move.l	TPL_TCP_WAIT(a5),a0
	jsr	(a0)
	addq.l	#6,sp
	ext.l	d0
	beq.s	.out
	cmp.w	#E_CNTIMEOUT,d0			; pas encore : on continue
	beq.s	.t
	cmp.w	#E_USERTIMEOUT,d0
	bne.s	.err
.t:
	tst.l	d6
	beq.s	.n
	move.l	game_base,a0
	cmp.b	#$b3,G_KEYS+1(a0)		; Échap
	beq.s	.err
.n:	dbf	d7,.w
.err:	move.l	d0,-(sp)
	bsr	sting_close
	move.l	(sp)+,d0
.out:	movem.l	(sp)+,d1-d7/a0-a6
	rts

; fonctions du transport pour le module C (convention gcc : arguments 32 bits, d2-d7/a2-a6 gardés)
st_send:					; (p, n) -> n acceptés, 0 plus tard, -1 erreur
	movem.l	d2/a2,-(sp)
	move.l	sting_tpl,a2
	move.w	8+8+2(sp),-(sp)			; n
	move.l	8+4+2(sp),-(sp)			; p
	move.w	sting_cn,-(sp)
	move.l	TPL_TCP_SEND(a2),a0
	jsr	(a0)
	addq.l	#8,sp
	ext.l	d0
	beq.s	.ok
	cmp.w	#E_OBUFFULL,d0
	bne.s	.err
	moveq	#0,d0
	bra.s	.out
.ok:	move.l	8+8(sp),d0
	bra.s	.out
.err:	moveq	#-1,d0
.out:	movem.l	(sp)+,d2/a2
	rts
st_avail:
	movem.l	d2/a2,-(sp)
	move.l	sting_tpl,a2
	move.w	sting_cn,-(sp)
	move.l	TPL_CNBYTES(a2),a0
	jsr	(a0)
	addq.l	#2,sp
	ext.l	d0
	bpl.s	.out
	cmp.w	#E_NODATA,d0
	bne.s	.err
	moveq	#0,d0
	bra.s	.out
.err:	moveq	#-1,d0
.out:	movem.l	(sp)+,d2/a2
	rts
st_get:						; (p, n) -> octets lus
	movem.l	d2/a2,-(sp)
	move.l	sting_tpl,a2
	move.w	8+8+2(sp),-(sp)
	move.l	8+4+2(sp),-(sp)
	move.w	sting_cn,-(sp)
	move.l	TPL_CNGETBLOCK(a2),a0
	jsr	(a0)
	addq.l	#8,sp
	ext.l	d0
	bpl.s	.out
	moveq	#0,d0
.out:	movem.l	(sp)+,d2/a2
	rts
sting_close:
	movem.l	d0-d2/a0-a2,-(sp)
	move.l	sting_tpl,a2
	clr.l	-(sp)				; TCP_close(cn, 0, NULL)
	clr.w	-(sp)
	move.w	sting_cn,-(sp)
	move.l	TPL_TCP_CLOSE(a2),a0
	jsr	(a0)
	addq.l	#8,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts

; --------------------------------------------------------------- transport : port série
; pilote du périphérique 1 (AUX) appelé directement par les tables du TOS (xconstat $51E,
; xconin $53E, xcostat $55E, xconout $57E ; entrée 1, celle que Bconmap tient à jour) : pas de
; trap #13, donc pas de réentrance dans le répartiteur du BIOS quand la VBL relève le réseau
; pendant un appel du jeu au TOS. Superviseur ; le pilote peut détruire d0-d2/a0-a2.
aux	macro					; table \1 : (périphérique, [octet]) déjà empilés
	move.l	\1+4.w,a0
	jsr	(a0)
	endm
se_send:					; (p, n) : envoie tout ce que le port accepte
	movem.l	d2-d4/a2-a3,-(sp)
	move.l	20+4(sp),a3
	move.l	20+8(sp),d4
	moveq	#0,d3
.l:	cmp.l	d4,d3
	bhs.s	.out
	move.w	#1,-(sp)
	aux	$55e				; Bcostat(1)
	addq.l	#2,sp
	tst.w	d0
	beq	.out
	moveq	#0,d0
	move.b	(a3,d3.l),d0
	move.w	d0,-(sp)
	move.w	#1,-(sp)
	aux	$57e				; Bconout(1, octet)
	addq.l	#4,sp
	addq.l	#1,d3
	bra.s	.l
.out:	move.l	d3,d0
	movem.l	(sp)+,d2-d4/a2-a3
	rts
se_avail:
	movem.l	d2/a2,-(sp)
	move.w	#1,-(sp)
	aux	$51e				; Bconstat(1) : -1 si un octet attend
	addq.l	#2,sp
	ext.l	d0
	neg.l	d0
	movem.l	(sp)+,d2/a2
	rts
se_get:						; (p, n) : ce qui est déjà arrivé
	movem.l	d2-d4/a2-a3,-(sp)
	move.l	20+4(sp),a3
	move.l	20+8(sp),d4
	moveq	#0,d3
.l:	cmp.l	d4,d3
	bhs.s	.out
	move.w	#1,-(sp)
	aux	$51e				; Bconstat(1)
	addq.l	#2,sp
	tst.w	d0
	beq.s	.out
	move.w	#1,-(sp)
	aux	$53e				; Bconin(1)
	addq.l	#2,sp
	move.b	d0,(a3,d3.l)
	addq.l	#1,d3
	bra.s	.l
.out:	move.l	d3,d0
	movem.l	(sp)+,d2-d4/a2-a3
	rts
io_ms:	move.l	$4ba.w,d0			; horloge 200 Hz -> millisecondes
	mulu.l	#5,d0
	rts

; --------------------------------------------------------------- au lancement (rien sur le réseau)
; réglages de SCRCT60.INF dans struct net, module C relogé, STinG cherché ; mode utilisateur
net_setup:
	movem.l	d0-d2/a0-a2/a6,-(sp)
	pea	.sup(pc)			; vecteurs du TOS, STinG
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	lea	net_blob,a0			; module C lié en 0 : mots longs absolus relogés
	lea	net_rel,a1
	move.l	a0,d1
.rl:	move.l	(a1)+,d0
	bmi.s	.rd
	add.l	d1,(a0,d0.l)
	bra.s	.rl
.rd:	lea	net_state,a6			; struct net
	move.l	#net_io,(a6)
	lea	cfg_name,a0			; pseudo, salle, version, empreinte
	lea	NET_NAME(a6),a1
	moveq	#15-1,d0
	bsr	.cpy
	tst.b	NET_NAME(a6)
	bne.s	.n1
	move.l	#'Falc',NET_NAME(a6)
	move.l	#'on'<<16,NET_NAME+4(a6)
.n1:	lea	cfg_room,a0
	lea	NET_ROOM(a6),a1
	moveq	#15-1,d0
	bsr	.cpy
	move.l	#'v45'<<8,NET_VERSION(a6)
	move.l	#$b1f6578d,d0			; empreinte du jeu étudié (scr_tool.py l'écrit dans l'INF)
	lea	cfg_hash,a0
	tst.b	(a0)
	beq.s	.h1
	bsr	.hex
.h1:	move.l	d0,NET_HASH(a6)
; adresse du relais : relais = adresse[:port], sinon serveur officiel (adresse chiffrée comme
; dans la version PC, jamais affichée)
	move.w	#NET_PORT,net_port
	lea	cfg_relay,a0
	tst.b	(a0)
	bne.s	.cfgr
	lea	.offi(pc),a0
	lea	net_host,a1
	moveq	#12-1,d1
	moveq	#$5a,d2
.dec:	move.b	(a0)+,d0
	eor.b	d2,d0
	move.b	d0,(a1)+
	add.b	#13,d2
	dbf	d1,.dec
	clr.b	(a1)
	bra.s	.tr
.cfgr:	lea	net_host,a1			; « adresse:port »
.cr:	move.b	(a0)+,d0
	beq.s	.cre
	cmp.b	#':',d0
	beq.s	.port
	move.b	d0,(a1)+
	bra.s	.cr
.port:	moveq	#0,d1
.pd:	moveq	#0,d0
	move.b	(a0)+,d0
	sub.b	#'0',d0
	bcs.s	.pe
	cmp.b	#9,d0
	bhi.s	.pe
	mulu.w	#10,d1
	add.w	d0,d1
	bra.s	.pd
.pe:	move.w	d1,net_port
.cre:	clr.b	(a1)
; transport : STinG (défaut) ou port série
.tr:	lea	net_io,a0
	cmp.b	#'s',cfg_transport		; « serie »
	bne.s	.st
	cmp.b	#'e',cfg_transport+1
	bne.s	.st
	move.w	#1,net_serial
	move.l	#se_send,(a0)+
	move.l	#se_avail,(a0)+
	move.l	#se_get,(a0)+
	move.l	#io_ms,(a0)
	move.w	#-1,-(sp)			; Rsconf : 19200 bauds, pas de contrôle de flux
	move.w	#-1,-(sp)
	move.w	#-1,-(sp)
	move.w	#-1,-(sp)
	clr.w	-(sp)
	move.w	#1,-(sp)
	move.w	#15,-(sp)
	trap	#14
	lea	14(sp),sp
	bra.s	.out
.st:	move.l	#st_send,(a0)+
	move.l	#st_avail,(a0)+
	move.l	#st_get,(a0)+
	move.l	#io_ms,(a0)
	bsr	net_probe
.out:	movem.l	(sp)+,d0-d2/a0-a2/a6
	rts
.cpy:	move.b	(a0)+,(a1)+
	dbeq	d0,.cpy
	clr.b	(a1)
	rts
.hex:	moveq	#0,d0				; 8 chiffres hexadécimaux (a0)
	moveq	#8-1,d2
.hx:	moveq	#0,d1
	move.b	(a0)+,d1
	sub.b	#'0',d1
	cmp.b	#9,d1
	bls.s	.hd
	and.b	#$df,d1
	sub.b	#'A'-'0'-10,d1
.hd:	lsl.l	#4,d0
	and.b	#15,d1
	or.b	d1,d0
	dbf	d2,.hx
	rts
.sup:	move.l	$b4.w,bios_vec
	move.l	$b8.w,xbios_vec
	bsr	sting_find
	rts
.offi:	dc.b	$37,$06,$07,$e2,$ef,$e9,$c9,$d1,$a7,$e1,$bf,$8a
	even

; essai au lancement (carte réseau) : STinG, adresse du relais, connexion TCP ; message à l'écran.
; La connexion n'est gardée : la partie en ligne se connecte au choix « 4. Online Multiplayer »
net_probe:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	txt_on1(pc),a0
	bsr	print
	tst.l	sting_tpl
	bne.s	.s1
	lea	txt_on_nost(pc),a0
	bra	.bad
.s1:	lea	txt_on_srv(pc),a0
	bsr	print
	lea	txt_on_off(pc),a0		; serveur officiel : adresse jamais affichée
	tst.b	cfg_relay
	beq.s	.s2
	lea	cfg_relay,a0
.s2:	bsr	print
	lea	txt_crlf(pc),a0
	bsr	print
	bsr	sting_resolve
	tst.l	d0
	beq.s	.s3
	lea	txt_on_dns(pc),a0
	bra.s	.err
.s3:	moveq	#0,d1
	bsr	sting_connect
	tst.l	d0
	beq.s	.s4
	clr.l	net_ip				; plus d'essai dans le jeu (Link abandoned)
	lea	txt_on_tcp(pc),a0
	bra.s	.err
.s4:	bsr	sting_close			; joignable : refermée
	lea	txt_on_ok(pc),a0
	bsr	print
	moveq	#50-1,d7			; 1 s pour lire
	bra.s	.wt
.err:	move.l	d0,d6				; message, puis texte d'erreur de STinG
	bsr	print
	move.l	sting_tpl,a5
	move.w	d6,-(sp)
	move.l	TPL_ERRTEXT(a5),a0
	jsr	(a0)				; get_err_text(code)
	addq.l	#2,sp
	move.l	d0,a0
	tst.l	d0
	beq.s	.e1
	bsr	print
.e1:	lea	txt_crlf(pc),a0
.bad:	bsr	print
	lea	txt_on_ko(pc),a0
	bsr	print
	move.w	#150-1,d7			; 3 s pour lire
.wt:	move.w	#37,-(sp)			; Vsync
	trap	#14
	addq.l	#2,sp
	dbf	d7,.wt
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; --------------------------------------------------------------- connexion (« 4. Online Multiplayer »)
; appelée au test maître / esclave du Computer Link ($453EC), pendant que le jeu affiche
; « Linking » ; superviseur. Relais (STinG ou modem), inscription, attente d'un adversaire,
; poignée de main. Échap (touche du jeu) abandonne. d0 = 0 : relié (net_on posé)
net_open:
	movem.l	d1-d7/a0-a6,-(sp)
	bsr	net_shut			; connexion précédente éventuelle
	lea	net_state,a6
	tst.w	net_serial
	bne.s	.ser
	tst.l	sting_tpl			; carte réseau : STinG (ou GlueSTiK)
	beq	.no
	tst.l	net_ip				; adresse trouvée au lancement
	beq	.no
	move.w	sr,-(sp)			; interruptions permises pendant l'attente (le
	and.w	#$f8ff,sr			; jeu peut les avoir masquées) : STinG avance
	moveq	#1,d1				; avec Échap
	bsr	sting_connect
	move.w	(sp)+,sr
	tst.l	d0
	bne	.no
	move.w	#1,net_sting
	bra.s	.join
.ser:	tst.b	cfg_modem			; port série : modem éventuel, puis « CONNECT »
	beq.s	.join
	lea	cfg_modem,a0
	bsr	ser_puts
	lea	.cr(pc),a0
	bsr	ser_puts
	bsr	ser_connect
	tst.l	d0
	bne.s	.no
.join:	pea	net_state			; JOIN2
	NETCALL	0
	addq.l	#4,sp
.wait:	NETCALL	4				; net_poll
	tst.l	d0
	bmi.s	.no
	cmp.l	#NS_CONNECTED,d0
	beq.s	.ok
	move.l	game_base,a0			; Échap
	cmp.b	#$b3,G_KEYS+1(a0)
	bne.s	.wait
	bra.s	.no
.ok:	tst.l	NET_PARAMSOK(a6)		; physique imposée par le serveur : celle d'origine
	beq.s	.no
	move.w	#1,net_on
	moveq	#0,d0
	bra.s	.out
.no:	bsr	net_shut
	moveq	#-1,d0
.out:	movem.l	(sp)+,d1-d7/a0-a6
	rts
.cr:	dc.b	13,0
	even

; texte (a0) vers le port série (modem) ; superviseur
ser_puts:
	movem.l	d0-d2/a0-a3,-(sp)
	move.l	a0,a3
.l:	moveq	#0,d0
	move.b	(a3)+,d0
	beq.s	.out
.w:	move.w	d0,-(sp)
	move.w	#1,-(sp)
	aux	$55e				; Bcostat(1)
	addq.l	#2,sp
	move.w	(sp)+,d1
	tst.w	d0
	beq.s	.w0
	move.w	d1,-(sp)
	move.w	#1,-(sp)
	aux	$57e				; Bconout(1, octet)
	addq.l	#4,sp
	bra.s	.l
.w0:	move.w	d1,d0
	bra.s	.w
.out:	movem.l	(sp)+,d0-d2/a0-a3
	rts
; attend « CONNECT » du modem (30 s) ; d0 = 0 si reçu ; superviseur
ser_connect:
	movem.l	d1-d4/a0-a3,-(sp)
	move.l	$4ba.w,d4
	add.l	#6000,d4
	lea	.word(pc),a3
.l:	cmp.l	$4ba.w,d4
	blo.s	.no
	move.w	#1,-(sp)
	aux	$51e				; Bconstat(1)
	addq.l	#2,sp
	tst.w	d0
	beq.s	.l
	move.w	#1,-(sp)
	aux	$53e				; Bconin(1)
	addq.l	#2,sp
	cmp.b	(a3)+,d0
	beq.s	.n
	lea	.word(pc),a3
	bra.s	.l
.n:	tst.b	(a3)
	bne.s	.l
	moveq	#0,d0
	bra.s	.out
.no:	moveq	#-1,d0
.out:	movem.l	(sp)+,d1-d4/a0-a3
	rts
.word:	dc.b	"CONNECT",0
	even

; fin de la partie en ligne : BYE, connexion fermée ; superviseur
net_shut:
	movem.l	d0-d2/a0-a2,-(sp)
	tst.w	net_on
	beq.s	.n
	NETCALL	20				; net_bye
.n:	clr.w	net_on
	tst.w	net_sting
	beq.s	.s
	bsr	sting_close
	clr.w	net_sting
.s:	movem.l	(sp)+,d0-d2/a0-a2
	rts
; idem, depuis le mode utilisateur ou superviseur (fin du lanceur)
net_close:
	movem.l	d0-d2/a0-a2,-(sp)
	pea	net_shut(pc)
	move.w	#38,-(sp)			; Supexec
	trap	#14
	addq.l	#6,sp
	clr.b	net_online
	movem.l	(sp)+,d0-d2/a0-a2
	rts

; --------------------------------------------------------------- menu de départ du jeu
; « 1. Single Player League / 2. Multiplayer / 3. Computer Link » + « 4. Online Multiplayer »,
; comme la version PC : 4 entrées ($4BE3C : moveb #2,d2 -> #3), 4e texte $F0 dans la table du
; menu ($49218 + $10), affiché par l'impression du jeu ($47BA0 / $47BC6) depuis txt_online ; le
; choix est noté au retour du menu ($4BE44 : jsr $48D88). Le jeu envoie tout choix > 1 au
; Computer Link ($453B6) : le 4e y passe aussi, par le relais au lieu du port série.
online_patch:
	movem.l	d0/a0-a1,-(sp)
	move.l	game_base,a0
	cmp.l	#$143c0002,$4be3c-$10100(a0)	; moveb #2,d2
	bne	.no
	tst.b	$49218+$13-$10100(a0)		; 4e entrée libre
	bne	.no
	cmp.w	#$4a39,$47ba0-$10100(a0)	; tstb $4C0F1
	bne	.no
	lea	$4c0f1-$10100(a0),a1
	cmp.l	$47ba2-$10100(a0),a1
	bne	.no
	cmp.w	#$227c,$47bc6-$10100(a0)	; moveal #$4C0FB,a1
	bne	.no
	lea	$4c0fb-$10100(a0),a1
	cmp.l	$47bc8-$10100(a0),a1
	bne	.no
	cmp.w	#$4eb9,$4be44-$10100(a0)	; jsr $48D88
	bne	.no
	lea	$48d88-$10100(a0),a1
	cmp.l	$4be46-$10100(a0),a1
	bne	.no
	move.b	#3,$4be3f-$10100(a0)
	move.b	#TXT_ONLINE,$49218+$13-$10100(a0)
	move.w	#$4eb9,$47ba0-$10100(a0)
	move.l	#print_start,$47ba2-$10100(a0)
	move.w	#$4eb9,$47bc6-$10100(a0)
	move.l	#print_loop,$47bc8-$10100(a0)
	move.l	#menu_choice,$4be46-$10100(a0)
	bsr	flush_ic
.no:	movem.l	(sp)+,d0/a0-a1
	rts
TXT_ONLINE	equ	$f0
; au lieu de « tstb $4C0F1 » : texte demandé (d1) noté, drapeaux comme l'instruction d'origine
print_start:
	move.b	d1,txt_start
	move.l	a0,-(sp)
	move.l	game_base,a0
	tst.b	$4c0f1-$10100(a0)
	movea.l	(sp)+,a0			; (movea : drapeaux gardés)
	rts
; au lieu de « moveal #$4C0FB,a1 » (puis le jeu lit (a1,d1.w)) : texte $F0 = txt_online
print_loop:
	move.l	game_base,a1
	cmp.b	#TXT_ONLINE,txt_start
	bne.s	.orig
	tst.b	$4c0f1-$10100(a1)		; menu de départ seulement
	bpl.s	.orig
	move.l	d0,-(sp)
	lea	txt_online,a1			; a1 + d1.w = txt_online + (d1.b - $F0)
	moveq	#0,d0
	move.b	d1,d0
	sub.b	#TXT_ONLINE,d0
	add.l	d0,a1
	move.w	d1,d0
	ext.l	d0
	sub.l	d0,a1
	move.l	(sp)+,d0
	rts
.orig:	add.l	#$4c0fb-$10100,a1
	rts
; au lieu de « jsr $48D88 » au menu de départ : choix noté (3 : en ligne) ; toute partie en
; ligne précédente est finie
menu_choice:
	pea	.ret(pc)
	move.l	game_base,-(sp)
	add.l	#$48d88-$10100,(sp)
	rts					; menu du jeu, retour en .ret
.ret:	bsr	net_close
	cmp.b	#3,d0
	seq	net_online
	rts

; --------------------------------------------------------------- pendant le jeu
; trap #13 (BIOS) : après « 4. Online Multiplayer », le périphérique 1 (câble du jeu) va au relais ;
; sinon tout va au TOS (« 3. Computer Link » : vrai câble série, comme à l'origine)
net_trap13:
	tst.b	net_online
	beq.s	.tos
	move.l	a0,-(sp)
	lea	4+8(sp),a0			; arguments : après le cadre (format 0, 8 octets)
	btst	#5,4(sp)			; appel depuis le mode utilisateur : pile utilisateur
	bne.s	.sv
	move.l	usp,a0
.sv:	cmp.w	#1,2(a0)			; périphérique 1 ?
	bne	.tos0
	move.w	(a0),d0
	cmp.w	#1,d0
	beq	.stat
	cmp.w	#2,d0
	beq	.in
	cmp.w	#3,d0
	beq.s	.out
	cmp.w	#8,d0
	beq	.ostat
.tos0:	move.l	(sp)+,a0
.tos:	move.l	bios_vec,-(sp)			; TOS
	rts
.ostat:	move.l	(sp)+,a0			; Bcostat : toujours prêt
	moveq	#-1,d0
	rte
.out:	moveq	#0,d0				; Bconout(1, octet)
	move.w	4(a0),d0
	move.l	(sp)+,a0
	tst.w	net_on				; pas (ou plus) relié : octet perdu
	beq.s	.o1
	movem.l	d1-d2/a0-a1,-(sp)
	move.w	#1,net_busy
	move.l	d0,-(sp)
	NETCALL	8				; net_put (envoyé au prochain net_poll : lecture du
	addq.l	#4,sp				; câble par le jeu, ou VBL)
	clr.w	net_busy
	movem.l	(sp)+,d1-d2/a0-a1
.o1:	moveq	#-1,d0
	rte
.stat:	move.l	4(a0),d0			; Bconstat(1) ; d0 = retour du « jsr $4476E » du jeu
	move.l	(sp)+,a0
	movem.l	d1-d2/a0-a1,-(sp)
	move.l	game_base,a1
	lea	$453f2-$10100(a1),a1
	move.l	d0,d2
	sub.l	a1,d2				; 0 : test de $453EC (maître ou esclave ?)
	move.w	#1,net_busy
	tst.w	net_on
	bne.s	.st0
	tst.l	d2				; pas relié : la connexion se fait au test
	bne	.st3				; maître / esclave, jamais avant
	bsr	net_open
	tst.l	d0
	beq.s	.st0
	move.b	#1,net_reject			; échec ou Échap : un octet autre que $80, le
	bra.s	.st2				; jeu abandonne (« Link abandoned », menu)
.st0:	clr.w	net_el
	moveq	#0,d0
	move.b	$fffffa23.w,d0			; MFP, timer C (horloge 200 Hz du TOS)
	move.w	d0,net_tc
.st1:	tst.w	net_on
	beq.s	.st3
	NETCALL	4
	NETCALL	12				; net_avail
	tst.l	d0
	bne.s	.st2
; rien d'arrivé : on attend jusqu'à 0,7 ms, l'écart entre deux tests d'un 68000 à 8 MHz. Les
; délais d'attente du jeu ($447F0 : 3 tests par octet) sont des boucles de calcul, presque nulles sur
; 68060 : sans cela, un octet en route (paquet TCP coupé, port série) passerait pour perdu
	tst.l	d2
	beq.s	.sl
	bsr	tc_step
	cmp.w	#27,net_el			; 27 x 26 µs
	blo.s	.st1
	bra.s	.st3
; esclave : au test « octet reçu ? » qui suit le vidage du tampon ($453B6 -> $453EC), le jeu ne
; doit pas se croire maître : il attend le premier octet du maître (comme la version PC, qui retient
; son jeu à cet endroit) ; Échap rend la main
.sl:	tst.l	net_state+NET_MASTER
	bne.s	.st3
	tst.l	net_state+NET_STATE
	bmi.s	.st3
	move.l	game_base,a0
	cmp.b	#$b3,G_KEYS+1(a0)
	bne.s	.st1
	move.b	#1,net_reject
.st2:	moveq	#-1,d0
	bra.s	.st4
.st3:	moveq	#0,d0
.st4:	clr.w	net_busy
	movem.l	(sp)+,d1-d2/a0-a1
	rte
.in:	move.l	(sp)+,a0			; Bconin(1) : attend un octet
	movem.l	d1-d2/a0-a1,-(sp)
	moveq	#0,d0
	tst.b	net_reject			; refus (voir plus haut) : 0 au lieu de $80
	beq.s	.in0
	clr.b	net_reject
	bsr	net_shut
	bra.s	.in3
.in0:	move.w	#1,net_busy
.in1:	tst.w	net_on				; liaison perdue : 0
	beq.s	.in2
	NETCALL	4
	NETCALL	16				; net_get
	tst.l	d0
	bpl.s	.in2
	tst.l	net_state+NET_STATE
	bpl.s	.in1
	moveq	#0,d0
.in2:	clr.w	net_busy
.in3:	movem.l	(sp)+,d1-d2/a0-a1
	rte

; temps écoulé (net_el, en périodes de 26 µs du timer C : 192 par 5 ms)
tc_step:
	moveq	#0,d0
	move.b	$fffffa23.w,d0
	move.w	net_tc,d1
	move.w	d0,net_tc
	sub.w	d0,d1				; le compteur descend de 192 à 1
	bpl.s	.p
	add.w	#192,d1
.p:	add.w	d1,net_el
	rts

; trap #14 (XBIOS) : le jeu règle le port série à 9600 bauds avant le Computer Link ($4483E,
; Rsconf) ; en ligne (4e choix), le port (transport série) reste réglé pour le relais
net_trap14:
	tst.b	net_online
	beq.s	.tos
	move.l	a0,-(sp)
	lea	4+8(sp),a0
	btst	#5,4(sp)
	bne.s	.sv
	move.l	usp,a0
.sv:	cmp.w	#15,(a0)			; Rsconf
	bne.s	.tos0
	move.l	(sp)+,a0
	moveq	#-1,d0
	rte
.tos0:	move.l	(sp)+,a0
.tos:	move.l	xbios_vec,-(sp)
	rts

; VBL : réponses aux PING de l'adversaire même quand le jeu ne lit pas le câble (menus,
; chargement) ; jamais pendant un appel du jeu au câble (STinG n'est pas réentrant)
net_vbl:
	tst.w	net_on
	beq.s	.out
	tst.w	net_busy
	bne.s	.out
	movem.l	d0-d2/a0-a1,-(sp)
	move.w	#1,net_busy
	NETCALL	4
	clr.w	net_busy
	movem.l	(sp)+,d0-d2/a0-a1
.out:	rts

	data
txt_online:
	dc.b	"Online Multiplayer",$ff
	even
txt_on1:
	dc.b	"4. Online Multiplayer (relais v45) : ",0
txt_on_nost:
	dc.b	"STinG absent (cookie STiK).",13,10,0
txt_on_srv:
	dc.b	"carte reseau (STinG)",13,10,"  serveur : ",0
txt_on_off:
	dc.b	"serveur officiel",0
txt_on_dns:
	dc.b	"  adresse du serveur introuvable (DNS de STinG ?) : ",0
txt_on_tcp:
	dc.b	"  connexion au serveur impossible : ",0
txt_on_ok:
	dc.b	"  serveur joignable.",13,10,0
txt_on_ko:
	dc.b	"  (le jeu en ligne donnera Link abandoned)",13,10,0
	even
	section	netblob,data
net_blob:	incbin	"../net/net.bin"
		even
net_rel:	include	"../net/netrel.s"
	text

	bss
net_on:		ds.w	1			; relié à l'adversaire
net_serial:	ds.w	1
net_online:	ds.b	1			; 4e choix du menu de départ
net_reject:	ds.b	1
txt_start:	ds.b	1
		even
xbios_vec:	ds.l	1
net_busy:	ds.w	1
net_sting:	ds.w	1
net_port:	ds.w	1
sting_cn:	ds.w	1
sting_tpl:	ds.l	1
bios_vec:	ds.l	1
net_tc:		ds.w	1
net_el:		ds.w	1
net_ip:		ds.l	1
net_io:		ds.l	4
net_cfg:
cfg_name:	ds.b	16
cfg_room:	ds.b	16
cfg_relay:	ds.b	64
cfg_transport:	ds.b	8
cfg_modem:	ds.b	64
cfg_hash:	ds.b	12
net_host:	ds.b	68
		even
net_state:	ds.b	NET_BYTES
	text

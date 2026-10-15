; ---------------------------------------------------------------------------
; online.s - multijoueur en ligne de SCRCT60 (inclus par scrf030.s, -DCT60=1)
;
; Le jeu d'origine relie deux machines par le câble série (« 3. Computer Link ») et n'y accède
; que par le BIOS, périphérique 1 (Bconstat, Bconin, Bconout : docs/RETRO_INGENIERIE.md §10). Ici
; ces appels sont détournés (trap #13, par la table des vecteurs déplacée) vers le serveur relais
; de la version PC v45 : les octets du câble partent dans des trames DATA, comme le fait la version
; PC (native/src/net.cpp). Protocole dans falcon/net/net.c (C, relogé ici).
;
; Transport : STinG (cookie « STiK » : STinG sous TOS, GlueSTiK sous MiNT ; carte réseau de la
; CT60), ou flux brut sur le port série (modem WiFi, passerelle PC, essais sous Hatari).
; Configuration : lettre L sur la première ligne de SCRCT60.INF, puis des lignes
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

; nom ou adresse (net_host) -> connexion TCP sur net_port ; d0 = 0 si établie
sting_open:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	sting_tpl,a5
	move.w	#1,-(sp)			; resolve(nom, NULL, &adresse, 1)
	pea	net_ip
	clr.l	-(sp)
	pea	net_host
	move.l	TPL_RESOLVE(a5),a0
	jsr	(a0)
	lea	14(sp),sp
	tst.w	d0
	ble.s	.err
	move.w	#2048,-(sp)			; TCP_open(adresse, port, 0, 2048)
	clr.w	-(sp)
	move.w	net_port,-(sp)
	move.l	net_ip,-(sp)
	move.l	TPL_TCP_OPEN(a5),a0
	jsr	(a0)
	lea	10(sp),sp
	tst.w	d0
	bmi.s	.err
	move.w	d0,sting_cn
	move.w	#20,-(sp)			; TCP_wait_state(cn, TESTABLISH, 20 s)
	move.w	#4,-(sp)
	move.w	sting_cn,-(sp)
	move.l	TPL_TCP_WAIT(a5),a0
	jsr	(a0)
	addq.l	#6,sp
	tst.w	d0
	bne.s	.err
	moveq	#0,d0
	bra.s	.out
.err:	moveq	#-1,d0
.out:	movem.l	(sp)+,d2-d7/a2-a6
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
; BIOS, périphérique 1 : trap #13 marqué « interne » (net_inside), que notre détournement
; laisse passer au TOS
bios	macro					; fonction \1 (arguments déjà empilés, sauf la fonction)
	move.w	#\1,-(sp)
	addq.w	#1,net_inside
	trap	#13
	subq.w	#1,net_inside
	endm
se_send:					; (p, n) : envoie tout ce que le port accepte
	movem.l	d2-d4/a2-a3,-(sp)		; le TOS peut détruire d0-d2/a0-a2
	move.l	20+4(sp),a3
	move.l	20+8(sp),d4
	moveq	#0,d3
.l:	cmp.l	d4,d3
	bhs.s	.out
	move.w	#1,-(sp)			; Bcostat(1)
	bios	8
	addq.l	#4,sp
	tst.w	d0
	beq	.out
	moveq	#0,d0
	move.b	(a3,d3.l),d0
	move.w	d0,-(sp)			; Bconout(1, octet)
	move.w	#1,-(sp)
	bios	3
	addq.l	#6,sp
	addq.l	#1,d3
	bra.s	.l
.out:	move.l	d3,d0
	movem.l	(sp)+,d2-d4/a2-a3
	rts
se_avail:
	movem.l	d2/a2,-(sp)			; le TOS peut détruire d0-d2/a0-a2
	move.w	#1,-(sp)			; Bconstat(1) : -1 si un octet attend
	bios	1
	addq.l	#4,sp
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
	bios	1
	addq.l	#4,sp
	tst.w	d0
	beq.s	.out
	move.w	#1,-(sp)			; Bconin(1)
	bios	2
	addq.l	#4,sp
	move.b	d0,(a3,d3.l)
	addq.l	#1,d3
	bra.s	.l
.out:	move.l	d3,d0
	movem.l	(sp)+,d2-d4/a2-a3
	rts
io_ms:	move.l	$4ba.w,d0			; horloge 200 Hz -> millisecondes
	mulu.l	#5,d0
	rts

; --------------------------------------------------------------- connexion (avant le jeu)
; d0 = 0 : relié à l'adversaire ; sinon, partie seule (message affiché)
net_connect:
	movem.l	d1-d7/a0-a6,-(sp)
	lea	txt_net1(pc),a0
	bsr	print
	pea	.sup(pc)			; vecteur BIOS du TOS, horloge, STinG
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
	move.l	#$b1f6578d,d0			; empreinte du jeu étudié (scr_tool.py la réécrit)
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
	lea	txt_neto(pc),a0
	bra.s	.pr
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
	lea	net_host,a0
.pr:	move.l	a0,-(sp)
	lea	txt_net2(pc),a0
	bsr	print
	move.l	(sp)+,a0
	bsr	print
	lea	txt_crlf(pc),a0
	bsr	print
; transport
	cmp.b	#'s',cfg_transport		; « serie » (sinon STinG)
	bne.s	.st
	cmp.b	#'e',cfg_transport+1
	beq	.serial
.st:	tst.l	sting_tpl
	bne.s	.st1
	lea	txt_nost(pc),a0
	bra	.fail
.st1:	pea	sting_open(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	tst.l	d0
	beq.s	.st2
	lea	txt_notcp(pc),a0
	bra	.fail
.st2:	move.w	#1,net_sting
	lea	net_io,a0
	move.l	#st_send,(a0)+
	move.l	#st_avail,(a0)+
	move.l	#st_get,(a0)+
	move.l	#io_ms,(a0)
	bra.s	.join
.serial:
	lea	net_io,a0
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
	tst.b	cfg_modem			; modem : commande puis « CONNECT »
	beq.s	.join
	lea	cfg_modem,a0
	bsr	ser_puts
	move.w	#13,-(sp)
	move.w	#1,-(sp)
	move.w	#3,-(sp)
	trap	#13
	addq.l	#6,sp
	bsr	ser_connect
	tst.l	d0
	beq.s	.join
	lea	txt_nomodem(pc),a0
	bra	.fail
; inscription, attente de l'adversaire, poignée de main
.join:	pea	.start(pc)			; net_start (superviseur : horloge $4BA)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	clr.l	net_shown
.wait:	bsr	net_super_poll
	move.l	NET_STATE(a6),d7
	lea	NET_TEXT(a6),a0			; état affiché quand il change
	move.l	(a0),d0
	cmp.l	net_shown,d0
	beq.s	.same
	move.l	d0,net_shown
	move.l	a0,-(sp)
	lea	txt_netin(pc),a0
	bsr	print
	move.l	(sp)+,a0
	bsr	print
	lea	txt_crlf(pc),a0
	bsr	print
.same:	tst.l	d7
	bmi	.failed
	cmp.l	#NS_CONNECTED,d7
	beq.s	.ok
	move.w	#2,-(sp)			; Échap : partie seule
	move.w	#1,-(sp)			; Bconstat(2)
	trap	#13
	addq.l	#4,sp
	tst.w	d0
	beq.s	.wait
	move.w	#2,-(sp)
	move.w	#2,-(sp)			; Bconin(2)
	trap	#13
	addq.l	#4,sp
	cmp.b	#27,d0
	bne.s	.wait
	lea	txt_netesc(pc),a0
	bra.s	.fail0
.ok:	tst.l	NET_PARAMSOK(a6)
	bne.s	.ok2
	lea	txt_netparams(pc),a0
	bra.s	.fail0
.ok2:	lea	txt_netok(pc),a0		; relié : rôle et adversaire
	bsr	print
	lea	NET_PEER(a6),a0
	bsr	print
	lea	txt_netm(pc),a0
	tst.l	NET_MASTER(a6)
	bne.s	.m
	lea	txt_nets(pc),a0
.m:	bsr	print
	move.w	#1,net_on
	moveq	#100-1,d3			; 2 s pour lire
.w2:	move.w	#37,-(sp)
	trap	#14
	addq.l	#2,sp
	dbf	d3,.w2
	moveq	#0,d0
	bra.s	.out
.failed:
	lea	NET_TEXT(a6),a0
.fail:	move.l	a0,-(sp)
	lea	txt_netfail(pc),a0
	bsr	print
	move.l	(sp)+,a0
	bsr	print
	lea	txt_crlf(pc),a0
.fail0:	bsr	print
	lea	txt_netsolo(pc),a0
	bsr	print
	bsr	wait_key
	bsr	net_close
	moveq	#-1,d0
.out:	movem.l	(sp)+,d1-d7/a0-a6
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
	bsr	sting_find
	rts
.start:	pea	net_state
	NETCALL	0
	addq.l	#4,sp
	rts
.offi:	dc.b	$37,$06,$07,$e2,$ef,$e9,$c9,$d1,$a7,$e1,$bf,$8a
	even

; texte (a0) vers le port série (modem)
ser_puts:
	movem.l	d0-d2/a0-a3,-(sp)
	move.l	a0,a3
.l:	moveq	#0,d0
	move.b	(a3)+,d0
	beq.s	.out
	move.w	d0,-(sp)
	move.w	#1,-(sp)
	move.w	#3,-(sp)			; Bconout(1)
	trap	#13
	addq.l	#6,sp
	bra.s	.l
.out:	movem.l	(sp)+,d0-d2/a0-a3
	rts
; attend « CONNECT » du modem (30 s) ; d0 = 0 si reçu
ser_connect:
	movem.l	d1-d4/a0-a3,-(sp)
	bsr	hz200
	move.l	d0,d4
	add.l	#6000,d4
	lea	.word(pc),a3
.l:	bsr	hz200
	cmp.l	d4,d0
	bhi.s	.no
	move.w	#1,-(sp)
	move.w	#1,-(sp)			; Bconstat(1)
	trap	#13
	addq.l	#4,sp
	tst.w	d0
	beq.s	.l
	move.w	#1,-(sp)
	move.w	#2,-(sp)			; Bconin(1)
	trap	#13
	addq.l	#4,sp
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
; horloge 200 Hz ($4BA, lisible en superviseur seulement) -> d0
hz200:	movem.l	d1-d2/a0-a2,-(sp)
	pea	.r(pc)
	move.w	#38,-(sp)			; Supexec
	trap	#14
	addq.l	#6,sp
	movem.l	(sp)+,d1-d2/a0-a2
	rts
.r:	move.l	$4ba.w,d0
	rts

; net_poll en superviseur (STinG et BIOS appelés comme pendant le jeu)
net_super_poll:
	pea	.p(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	rts
.p:	NETCALL	4
	rts

; fin : BYE et fermeture (superviseur ou utilisateur)
net_close:
	movem.l	d0-d2/a0-a2,-(sp)
	pea	.c(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	clr.w	net_on
	movem.l	(sp)+,d0-d2/a0-a2
	rts
.c:	tst.w	net_on
	beq.s	.n
	NETCALL	20				; net_bye
.n:	tst.w	net_sting
	beq.s	.s
	bsr	sting_close
	clr.w	net_sting
.s:	rts

; --------------------------------------------------------------- pendant le jeu
; trap #13 (BIOS) : périphérique 1 (câble du jeu) vers le réseau, le reste au TOS
net_trap13:
	tst.w	net_inside			; nos propres appels (port série) : au TOS
	bne.s	.tos
	tst.w	net_on
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
	movem.l	d1-d2/a0-a1,-(sp)
	move.w	#1,net_busy
	move.l	d0,-(sp)
	NETCALL	8				; net_put (envoyé au prochain net_poll : lecture du
	addq.l	#4,sp				; câble par le jeu, ou VBL)
	clr.w	net_busy
	movem.l	(sp)+,d1-d2/a0-a1
	moveq	#-1,d0
	rte
.stat:	move.l	4(a0),d0			; Bconstat(1) ; d0 = retour du « jsr $4476E » du jeu
	move.l	(sp)+,a0
	movem.l	d1-d2/a0-a1,-(sp)
	move.l	game_base,a1
	lea	$453f2-$10100(a1),a1
	move.l	d0,d2
	sub.l	a1,d2				; 0 : test de $453EC (maître ou esclave ?)
	move.w	#1,net_busy
	clr.w	net_el
	moveq	#0,d0
	move.b	$fffffa23.w,d0			; MFP, timer C (horloge 200 Hz du TOS)
	move.w	d0,net_tc
.st1:	NETCALL	4
	NETCALL	12				; net_avail
	tst.l	d0
	bne.s	.st2
; rien d'arrivé : on attend jusqu'à 0,7 ms, l'écart entre deux tests d'un 68000 à 8 MHz. Les
; délais d'attente du jeu ($447F0 : 3 tests par octet) sont des boucles de calcul, presque nulles sur
; 68060 : sans cela, un octet en route (port série, paquet TCP coupé) passerait pour perdu
	tst.l	d2
	beq.s	.sl
	bsr	tc_step
	cmp.w	#27,net_el			; 27 x 26 µs
	blo.s	.st1
	bra.s	.st3
.sl:
; esclave : au test « octet reçu ? » qui suit le vidage du tampon ($453B6 -> $453EC), le jeu ne
; doit pas se croire maître : il attend le premier octet du maître (comme la version PC, qui retient
; son jeu à cet endroit) ; Échap rend la main
	tst.l	d2
	bne.s	.st3
	tst.l	net_state+NET_MASTER
	bne.s	.st3
	tst.l	net_state+NET_STATE
	bmi.s	.st3
	move.l	game_base,a0
	cmp.b	#$b3,G_KEYS+1(a0)
	beq.s	.st3
	bra.s	.st1
.st2:	moveq	#-1,d0
	bra.s	.st4
.st3:	moveq	#0,d0
.st4:	clr.w	net_busy
	movem.l	(sp)+,d1-d2/a0-a1
	rte
.in:	move.l	(sp)+,a0			; Bconin(1) : attend un octet
	movem.l	d1-d2/a0-a1,-(sp)
	move.w	#1,net_busy
.in1:	NETCALL	4
	NETCALL	16				; net_get
	tst.l	d0
	bpl.s	.in2
	tst.l	net_state+NET_STATE		; liaison perdue : 0
	bpl.s	.in1
	moveq	#0,d0
.in2:	clr.w	net_busy
	movem.l	(sp)+,d1-d2/a0-a1
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

; VBL : réponses aux PING de l'adversaire même quand le jeu ne lit pas le câble (menus,
; chargement) ; jamais pendant un appel du jeu au câble (STinG n'est pas réentrant)
net_vbl:
	tst.w	net_on
	beq.s	.out
	tst.w	net_busy
	bne.s	.out
; jamais dans un appel au système : le pilote du port série (ou STinG) n'est pas réentrant. Le
; PC interrompu (cadre de vbl_hook, après notre adresse de retour) doit être dans le jeu, ou,
; avant que le jeu soit reconnu (chargement), hors de la ROM du TOS
	move.l	d0,-(sp)
	move.l	4+4+2(sp),d0
	tst.w	game_ok
	beq.s	.ld
	sub.l	game_base,d0			; dans le jeu ($10100 à $70100)
	cmp.l	#$60000,d0
	bhs.s	.skip
	bra.s	.go
.ld:	cmp.l	#$e00000,d0			; ROM du TOS : $E00000 à $EFFFFF
	blo.s	.go
	cmp.l	#$f00000,d0
	blo.s	.skip
.go:	move.l	(sp)+,d0
	movem.l	d0-d2/a0-a1,-(sp)
	move.w	#1,net_busy
	NETCALL	4
	clr.w	net_busy
	movem.l	(sp)+,d0-d2/a0-a1
.out:	rts
.skip:	move.l	(sp)+,d0
	rts

	data
txt_net1:
	dc.b	13,10,"Multijoueur en ligne (Computer Link par le relais v45)",13,10,0
txt_net2:
	dc.b	"Serveur : ",0
txt_neto:
	dc.b	"serveur officiel",0
txt_netin:
	dc.b	"  ",0
txt_nost:
	dc.b	"STinG absent (cookie STiK) : installez STinG ou mettez transport = serie",0
txt_notcp:
	dc.b	"connexion TCP au serveur impossible (STinG)",0
txt_nomodem:
	dc.b	"le modem n'a pas repondu CONNECT",0
txt_netfail:
	dc.b	"Echec : ",0
txt_netesc:
	dc.b	"Abandon (Echap).",13,10,0
txt_netparams:
	dc.b	"Le serveur impose une physique modifiee : impossible sur Falcon.",13,10,0
txt_netsolo:
	dc.b	"Partie sans reseau. Une touche...",13,10,0
txt_netok:
	dc.b	"Relie a ",0
txt_netm:
	dc.b	" : vous etes le maitre (vous menez les menus).",13,10
	dc.b	"Dans le jeu : 3. Computer Link.",13,10,0
txt_nets:
	dc.b	" : il mene les menus.",13,10
	dc.b	"Dans le jeu : 3. Computer Link.",13,10,0
	even
	section	netblob,data
net_blob:	incbin	"../net/net.bin"
		even
net_rel:	include	"../net/netrel.s"
	text

	bss
net_on:		ds.w	1
net_inside:	ds.w	1
net_busy:	ds.w	1
net_sting:	ds.w	1
net_port:	ds.w	1
sting_cn:	ds.w	1
sting_tpl:	ds.l	1
bios_vec:	ds.l	1
net_tc:		ds.w	1
net_el:		ds.w	1
net_ip:		ds.l	1
net_shown:	ds.l	1
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

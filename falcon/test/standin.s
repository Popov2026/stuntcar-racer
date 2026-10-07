; ---------------------------------------------------------------------------
; standin.s - « doublure » de GAME.PUT pour tester SCRF030 sous Hatari sans
; les données du jeu.
;
; Fait ce que fait Stunt Car Racer avec la machine (docs/RETRO_INGENIERIE.md) :
; démarrage en mode utilisateur puis Super, Physbase, palette écrite en $FF8240,
; VBL détournée en $70, clavier en $118 (ACIA), double tampon par écriture de
; $FF8201/$FF8203, registres du YM2149, et en plus :
;   * « move sr » en mode utilisateur (privilégiée sur 68030) ;
;   * code modifié puis exécuté (piège du cache d'instructions du 68030) ;
;   * cadence de la VBL mesurée avec l'horloge 200 Hz du TOS (le jeu attend 50).
;
; Les octets reçus de l'IKBD par le gestionnaire $118 sont comptés (kbd=).
; Résultats écrits sur la console de Hatari (NatFeats, option --natfeats on).
;
; vasmm68k_mot -Ftos -m68030 -devpac -nosym -o GAME.PUT standin.s
; ---------------------------------------------------------------------------

FRAMES		equ	150			; images dessinées (3 s à 50 Hz)

	text

start:	move.l	4(sp),a5
	lea	ustack_top,sp
	move.l	$0c(a5),d0
	add.l	$14(a5),d0
	add.l	$1c(a5),d0
	add.l	#$100,d0
	move.l	d0,-(sp)
	move.l	a5,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)			; Mshrink
	trap	#1
	lea	12(sp),sp

; 1. « move sr » en mode utilisateur, comme un programme 68000
	moveq	#-1,d3
	move.w	sr,d3				; privilégiée sur 68010+
	move.l	d3,sr_dn
	move.w	#$1234,-(sp)
	move.w	sr,-(sp)
	move.w	(sp)+,sr_predec
	move.w	(sp)+,sr_guard			; doit rester $1234

; 2. superviseur (le jeu appelle Super)
	clr.l	-(sp)
	move.w	#$20,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,old_ssp

	bsr	nf_init

	movec	cacr,d0
	move.l	d0,r_cacr
	movec	vbr,d0
	move.l	d0,r_vbr
	move.b	$ffff8007.w,r_busctrl+1
	move.w	$ffff82c2.w,r_vco		; VIDEL : doublement de ligne...
	move.b	$ffff8260.w,r_shiftmode+1
	move.b	$ff.w,r_byteff+1		; octet lu par la physique du jeu ($49718)

; 3. code modifié puis exécuté
	lea	smc_buf,a0
	move.l	#$70014e75,(a0)			; moveq #1,d0 ; rts
	jsr	(a0)
	move.l	#$70024e75,(a0)			; moveq #2,d0 ; rts
	jsr	(a0)
	move.w	d0,smc_result			; 2 attendu ; 1 = instruction périmée en cache

; 4. écrans : celui du TOS + un second aligné sur 256 octets
	move.w	#2,-(sp)			; Physbase
	trap	#14
	addq.l	#2,sp
	move.l	d0,screen1
	move.l	#screen2_mem+255,d0
	and.l	#$ffffff00,d0
	move.l	d0,screen2

	lea	$ffff8240.w,a0			; palette écrite directement
	lea	palette,a1
	moveq	#16-1,d0
.pal:	move.w	(a1)+,(a0)+
	dbf	d0,.pal

	move.b	#7,$ffff8800.w			; YM : mixeur, voie A en son
	move.b	#%11111110,$ffff8802.w
	move.b	#0,$ffff8800.w
	move.b	#$80,$ffff8802.w
	move.b	#8,$ffff8800.w
	move.b	#0,$ffff8802.w			; volume nul

; 5. vecteurs détournés comme le jeu
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	$70.w,old_vbl
	move.l	$118.w,old_kbd
	move.l	#vbl,$70.w
	move.l	#kbd,$118.w
	move.w	(sp)+,sr

; 6. cadence de la VBL pendant 200 ticks de 200 Hz (une seconde)
	move.l	$4ba.w,d0
.sync:	cmp.l	$4ba.w,d0
	beq.s	.sync
	move.l	$4ba.w,d1
	move.l	vbl_count,d2
	add.l	#200,d1
.wait:	cmp.l	$4ba.w,d1
	bhi.s	.wait
	move.l	vbl_count,d0
	sub.l	d2,d0
	move.l	d0,vbl_per_sec

; 7. animation en double tampon : on dessine dans l'écran caché puis on l'affiche
	clr.w	frame
.loop:	move.l	screen2,a0
	btst	#0,frame+1
	beq.s	.b2
	move.l	screen1,a0
.b2:	move.l	a0,draw_screen
	bsr	draw_frame
	move.l	draw_screen,d0			; affiché à la prochaine VBL
	lsr.l	#8,d0
	move.b	d0,$ffff8203.w
	lsr.w	#8,d0
	move.b	d0,$ffff8201.w
	move.l	vbl_count,d0
.vs:	cmp.l	vbl_count,d0
	beq.s	.vs
	addq.w	#1,frame
	cmp.w	#FRAMES,frame
	blo.s	.loop

; 8. adresse vidéo lue en retour (les 3 octets du VIDEL)
	moveq	#0,d0
	move.b	$ffff8201.w,d0
	swap	d0
	move.b	$ffff8203.w,d0
	lsl.w	#8,d0
	move.b	$ffff820d.w,d0
	move.l	d0,r_vbase

	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	old_vbl,$70.w
	move.l	old_kbd,$118.w
	move.w	(sp)+,sr
	move.l	screen1,d0			; écran du TOS rendu
	lsr.l	#8,d0
	move.b	d0,$ffff8203.w
	lsr.w	#8,d0
	move.b	d0,$ffff8201.w

	bsr	report

	move.l	old_ssp,-(sp)
	move.w	#$20,-(sp)
	trap	#1
	addq.l	#6,sp
	clr.w	-(sp)
	trap	#1

; ---------------------------------------------------------------------------
vbl:	addq.l	#1,vbl_count
	rte

kbd:	move.w	d0,-(sp)
.l:	btst	#0,$fffffc00.w			; octet reçu ?
	beq.s	.d
	move.b	$fffffc02.w,d0
	addq.l	#1,kbd_bytes
	bra.s	.l
.d:	bclr	#6,$fffffa11.w			; fin d'interruption MFP (ACIA)
	move.w	(sp)+,d0
	rte

; bandes des 16 couleurs, et un bloc blanc qui avance d'un groupe de 16 pixels par image
draw_frame:
	move.l	draw_screen,a0
	moveq	#0,d5				; couleur
.band:	moveq	#12-1,d6			; 12 lignes par bande (192 lignes)
.line:	moveq	#20-1,d7
.grp:	moveq	#0,d0
	btst	#0,d5
	beq.s	.p0
	not.w	d0
.p0:	move.w	d0,(a0)+
	moveq	#0,d0
	btst	#1,d5
	beq.s	.p1
	not.w	d0
.p1:	move.w	d0,(a0)+
	moveq	#0,d0
	btst	#2,d5
	beq.s	.p2
	not.w	d0
.p2:	move.w	d0,(a0)+
	moveq	#0,d0
	btst	#3,d5
	beq.s	.p3
	not.w	d0
.p3:	move.w	d0,(a0)+
	dbf	d7,.grp
	dbf	d6,.line
	addq.w	#1,d5
	cmp.w	#16,d5
	blo.s	.band
	move.w	#8*160/4-1,d0			; 8 dernières lignes noires
.clr:	clr.l	(a0)+
	dbf	d0,.clr
; bloc 16x16 en couleur 15 (bandes 2 et 3), position = image modulo 20
	moveq	#0,d0
	move.w	frame,d0
	divu	#20,d0
	swap	d0				; reste
	lsl.w	#3,d0
	move.l	draw_screen,a0
	add.w	d0,a0
	lea	24*160(a0),a0
	moveq	#16-1,d1
.blk:	move.l	#-1,(a0)
	move.l	#-1,4(a0)
	lea	160(a0),a0
	dbf	d1,.blk
	rts

; ---------------------------------------------------------------------------
; compte rendu sur la console de Hatari
report:
	lea	txtbuf,a1
	lea	t_head,a0
	bsr	cat
	lea	t_srdn,a0
	bsr	cat
	move.l	sr_dn,d0
	bsr	hex8
	lea	t_srsp,a0
	bsr	cat
	move.w	sr_predec,d0
	bsr	hex4
	lea	t_guard,a0
	bsr	cat
	move.w	sr_guard,d0
	bsr	hex4
	lea	t_smc,a0
	bsr	cat
	move.w	smc_result,d0
	bsr	dec
	lea	t_vbl,a0
	bsr	cat
	move.l	vbl_per_sec,d0
	bsr	dec
	lea	t_frames,a0
	bsr	cat
	move.w	frame,d0
	bsr	dec
	lea	t_kbd,a0
	bsr	cat
	move.l	kbd_bytes,d0
	bsr	dec
	lea	t_cacr,a0
	bsr	cat
	move.l	r_cacr,d0
	bsr	hex8
	lea	t_vbr,a0
	bsr	cat
	move.l	r_vbr,d0
	bsr	hex8
	lea	t_bus,a0
	bsr	cat
	move.w	r_busctrl,d0
	bsr	hex4
	lea	t_shift,a0
	bsr	cat
	move.w	r_shiftmode,d0
	bsr	hex4
	lea	t_vco,a0
	bsr	cat
	move.w	r_vco,d0
	bsr	hex4
	lea	t_byteff,a0
	bsr	cat
	move.w	r_byteff,d0
	bsr	hex4
	lea	t_vbase,a0
	bsr	cat
	move.l	r_vbase,d0
	bsr	hex8
	lea	t_scr,a0
	bsr	cat
	move.l	screen1,d0
	bsr	hex8
	lea	t_scr2,a0
	bsr	cat
	move.l	screen2,d0
	bsr	hex8
	lea	t_end,a0
	bsr	cat
	clr.b	(a1)
	pea	txtbuf
	bsr	nf_stderr
	addq.l	#4,sp
	rts

cat:	move.b	(a0)+,(a1)+
	bne.s	cat
	subq.l	#1,a1
	rts

hex8:	swap	d0
	bsr.s	hex4
	swap	d0
hex4:	moveq	#4-1,d2
.h:	rol.w	#4,d0
	moveq	#$f,d1
	and.w	d0,d1
	move.b	hexdig(pc,d1.w),(a1)+
	dbf	d2,.h
	rts
hexdig:	dc.b	"0123456789ABCDEF"

dec:	and.l	#$ffff,d0			; 0..65535
	lea	decbuf+6,a2
	clr.b	-(a2)
.d:	divu	#10,d0
	swap	d0
	add.b	#'0',d0
	move.b	d0,-(a2)
	clr.w	d0
	swap	d0
	tst.w	d0
	bne.s	.d
.c:	move.b	(a2)+,(a1)+
	bne.s	.c
	subq.l	#1,a1
	rts

; ---------------------------------------------------------------------------
; NatFeats (superviseur)
nf_init:
	move.l	sp,a1
	move.l	$10.w,a0
	move.l	#.fail,$10.w
	pea	nf_name_stderr
	subq.l	#4,sp
	dc.w	$7300				; NF_ID
	move.l	d0,nf_id_stderr
.fail:	move.l	a1,sp
	move.l	a0,$10.w
	rts

nf_stderr:					; 4(sp) = chaîne
	move.l	nf_id_stderr,d0
	beq.s	.no
	move.l	4(sp),-(sp)
	move.l	d0,-(sp)
	subq.l	#4,sp				; place de l'adresse de retour
	dc.w	$7301				; NF_CALL
	lea	12(sp),sp
.no:	rts

; ---------------------------------------------------------------------------
	data
palette:
	dc.w	$000,$700,$070,$770,$007,$707,$077,$555
	dc.w	$333,$733,$373,$773,$337,$737,$377,$777
nf_name_stderr:
	dc.b	"NF_STDERR",0
t_head:	dc.b	"STANDIN",0
t_srdn:	dc.b	" sr_dn=",0
t_srsp:	dc.b	" sr_predec=",0
t_guard: dc.b	" guard=",0
t_smc:	dc.b	" smc=",0
t_vbl:	dc.b	" vbl_per_sec=",0
t_frames: dc.b	" frames=",0
t_kbd:	dc.b	" kbd=",0
t_cacr:	dc.b	" cacr=",0
t_vbr:	dc.b	" vbr=",0
t_bus:	dc.b	" ff8007=",0
t_shift: dc.b	" ff8260=",0
t_vco:	dc.b	" ff82c2=",0
t_byteff: dc.b	" byte_ff=",0
t_vbase: dc.b	" vbase=",0
t_scr:	dc.b	" screen1=",0
t_scr2:	dc.b	" screen2=",0
t_end:	dc.b	10,0
	even

	bss
old_ssp:	ds.l	1
sr_dn:		ds.l	1
sr_predec:	ds.w	1
sr_guard:	ds.w	1
smc_result:	ds.w	1
r_cacr:		ds.l	1
r_vbr:		ds.l	1
r_busctrl:	ds.w	1
r_shiftmode:	ds.w	1
r_vco:		ds.w	1
r_byteff:	ds.w	1
r_vbase:	ds.l	1
nf_id_stderr:	ds.l	1
screen1:	ds.l	1
screen2:	ds.l	1
draw_screen:	ds.l	1
old_vbl:	ds.l	1
old_kbd:	ds.l	1
vbl_count:	ds.l	1
kbd_bytes:	ds.l	1
vbl_per_sec:	ds.l	1
frame:		ds.w	1
smc_buf:	ds.l	4
decbuf:		ds.b	8
txtbuf:		ds.b	512
		ds.l	256
ustack_top:	ds.l	1
screen2_mem:	ds.b	32000+256

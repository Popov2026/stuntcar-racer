; ---------------------------------------------------------------------------
; SCRF030 - Stunt Car Racer sur Atari Falcon030
;
; Lanceur qui prépare le Falcon (mode ST compatible) puis exécute le jeu
; d'origine GAME.PUT, sans le modifier :
;
;  * mode vidéo VIDEL « ST basse » 320x200 16 couleurs (RVB, TV ou VGA),
;    sur un écran à nous de 32 Ko (comme en haut de la RAM d'un ST : le chargeur
;    JEK de GAME.PUT se sert de écran+$7F00), mode et palettes rétablis au retour ;
;  * caches du 68030 coupés : le jeu est décompressé puis relogé en mémoire
;    avant d'être exécuté (et le code issu du 6502 peut se modifier lui-même) ;
;  * table des vecteurs déplacée (VBR du 68030) vers une table de relais qui
;    renvoie chaque exception au vecteur écrit par le jeu en mémoire basse
;    ($70, $118...). Cela permet deux corrections transparentes :
;      - VBL à 60 Hz (VGA, RVB NTSC) : une VBL sur six n'est pas transmise,
;        le jeu (logique, chrono, son moteur réglés sur la VBL) garde la
;        cadence de 50 Hz de l'Atari ST ;
;      - « move sr,<ea> » est privilégiée sur 68010 et plus : exécutée en mode
;        utilisateur, elle est émulée (registre de données ou -(a7)) ;
;      - l'octet $FF (vecteur 63, propre à chaque TOS) que lit la physique
;        du jeu reçoit la valeur voulue, $FF ;
;  * son : sortie YM2149 (PSG) dirigée vers le codec ;
;  * en option, mode « 8 MHz + bus STE » proche d'un ST.
;
; Options (ligne de commande, première ligne de SCRF030.INF, ou touches
; enfoncées au lancement) :
;   8 / Shift      8 MHz, bus STE (au plus près d'un ST)
;   C / Control    garder les caches tels que TOS les a laissés
;   N / Alternate  pas de correction 60 Hz
;
; Assemblage : vasmm68k_mot -Ftos -m68030 -devpac -nosym -o SCRF030.PRG scrf030.s
; Variante dossier AUTO (reste résidente, ne lance rien, ne rétablit rien) :
;              vasmm68k_mot -Ftos -m68030 -devpac -nosym -DAUTO=1 -o F030AUTO.PRG scrf030.s
;
; Aucune donnée du jeu ici : GAME.PUT vient de votre disquette.
; ---------------------------------------------------------------------------

	ifnd	AUTO
AUTO	equ	0
	endc

; options
OPT_8MHZ	equ	0
OPT_CACHE	equ	1
OPT_NO60	equ	2

; Vsetmode
STMODES		equ	$80
VGA		equ	$10
PAL		equ	$20
VERTFLAG	equ	$100
BPS4		equ	2
MODE_STLOW	equ	STMODES|BPS4		; 40 colonnes, 16 couleurs

SCREEN_BYTES	equ	32000
SCREEN_AREA	equ	$8000			; écran + marge, comme en haut de la RAM d'un ST

	text

start:	move.l	4(sp),a5			; basepage
	lea	stack_top,sp
	move.l	a5,basepage
	move.l	$0c(a5),d0			; TEXT
	add.l	$14(a5),d0			; DATA
	add.l	$1c(a5),d0			; BSS
	add.l	#$100,d0
	move.l	d0,keep_size
	move.l	d0,-(sp)
	move.l	a5,-(sp)
	clr.w	-(sp)
	move.w	#$4a,-(sp)			; Mshrink
	trap	#1
	lea	12(sp),sp

	lea	txt_banner(pc),a0
	bsr	print

	bsr	parse_options
	bsr	print_options

	pea	read_cookies(pc)
	move.w	#38,-(sp)			; Supexec
	trap	#14
	addq.l	#6,sp

	tst.w	is_falcon
	bne.s	.falcon
	lea	txt_notfalcon(pc),a0		; pas de VIDEL : on lance tel quel
	bsr	print
	ifeq	AUTO
	bsr	run_game
	bsr	report_exec
	endc
	bra	quit

.falcon:
	move.w	#89,-(sp)			; Vmontype
	trap	#14
	addq.l	#2,sp
	move.w	d0,montype
	bne.s	.colour
	lea	txt_mono(pc),a0			; SM124 : le jeu est en couleur
	bsr	print
	bsr	wait_key
	bra	quit

.colour:
	bsr	set_video
	tst.l	d0
	bmi	.novideo

	pea	measure_vbl(pc)			; fréquence réelle de la VBL
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp

	bsr	sound_setup

	pea	hw_install(pc)			; caches, horloge, VBR
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp

	ifne	AUTO
; dossier AUTO : on reste résident (table des vecteurs et relais en BSS)
	clr.w	-(sp)
	move.l	keep_size,-(sp)
	move.w	#$31,-(sp)			; Ptermres
	trap	#1
	else
	bsr	run_game

	pea	hw_restore(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	bsr	sound_restore
	bsr	restore_video
	bsr	report_exec
	bra	quit
	endc

.novideo:
	lea	txt_novideo(pc),a0
	bsr	print
	bsr	wait_key

quit:	clr.w	-(sp)				; Pterm0
	trap	#1

; ---------------------------------------------------------------------------
; options : ligne de commande (basepage+$80) et touches spéciales
parse_options:
	moveq	#0,d4
	move.l	basepage,a0
	lea	$80(a0),a0
	moveq	#0,d1
	move.b	(a0)+,d1
	bsr.s	.letters

	clr.w	-(sp)				; SCRF030.INF : options sur la première ligne
	pea	inf_name
	move.w	#$3d,-(sp)			; Fopen
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi.s	.noinf
	move.w	d0,d3
	pea	inf_buf
	move.l	#63,-(sp)
	move.w	d3,-(sp)
	move.w	#$3f,-(sp)			; Fread
	trap	#1
	lea	12(sp),sp
	move.l	d0,d1
	move.w	d3,-(sp)
	move.w	#$3e,-(sp)			; Fclose
	trap	#1
	addq.l	#4,sp
	tst.l	d1
	ble.s	.noinf
	lea	inf_buf,a0
	bsr.s	.letters
.noinf:

	move.w	#-1,-(sp)
	move.w	#11,-(sp)			; Kbshift
	trap	#13
	addq.l	#4,sp
	moveq	#3,d1				; Shift droit ou gauche
	and.b	d0,d1
	beq.s	.k1
	bset	#OPT_8MHZ,d4
.k1:	btst	#2,d0				; Control
	beq.s	.k2
	bset	#OPT_CACHE,d4
.k2:	btst	#3,d0				; Alternate
	beq.s	.k3
	bset	#OPT_NO60,d4
.k3:	move.w	d4,options
	rts

; d1 caractères en (a0), arrêt en fin de ligne ; options ajoutées à d4 (d0-d2/a0-a2 détruits par le TOS)
.letters:
	bra.s	.next
.loop:	move.b	(a0)+,d0
	cmp.b	#13,d0
	beq.s	.eol
	cmp.b	#10,d0
	beq.s	.eol
	cmp.b	#'8',d0
	bne.s	.notspeed
	bset	#OPT_8MHZ,d4
.notspeed:
	and.b	#$df,d0				; majuscule
	cmp.b	#'C',d0
	bne.s	.notc
	bset	#OPT_CACHE,d4
.notc:	cmp.b	#'N',d0
	bne.s	.next
	bset	#OPT_NO60,d4
.next:	dbf	d1,.loop
.eol:	rts

print_options:
	lea	txt_opts(pc),a0
	bsr	print
	move.w	options,d3
	btst	#OPT_8MHZ,d3
	beq.s	.o1
	lea	txt_o8(pc),a0
	bsr	print
.o1:	btst	#OPT_CACHE,d3
	beq.s	.o2
	lea	txt_oc(pc),a0
	bsr	print
.o2:	btst	#OPT_NO60,d3
	beq.s	.o3
	lea	txt_on(pc),a0
	bsr	print
.o3:	lea	txt_crlf(pc),a0
	bra	print

; ---------------------------------------------------------------------------
; superviseur : boîte à cookies (_MCH, _VDO, _SND, _CPU)
read_cookies:
	clr.w	is_falcon
	move.l	$5a0.w,d0
	beq.s	.done
	move.l	d0,a0
.loop:	move.l	(a0)+,d0
	beq.s	.done
	move.l	(a0)+,d1
	cmp.l	#'_VDO',d0
	bne.s	.notvdo
	swap	d1
	cmp.w	#3,d1				; VIDEL
	bne.s	.loop
	move.w	#1,is_falcon
	bra.s	.loop
.notvdo:
	cmp.l	#'_SND',d0
	bne.s	.notsnd
	move.l	d1,snd_cookie
	bra.s	.loop
.notsnd:
	cmp.l	#'_CPU',d0
	bne.s	.loop
	move.l	d1,cpu_cookie
	bra.s	.loop
.done:	rts

; ---------------------------------------------------------------------------
; mode ST basse sur notre écran ; d0 < 0 en cas d'échec
set_video:
	move.w	#-1,-(sp)
	move.w	#88,-(sp)			; Vsetmode(-1)
	trap	#14
	addq.l	#4,sp
	move.w	d0,old_mode
	move.w	#2,-(sp)			; Physbase
	trap	#14
	addq.l	#2,sp
	move.l	d0,old_phys
	move.w	#3,-(sp)			; Logbase
	trap	#14
	addq.l	#2,sp
	move.l	d0,old_log

	pea	save_palettes(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp

; nouveau mode, comme le ferait VsetMode de TOS 4 pour ce moniteur
	move.w	#MODE_STLOW,d1
	cmp.w	#2,montype
	bne.s	.rgb
	or.w	#VGA|VERTFLAG,d1		; VGA : lignes doublées
	bra.s	.mode
.rgb:	move.w	old_mode,d0			; RVB / TV : PAL ou NTSC comme avant
	and.w	#PAL,d0
	or.w	d0,d1
.mode:	move.w	d1,new_mode

; écran dans notre BSS (ST-RAM : programme chargé en ST-RAM), aligné sur 256 octets
; ($FF8201/03), suivi d'une marge pour atteindre 32 Ko : sur un ST, l'écran est en haut
; de la mémoire et le chargeur JEK de GAME.PUT recopie sa dernière routine à
; écran+$7F00, entre la fin de l'écran et le sommet de la RAM.
	move.l	#screen_mem+255,d0
	and.l	#$ffffff00,d0
	move.l	d0,screen
	move.l	d0,a0				; écran noir
	move.w	#SCREEN_BYTES/4-1,d1
.clr:	clr.l	(a0)+
	dbf	d1,.clr
	move.l	d0,d1

	move.w	new_mode,-(sp)
	move.w	#3,-(sp)
	move.l	d1,-(sp)			; physique
	move.l	d0,-(sp)			; logique
	move.w	#5,-(sp)			; Setscreen
	trap	#14
	lea	14(sp),sp
	move.w	#37,-(sp)			; Vsync
	trap	#14
	addq.l	#2,sp
	moveq	#0,d0
	rts

	ifeq	AUTO
restore_video:
	move.w	#37,-(sp)
	trap	#14
	addq.l	#2,sp
	move.w	old_mode,-(sp)
	move.w	#3,-(sp)
	move.l	old_phys,-(sp)
	move.l	old_log,-(sp)
	move.w	#5,-(sp)			; Setscreen : mode et écran d'avant
	trap	#14
	lea	14(sp),sp
	pea	restore_palettes(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	rts
	endc

; superviseur : palettes ST (16 mots) et Falcon (256 longs)
save_palettes:
	lea	$ffff8240.w,a0
	lea	old_stpal,a1
	moveq	#16-1,d0
.st:	move.w	(a0)+,(a1)+
	dbf	d0,.st
	lea	$ffff9800.w,a0
	lea	old_fpal,a1
	move.w	#256-1,d0
.f:	move.l	(a0)+,(a1)+
	dbf	d0,.f
	rts

	ifeq	AUTO
restore_palettes:
	lea	old_fpal,a0
	lea	$ffff9800.w,a1
	move.w	#256-1,d0
.f:	move.l	(a0)+,(a1)+
	dbf	d0,.f
	lea	old_stpal,a0
	lea	$ffff8240.w,a1
	moveq	#16-1,d0
.st:	move.w	(a0)+,(a1)+
	dbf	d0,.st
	rts
	endc

; ---------------------------------------------------------------------------
; superviseur : nombre de VBL pendant 100 ticks de 200 Hz (25 à 50 Hz, 30 à 60 Hz)
measure_vbl:
	move.l	$70.w,old_vbl_m
	clr.l	vbl_count
	move.l	#count_vbl,$70.w
	move.l	$4ba.w,d0
.sync:	cmp.l	$4ba.w,d0			; début d'un tick
	beq.s	.sync
	move.l	$4ba.w,d0
	clr.l	vbl_count
	add.l	#100,d0
.wait:	cmp.l	$4ba.w,d0
	bhi.s	.wait
	move.l	vbl_count,d0
	move.l	old_vbl_m,$70.w
	move.w	d0,vbl_per_halfsec
	clr.w	hz60
	cmp.w	#28,d0
	blo.s	.done
	move.w	#1,hz60
.done:	rts

count_vbl:
	addq.l	#1,vbl_count
	move.l	old_vbl_m,-(sp)
	rts

; ---------------------------------------------------------------------------
; son : PSG (YM2149) -> ADC -> additionneur -> sorties
sound_setup:
	btst	#2,snd_cookie+3			; codec 16 bits présent ?
	beq.s	.none
	move.w	#-1,-(sp)
	move.w	#4,-(sp)			; ADDERIN
	move.w	#130,-(sp)			; Soundcmd
	trap	#14
	addq.l	#6,sp
	move.w	d0,old_adderin
	move.w	#-1,-(sp)
	move.w	#5,-(sp)			; ADCINPUT
	move.w	#130,-(sp)
	trap	#14
	addq.l	#6,sp
	move.w	d0,old_adcinput
	move.w	#1,-(sp)			; additionneur <- ADC
	move.w	#4,-(sp)
	move.w	#130,-(sp)
	trap	#14
	addq.l	#6,sp
	move.w	#3,-(sp)			; ADC <- PSG (gauche et droite)
	move.w	#5,-(sp)
	move.w	#130,-(sp)
	trap	#14
	addq.l	#6,sp
	move.w	#1,sound_saved
.none:	rts

	ifeq	AUTO
sound_restore:
	tst.w	sound_saved
	beq.s	.none
	move.w	old_adderin,-(sp)
	move.w	#4,-(sp)
	move.w	#130,-(sp)
	trap	#14
	addq.l	#6,sp
	move.w	old_adcinput,-(sp)
	move.w	#5,-(sp)
	move.w	#130,-(sp)
	trap	#14
	addq.l	#6,sp
.none:	rts
	endc

; ---------------------------------------------------------------------------
; superviseur : caches, horloge, table des vecteurs relais
hw_install:
	move.w	sr,-(sp)
	or.w	#$0700,sr
	cmp.l	#30,cpu_cookie			; CACR et $FFFF8007 : 68030 seulement
	bne.s	.speed_kept			; (68040/68060 des cartes accélératrices : autres bits)
	move.w	#1,is_030
	movec	cacr,d0
	move.l	d0,old_cacr
	btst	#OPT_CACHE,options+1
	bne.s	.cache_kept
	move.l	#$0808,d0			; CI+CD : vidés ; EI=ED=0 : coupés
	movec	d0,cacr
.cache_kept:
	move.b	$ffff8007.w,old_busctrl
	btst	#OPT_8MHZ,options+1
	beq.s	.speed_kept
	and.b	#%11011010,$ffff8007.w		; CPU et blitter à 8 MHz, bus STE
.speed_kept:

; relais : pour chaque vecteur n, « move.l (n*4).w,-(sp) ; rts »
	lea	relays,a0
	lea	vectab,a1
	moveq	#0,d1				; adresse du vecteur
	move.w	#256-1,d2
.mk:	move.l	a0,(a1)+
	move.w	#$2f38,(a0)+			; move.l abs.w,-(sp)
	move.w	d1,(a0)+
	move.w	#$4e75,(a0)+			; rts
	addq.w	#4,d1
	dbf	d2,.mk
	move.l	0.w,vectab			; SSP / PC de reset : recopiés
	move.l	4.w,vectab+4
	move.l	#priv_violation,vectab+$20
	tst.w	hz60
	beq.s	.no60
	btst	#OPT_NO60,options+1
	bne.s	.no60
	move.l	#vbl_5of6,vectab+$70
.no60:
	tst.w	is_030
	beq.s	.noflush
	movec	cacr,d0				; les relais sont du code : vider le cache d'instructions
	or.w	#$0808,d0
	movec	d0,cacr
.noflush:
	movec	vbr,d0
	move.l	d0,old_vbr
	lea	vectab,a0
	movec	a0,vbr
; la physique lit l'octet $FF (« move.b $FF.l,d0 » au lieu de « #$FF », routine
; $49718) : octet faible du vecteur 63, qui dépend de la version du TOS. Le CPU
; lit maintenant notre table : on y met la valeur voulue, $FF.
	move.b	$ff.w,old_byte_ff
	st	$ff.w
	move.w	#1,hw_installed
	move.w	(sp)+,sr
	rts

	ifeq	AUTO
hw_restore:
	tst.w	hw_installed
	beq.s	.done
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.b	old_byte_ff,$ff.w
	move.l	old_vbr,d0
	movec	d0,vbr
	tst.w	is_030
	beq.s	.not030
	move.b	old_busctrl,$ffff8007.w
	move.l	old_cacr,d0
	or.w	#$0808,d0			; vider avant de rallumer
	movec	d0,cacr
.not030:
	clr.w	hw_installed
	move.w	(sp)+,sr
.done:	rts
	endc

; VBL à 60 Hz : cinq VBL sur six sont transmises au vecteur $70 (50 Hz en moyenne)
vbl_5of6:
	subq.w	#1,vbl_phase
	bne.s	.pass
	move.w	#6,vbl_phase
	rte
.pass:	move.l	$70.w,-(sp)
	rts

; violation de privilège : émule « move sr,Dn » et « move sr,-(a7) » en mode utilisateur
; pile : 0-35 d0-d7/a0, 36 SR, 38 PC (instruction fautive), 42 format/vecteur
priv_violation:
	movem.l	d0-d7/a0,-(sp)
	move.l	38(sp),a0
	move.w	(a0),d0
	move.w	d0,d1
	and.w	#$ffc0,d1
	cmp.w	#$40c0,d1			; move sr,<ea>
	bne.s	.forward
	and.w	#$3f,d0
	cmp.w	#8,d0
	blo.s	.dn
	cmp.w	#$27,d0				; -(a7)
	bne.s	.forward
	move.l	usp,a0
	move.w	36(sp),-(a0)
	move.l	a0,usp
	bra.s	.emulated
.dn:	lsl.w	#2,d0
	move.w	36(sp),2(sp,d0.w)		; mot faible de Dn sauvegardé
.emulated:
	addq.l	#1,priv_count
	addq.l	#2,38(sp)
	movem.l	(sp)+,d0-d7/a0
	rte
.forward:
	movem.l	(sp)+,d0-d7/a0
	move.l	$20.w,-(sp)
	rts

; ---------------------------------------------------------------------------
	ifeq	AUTO
run_game:
	move.l	#null_env,-(sp)			; environnement vide
	pea	null_cmd
	pea	game_name
	clr.w	-(sp)				; charger et lancer
	move.w	#$4b,-(sp)			; Pexec
	trap	#1
	lea	16(sp),sp
	move.l	d0,exec_result
	rts

report_exec:
	move.l	exec_result,d0
	bpl.s	.ok
	lea	txt_nogame(pc),a0
	bsr	print
	bsr	wait_key
.ok:	rts
	endc

print:	move.l	a0,-(sp)
	move.w	#9,-(sp)			; Cconws
	trap	#1
	addq.l	#6,sp
	rts

wait_key:
	move.w	#8,-(sp)			; Cnecin
	trap	#1
	addq.l	#2,sp
	rts

; ---------------------------------------------------------------------------
	data

txt_banner:
	dc.b	27,"E"
	dc.b	"Stunt Car Racer - Falcon030",13,10
	ifne	AUTO
	dc.b	"(dossier AUTO)",13,10
	endc
	dc.b	"Shift: 8 MHz  Control: caches",13,10
	dc.b	"Alternate: pas de correction 60 Hz",13,10,0
txt_opts:
	dc.b	"Options :",0
txt_o8:	dc.b	" 8MHz",0
txt_oc:	dc.b	" caches",0
txt_on:	dc.b	" 60Hz",0
txt_crlf:
	dc.b	13,10,0
txt_notfalcon:
	dc.b	"Pas de VIDEL : lancement direct.",13,10,0
txt_mono:
	dc.b	"Moniteur monochrome : le jeu demande",13,10
	dc.b	"un moniteur couleur (RVB, TV ou VGA).",13,10,0
txt_novideo:
	dc.b	"Memoire insuffisante pour l'ecran.",13,10,0
	ifeq	AUTO
txt_nogame:
	dc.b	27,"E","GAME.PUT introuvable ou illisible.",13,10
	dc.b	"Copiez GAME.PUT (disquette d'origine)",13,10
	dc.b	"dans le dossier de SCRF030.PRG.",13,10,0
game_name:
	dc.b	"GAME.PUT",0
null_cmd:
	dc.b	0,0
null_env:
	dc.b	0,0
	endc
inf_name:
	dc.b	"SCRF030.INF",0
	even
vbl_phase:
	dc.w	6

; ---------------------------------------------------------------------------
	bss

basepage:	ds.l	1
keep_size:	ds.l	1
options:	ds.w	1
is_falcon:	ds.w	1
montype:	ds.w	1
snd_cookie:	ds.l	1
cpu_cookie:	ds.l	1
old_mode:	ds.w	1
new_mode:	ds.w	1
old_phys:	ds.l	1
old_log:	ds.l	1
screen:		ds.l	1
exec_result:	ds.l	1
old_vbl_m:	ds.l	1
vbl_count:	ds.l	1
vbl_per_halfsec: ds.w	1
hz60:		ds.w	1
sound_saved:	ds.w	1
old_adderin:	ds.w	1
old_adcinput:	ds.w	1
hw_installed:	ds.w	1
is_030:		ds.w	1
old_cacr:	ds.l	1
old_vbr:	ds.l	1
old_busctrl:	ds.w	1
old_byte_ff:	ds.w	1
priv_count:	ds.l	1
old_stpal:	ds.w	16
old_fpal:	ds.l	256
inf_buf:	ds.b	64
		ds.l	2
vectab:		ds.l	256			; nouvelle table (VBR), alignée sur 4
relays:		ds.w	3*256
		ds.l	512
stack_top:	ds.l	1
screen_mem:	ds.b	SCREEN_AREA+256

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
;  * en option, mode « 8 MHz + bus STE » proche d'un ST ;
;  * cartes 68060 (CT60, CT63) et 68040 : adressage 32 bits (le chargeur JEK de GAME.PUT
;    est corrigé avant d'être lancé : $0FFF8240 -> $FFFF8240), caches à recopie
;    (CPUSHA / CPUSHL au lieu du bit CI), et jeu fluide d'office en logique x6.
;
; Quand le jeu installe sa VBL, le relais le reconnaît (signature) et
;  * fait des flèches et d'Espace un joystick (kbd_joy) ;
;  * rallume les caches du 68030 (le jeu est en place ; le cache d'instructions
;    est vidé à chaque VBL par prudence) : un tour de jeu passe de 2,9 à 1,8 VBL ;
;  * remplace des routines du jeu par des versions réécrites pour le 68030, au
;    résultat identique (turbo.s : tracé des bords de polygones, sprites) ;
;  * avec l'option F seulement (expérimental), dessine une ou deux IMAGES
;    EXTRAPOLÉES par tour. Elles ont des défauts : la caméra prolongée se trompe sur
;    les bosses (l'image tressaute) et le jeu dessine certaines choses (roues avant,
;    tableau de bord) dans l'écran affiché, qui manquent alors. Principe : la logique du jeu tourne
;    toujours à 8,33 tours/s (une fois toutes les 6 VBL, comme sur ST), son rendu et
;    l'échange des écrans restent à leur place ; pendant l'attente de fin de tour
;    ($4B0A6), le rendu du jeu ($51BCC) est rappelé, caméra et adversaire prolongés de
;    2/6 et 4/6 de tour (ou 3/6) dans le sens du dernier déplacement, dans des écrans
;    à nous ; la VBL les affiche au tour suivant à V0+2 et V0+4 (ou V0+3), V0 étant
;    l'échange du jeu. On n'y recopie de l'image du tour que ce que le rendu ne repeint
;    pas (tout sauf la fenêtre 3D). Les variables que le rendu modifie (snaptab.s)
;    sont sauvegardées puis restaurées : la partie reste celle du jeu d'origine, état
;    pour état. Nombre d'images selon le temps restant dans le tour et leur durée
;    mesurée (horloge 200 Hz) ; aucune si la caméra saute (grue).
;
; Options (ligne de commande, première ligne de SCRF030.INF, ou touches
; enfoncées au lancement) :
;   8 / Shift      8 MHz, bus STE (au plus près d'un ST)
;   C / Control    caches tels que TOS les a laissés, dès le lancement
;   N / Alternate  pas de correction 60 Hz
;   O              jeu d'origine : ni image intermédiaire, ni caches
;   T              sans les routines réécrites pour le 68030 (turbo.s)
;   F              images extrapolées (expérimental : défauts possibles)
;   3              F1 passe en logique x3 (25 images/s) au lieu de x2 : Falcon accéléré
;   6              F1 passe en logique x6 (50 images/s), adaptatif : d'office sur 68040/68060
;   K              caches du 68030 coupés (images extrapolées et turbo.s gardées)
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

; instructions de cache des 68040/68060 (assemblage en -m68030)
CPUSHA_BC	macro
	dc.w	$f4f8				; cpusha bc : écrit le cache de données, vide les deux
	endm
CINVA_BC	macro
	dc.w	$f4d8				; cinva bc : vide les deux caches
	endm
CPUSHL_BC_A0	macro
	dc.w	$f4e8				; cpushl bc,(a0) : une ligne
	endm

; options
OPT_8MHZ	equ	0
OPT_CACHE	equ	1
OPT_NO60	equ	2
OPT_ORIG	equ	3
OPT_NOTURBO	equ	4
OPT_FLUID	equ	5
OPT_NOCACHE	equ	6
OPT_X3		equ	7
OPT_X6		equ	8			; (octet fort d'options)
HD_NPATCH	equ	4			; modifications du jeu en mode HD

; adresses du jeu (documentées pour une base TEXT à $10100), relatives à la base
G_VBL		equ	$4ec24-$10100		; VBL du jeu (movem.l d0-a6,-(sp))
G_RENDCALL	equ	$4aa8c-$10100		; jsr $51BCC de la boucle de course
G_RENDER	equ	$51bcc-$10100		; rendu de la scène et du cockpit
G_RELOAD	equ	$4b0c2-$10100		; move.b #6,$4EC20 (6 VBL par tour)
G_WAITCALL	equ	$4ab90-$10100		; jsr $4B0A6 de la boucle de course
G_WAIT		equ	$4b0a6-$10100		; attente de fin de tour et échange des écrans
G_NAMES		equ	$13498-$10100		; « LITTLE RAMP »
G_COUNTER	equ	$4ec20-$10100		; VBL restantes dans le tour
G_DISP		equ	$56c70-$10100		; écran affiché
G_DRAW		equ	$56c74-$10100		; écran de travail
G_WIN		equ	$56c78-$10100		; fenêtre 3D de l'écran de travail
G_CAM		equ	$10ac2-$10100		; x, y, z (16.16), tangage, lacet, roulis
G_OPP_PIECE	equ	$10907-$10100		; adversaire : pièce,
G_OPP_SEC	equ	$108f6-$10100		;   section.fraction,
G_OPP_LAT	equ	$109d6-$10100		;   position en travers
G_END		equ	$73370-$10100		; fin de la BSS du jeu
G_PIECE_TYPE	equ	$10ce6-$10100		; type de chaque pièce du circuit (bits 0-3)
G_TYPE_TAB	equ	$13670-$10100		; données des types de pièce
G_NPIECES	equ	$11114-$10100		; nombre de pièces du circuit
G_DAMP		equ	$4ee64-$10100		; coefficient de l'amortisseur ($114)
G_YAW		equ	$4e6fc-$10100		; réalignement du cap (8 octets)
G_CHRONO	equ	$4b517-$10100		; « move.b #$13,d0 » : centièmes ajoutés au chrono à chaque tour
G_CD		equ	$109c9-$10100		; compte à rebours (grue, départ, remise en piste) : 0 en course
G_JOY		equ	$106a6-$10100		; joystick (lu par le jeu, écrit par son $118)
G_KEYS		equ	$6f02c-$10100		; touches enfoncées ($B3), par code clavier
CAM_JUMP	equ	$02000000		; écart (x, y ou z) au-delà duquel la caméra a sauté

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
	ifeq	AUTO
	bsr	hd_setup			; F2 / F3 : 68040/68060 avec FPU, en VGA
	endc
	bsr	set_video
	tst.l	d0
	bmi	.novideo
	ifeq	AUTO
	tst.w	hd_avail			; registres du VIDEL en ST basse
	beq.s	.nohd
	move.l	#st_vregs,vsave_ptr
	pea	videl_save(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	move.w	#-1,-(sp)			; Physbase = notre écran (le chargeur JEK s'en sert),
	move.w	#-1,-(sp)			; même si le TOS en a réservé un autre aux changements
	move.l	screen,-(sp)			; de mode
	move.l	screen,-(sp)
	move.w	#5,-(sp)
	trap	#14
	lea	14(sp),sp
	move.w	#37,-(sp)
	trap	#14
	addq.l	#2,sp
.nohd:
	endc

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
	bne.s	.not8
	bset	#OPT_8MHZ,d4
.not8:	cmp.b	#'3',d0
	bne.s	.not3
	bset	#OPT_X3,d4
.not3:	cmp.b	#'6',d0
	bne.s	.notspeed
	bset	#OPT_X6,d4
.notspeed:
	and.b	#$df,d0				; majuscule
	cmp.b	#'C',d0
	bne.s	.notc
	bset	#OPT_CACHE,d4
.notc:	cmp.b	#'N',d0
	bne.s	.notn
	bset	#OPT_NO60,d4
.notn:	cmp.b	#'O',d0
	bne.s	.noto
	bset	#OPT_ORIG,d4
.noto:	cmp.b	#'T',d0
	bne.s	.notb
	bset	#OPT_NOTURBO,d4
.notb:	cmp.b	#'F',d0
	bne.s	.notf
	bset	#OPT_FLUID,d4
.notf:	cmp.b	#'K',d0
	bne.s	.next
	bset	#OPT_NOCACHE,d4
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
.o3:	btst	#OPT_ORIG,d3
	beq.s	.o4
	lea	txt_oo(pc),a0
	bsr	print
.o4:	btst	#OPT_NOTURBO,d3
	beq.s	.o5
	lea	txt_ot(pc),a0
	bsr	print
.o5:	btst	#OPT_FLUID,d3
	beq.s	.o6
	lea	txt_of(pc),a0
	bsr	print
.o6:	lea	txt_crlf(pc),a0
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
	bne.s	.notcpu
	move.l	d1,cpu_cookie
	bra.s	.loop
.notcpu:
	cmp.l	#'_FPU',d0
	bne.s	.loop
	move.l	d1,fpu_cookie
	bra.s	.loop
.done:
; adressage 24 bits ? Le chargeur JEK de GAME.PUT écrit la palette en $0FFF8240, qui
; n'est $FF8240 que si les 8 bits forts de l'adresse sont ignorés (Falcon d'origine,
; Hatari par défaut). En 32 bits (TT-RAM, cartes accélératrices) : erreur de bus.
	clr.w	addr32
	move.l	$8.w,a1
	move.l	sp,a2
	move.l	#.berr,$8.w
	tst.w	$0fff8240
	bra.s	.a24
.berr:	move.l	a2,sp				; cadre d'exception abandonné
	move.w	#1,addr32
.a24:	move.l	a1,$8.w
	rts

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
	cmp.l	#40,cpu_cookie			; 68040 / 68060 (CT60, CT63...) : autres bits
	beq.s	.c060				; du CACR, caches à recopie (copyback)
	cmp.l	#60,cpu_cookie
	beq.s	.c060
	cmp.l	#30,cpu_cookie			; CACR et $FFFF8007 : 68030 seulement
	bne.s	.speed_kept
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
	bra.s	.speed_kept
; 68040/68060 : caches coupés pendant le chargement (le jeu est décompressé puis relogé),
; après avoir écrit en mémoire le contenu du cache de données (CPUSHA)
.c060:	move.w	#1,is_060
	movec	cacr,d0
	move.l	d0,old_cacr
	btst	#OPT_CACHE,options+1
	bne.s	.speed_kept
	CPUSHA_BC
	moveq	#0,d0
	movec	d0,cacr
	CINVA_BC
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
	move.l	#vbl_hook,vectab+$70
	clr.w	div60
	tst.w	hz60
	beq.s	.no60
	btst	#OPT_NO60,options+1
	bne.s	.no60
	move.w	#1,div60			; 60 Hz : 5 VBL sur 6
.no60:
	move.l	old_cacr,d0			; caches du mode fluide : ceux du TOS,
	tst.w	is_060
	bne.s	.cv6
	and.w	#$3111,d0			; ou WA+DBE+ED+IBE+EI s'il les avait coupés
	btst	#0,d0
	bne.s	.cv
	move.w	#$3111,d0
.cv:	or.w	#$0808,d0			; vidés à l'allumage
	bra.s	.cvs
.cv6:	and.l	#$a080c000,d0			; 68060 : EDC ESB EBC EIC (et NAI), 68040 : DE IE
	tst.w	d0
	bmi.s	.cvs
	move.l	#$80008000,d0			; caches coupés par le TOS : données, instructions
	cmp.l	#60,cpu_cookie
	bne.s	.cvs
	move.l	#$a0808000,d0			; + tampon d'écriture et cache de branchements
.cvs:	move.l	d0,cache_on_value
	move.l	#ebuf_mem+255,d0		; écrans des images extrapolées
	and.l	#$ffffff00,d0
	move.l	d0,ebuf
	bsr	flush_ic			; les relais sont du code
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
	tst.w	hd_on
	beq.s	.nohd
	bsr	hd_leave
.nohd:	clr.w	icache_on
	clr.w	interp_on
	clr.w	game_ok
	move.b	old_byte_ff,$ff.w
	move.l	old_vbr,d0
	movec	d0,vbr
	tst.w	is_060
	beq.s	.not060
	CPUSHA_BC
	move.l	old_cacr,d0
	movec	d0,cacr
	CINVA_BC
.not060:
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

; VBL : reconnaissance du jeu, vidage du cache d'instructions, et à 60 Hz cinq
; VBL sur six seulement transmises au vecteur $70 (50 Hz en moyenne)
vbl_hook:
	addq.l	#1,vbl_ticks
	tst.w	game_ok
	bne.s	.ready
	bsr	detect_game
.ready:	tst.w	game_ok
	beq.s	.nokj
	bsr	kbd_joy
	ifeq	AUTO
	tst.w	hd_on
	beq.s	.nokj
	bsr	hd_vbl
	endc
.nokj:	tst.w	icache_on
	beq.s	.nofl
	bsr	flush_ic
.nofl:	tst.w	div60
	beq.s	.pass
	subq.w	#1,vbl_phase
	bne.s	.pass
	move.w	#6,vbl_phase
	tst.w	cnt_real			; logique accélérée à 60 Hz : la VBL retenue
	beq.s	.drop				; compte quand même pour le tour (comme $4EC2C)
	move.l	a0,-(sp)
	move.l	game_base,a0
	tst.b	G_COUNTER(a0)
	beq.s	.d0
	subq.b	#1,G_COUNTER(a0)
.d0:	move.l	(sp)+,a0
.drop:	rte
.pass:	tst.w	interp_on
	beq.s	.go
	bsr	vbl_flip
.go:	move.l	$70.w,-(sp)
	rts

; flèches du clavier = joystick (Espace = tir) : le jeu ne se pilote qu'au joystick, et
; sans joystick (Hatari sans émulation, Falcon sans manette) on ne pouvait ni tourner ni
; choisir dans les menus. La table des touches tenue par le jeu donne l'état ; on écrit
; le joystick du jeu (format de son $118 : directions et tir en bit 4, inversés) tant
; qu'une de ces touches est enfoncée, et une fois au relâchement : un vrai joystick
; garde la main le reste du temps.
kbd_joy:
	movem.l	d0-d1/a0,-(sp)
	move.l	game_base,a0
	lea	G_KEYS(a0),a0
	moveq	#0,d0
	cmp.b	#$b3,$48(a0)			; haut
	bne.s	.k1
	or.b	#1,d0
.k1:	cmp.b	#$b3,$50(a0)			; bas
	bne.s	.k2
	or.b	#2,d0
.k2:	cmp.b	#$b3,$4b(a0)			; gauche
	bne.s	.k3
	or.b	#4,d0
.k3:	cmp.b	#$b3,$4d(a0)			; droite
	bne.s	.k4
	or.b	#8,d0
.k4:	cmp.b	#$b3,$39(a0)			; Espace : tir
	bne.s	.k5
	or.b	#$10,d0
.k5:	cmp.b	#$b3,$3b(a0)			; F1 : logique normale / doublée
	seq	d1
	cmp.b	f1_prev,d1
	beq.s	.k6
	move.b	d1,f1_prev
	tst.b	d1
	beq.s	.k6
	tst.b	dbl_req			; normal <-> fluide (dbl_max : x2, x3 ou x6)
	beq.s	.f1on
	clr.b	dbl_req
	bra.s	.k6
.f1on:	move.b	dbl_max,dbl_req
.k6:
	ifeq	AUTO
	tst.w	hd_avail
	beq.s	.k8
	cmp.b	#$b3,$3c(a0)			; F2 : mode HD, F3 : mode texturé (bascules)
	seq	d1
	cmp.b	f2_prev,d1
	beq.s	.k7
	move.b	d1,f2_prev
	tst.b	d1
	beq.s	.k7
	moveq	#1,d1
	cmp.b	hd_req,d1
	bne.s	.f2s
	moveq	#0,d1
.f2s:	move.b	d1,hd_req
.k7:	cmp.b	#$b3,$3d(a0)
	seq	d1
	cmp.b	f3_prev,d1
	beq.s	.k8
	move.b	d1,f3_prev
	tst.b	d1
	beq.s	.k8
	moveq	#2,d1
	cmp.b	hd_req,d1
	bne.s	.f3s
	moveq	#0,d1
.f3s:	move.b	d1,hd_req
	endc
.k8:	move.b	kj_prev,d1
	move.b	d0,kj_prev
	or.b	d0,d1
	beq.s	.out
	not.b	d0
	move.l	game_base,a0
	move.b	d0,G_JOY(a0)
.out:	movem.l	(sp)+,d0-d1/a0
	rts

; le vecteur $70 pointe-t-il sur la VBL du jeu ? (vérifié une fois par valeur du vecteur)
; Appelée dans l'interruption : tous les registres touchés sont rendus (a1 compris, sinon
; le jeu, interrompu dans une boucle de copie par a1, écrivait dans le lanceur).
detect_game:
	movem.l	d0/a0-a1,-(sp)
	move.l	$70.w,d0
	cmp.l	last_vbl70,d0
	beq	.no
	move.l	d0,last_vbl70
	sub.l	#G_VBL,d0			; base TEXT supposée du jeu
	cmp.l	#$800,d0
	blo	.no
	move.l	d0,a0
	add.l	#G_END,d0
	cmp.l	$42e.w,d0			; phystop : tout doit être en RAM
	bhi	.no
	cmp.l	#$48e7fffe,G_VBL(a0)
	bne	.no
	cmp.l	#$13fc0006,G_RELOAD(a0)
	bne	.no
	cmp.l	#'LITT',G_NAMES(a0)
	bne	.no
	cmp.w	#$4eb9,G_RENDCALL(a0)
	bne	.no
	move.l	a0,d0
	add.l	#G_RENDER,d0
	cmp.l	G_RENDCALL+2(a0),d0
	bne	.no
	move.l	d0,render_addr
	cmp.w	#$4eb9,G_WAITCALL(a0)
	bne	.no
	move.l	a0,d0
	add.l	#G_WAIT,d0
	cmp.l	G_WAITCALL+2(a0),d0
	bne	.no
	move.l	d0,wait_addr
	move.l	a0,game_base
	move.w	#1,game_ok
	btst	#OPT_ORIG,options+1
	bne	.no
	move.w	is_030,d0
	or.w	is_060,d0
	beq.s	.nocache
	btst	#OPT_NOCACHE,options+1
	bne.s	.nocache
	bsr	flush_ic
	move.l	cache_on_value,d0		; le jeu est en place : caches allumés
	movec	d0,cacr
	move.w	#1,icache_on
.nocache:
	clr.w	have_prev
	btst	#OPT_FLUID,options+1		; images extrapolées : option F seulement
	beq.s	.nointerp
	move.l	#interp_wait,G_WAITCALL+2(a0)	; jsr interp_wait
	move.w	#1,interp_on
	bra.s	.hooked
.nointerp:
	move.l	#tick_hook,G_WAITCALL+2(a0)	; jsr tick_hook (F1 : logique accélérée)
	move.l	#lvl_50,lvl_set
	tst.w	div60
	beq.s	.l50
	move.l	#lvl_60,lvl_set			; 60 Hz : tours en vraies VBL
.l50:	move.b	#1,dbl_max			; F1 : x2 (Falcon 16 MHz : cadence stable),
	btst	#OPT_X3,options+1		; x3 adaptatif avec l'option 3,
	bne.s	.mx3
	btst	#OPT_X6-8,options
	bne.s	.mx6
	tst.w	is_060				; x6 adaptatif avec l'option 6 ou sur 68040/060
	beq.s	.hooked				; (fluide dès le départ)
	move.b	#3,dbl_req
.mx6:	move.b	#3,dbl_max
	bra.s	.hooked
.mx3:	move.b	#2,dbl_max
.hooked:
	bsr	turbo_reloc			; adresses du jeu dans turbo.s
	tst.w	icache_on			; code que le jeu modifie : cache vidé
	beq.s	.nocc
	ifd	NOCOLORFIX
	bra.s	.nocc
	endc
	lea	cache_tab,a1
	bsr	turbo_patch
	move.b	#$f0,pix_col			; couleur en place : inconnue
	tst.w	is_060
	beq.s	.nocc
	moveq	#0,d0				; 68040/68060 : couleur lue dans les opcodes
	btst	#6,$53151-$10100(a0)		; (bset : bit 6 à 1), puis tracé de pixel
	beq.s	.cb0				; sans code automodifiant
	bset	#0,d0
.cb0:	btst	#6,$53155-$10100(a0)
	beq.s	.cb1
	bset	#1,d0
.cb1:	btst	#6,$53159-$10100(a0)
	beq.s	.cb2
	bset	#2,d0
.cb2:	btst	#6,$5315d-$10100(a0)
	beq.s	.cb3
	bset	#3,d0
.cb3:	move.b	d0,pix_col
	lea	pix060_tab,a1
	bsr	turbo_patch
.nocc:	btst	#OPT_NOTURBO,options+1
	bne.s	.noturbo
	lea	turbo_tab,a1
	bsr	turbo_patch
	ifd	SELFCHECK
	move.l	#'CHK!',chk_magic
	endc
.noturbo:
	bsr	flush_ic			; code modifié
.no:	movem.l	(sp)+,d0/a0-a1
	rts

; ---------------------------------------------------------------------------
; appelée par la boucle de course à la place de « jsr $4B0A6 » (attente de la fin du
; tour, superviseur) : la logique et le rendu du tour N sont faits, aux mêmes instants
; que dans le jeu d'origine ; l'image du tour N sera affichée par le jeu au début du
; tour suivant (VBL V0). Pendant l'attente, on dessine une ou deux images EXTRAPOLÉES
; (caméra et adversaire prolongés de 2/6 et 4/6 de tour, ou 3/6, selon la vitesse
; N-1 -> N) qui seront affichées par la VBL à V0+2 et V0+4 (ou V0+3).
interp_wait:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	est_interp,a0
	bsr	decay
	move.l	game_base,a6
	lea	G_CAM(a6),a0			; état du tour N
	lea	cam_cur,a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.w	(a0)+,(a1)+
	move.b	G_OPP_PIECE(a6),(a1)+
	move.b	G_OPP_PIECE(a6),(a1)+
	move.w	G_OPP_SEC(a6),(a1)+
	move.w	G_OPP_LAT(a6),(a1)+
	move.l	vbl_ticks,d0			; tour précédent récent ?
	move.l	d0,d1
	sub.l	last_call,d1
	move.l	d0,last_call
	cmp.l	#15,d1
	bhi	.skip
	tst.w	have_prev
	beq	.skip
; combien d'images avant la fin du tour ? Temps restant, en ticks de 5 ms (4 par VBL) :
; compteur*4 - 3 (VBL entamée, marge) ; une image coûte est_interp (mesurée).
	moveq	#0,d0
	move.b	G_COUNTER(a6),d0
	lsl.w	#2,d0
	subq.w	#3,d0
	move.w	est_interp,d1
	move.w	d1,d2
	add.w	d2,d2				; (si la 2e manque, la 1re est montrée à V0+3)
	moveq	#2,d7				; deux images ?
	cmp.w	d0,d2
	bls.s	.n
	moveq	#1,d7
	addq.w	#1,d1
	cmp.w	d0,d1
	bhi	.skip
.n:
	ifd	DBG
	move.b	G_COUNTER(a6),dbg_e
	move.b	est_interp+1,dbg_e+1
	move.b	d7,dbg_e+2
	endc
	moveq	#0,d5				; images faites
	lea	cam_cur,a0
	lea	cam_prev,a1
	moveq	#3-1,d2
.jmp:	move.l	(a0)+,d0			; x, y, z : saut de caméra ?
	sub.l	(a1)+,d0
	bpl.s	.jp
	neg.l	d0
.jp:	cmp.l	#CAM_JUMP,d0
	bhi	.skip
	dbf	d2,.jmp

	move.l	ebuf,a5				; écrans de ce tour : jeu alterné
	bchg	#0,ebuf_par+1
	beq.s	.par
	add.l	#2*SCREEN_BYTES,a5
.par:	moveq	#0,d5				; file d'affichage du tour suivant
	clr.w	stg_ready
	clr.w	render_aborted
	move.l	G_DRAW(a6),save_draw
	move.l	G_WIN(a6),save_win
	bsr	snap_save
	moveq	#3,d6				; une image : 3/6, à V0+3
	cmp.w	#1,d7
	beq.s	.one
	moveq	#2,d6				; deux : 2/6 et 4/6, à V0+2 et V0+4
.one:
.img:	move.l	$4ba.w,t_start
	move.w	d6,slot_k
	bsr	set_extrap
	move.l	a5,a1
	movem.l	d5-d7,-(sp)
	bsr	copy_frame			; image du tour N -> écran supplémentaire
	movem.l	(sp)+,d5-d7
	move.l	a5,G_DRAW(a6)
	move.l	a5,d0
	add.l	#2576,d0			; comme $10824 : fenêtre 3D
	move.l	d0,G_WIN(a6)
	movem.l	d5-d7/a5,-(sp)
	move.l	sp,render_sp
	move.l	#.rendered,abort_pc
	movem.l	16(sp),d0-d7/a0-a6		; registres du jeu à l'appel
	move.w	#1,in_render			; la VBL qui finit le tour l'interrompt
	jsr	([render_addr])
.rendered:
	clr.w	in_render
	movem.l	(sp)+,d5-d7/a5
	move.l	game_base,a6
	move.l	save_draw,G_DRAW(a6)
	move.l	save_win,G_WIN(a6)
	bsr	snap_restore
	lea	cam_cur,a0			; caméra du tour N
	lea	G_CAM(a6),a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.w	(a0)+,(a1)+
	move.l	$4ba.w,d0			; durée de cette image
	sub.l	t_start,d0
	tst.w	render_aborted			; inachevée : rien à montrer, on s'arrête
	bne	.skip				; (et sa durée tronquée ne compte pas)
	lea	est_interp,a0
	bsr	estimate
	tst.w	d5
	bne.s	.second
	moveq	#7,d0				; montrée par la VBL qui fait passer le
	sub.w	d6,d0				; compteur de 7-k à 6-k : V0+k
	cmp.w	#2,d7
	bne.s	.q0
	moveq	#4,d0				; deux prévues : en attendant la 2e, à V0+3
.q0:	lea	stg_q0,a0			; file 0 : cette image seule
	move.w	#1,(a0)
	move.b	d0,2(a0)
	move.l	a5,4(a0)
	clr.w	stg_q
	move.w	#1,stg_ready			; à prendre par la VBL qui termine le tour
	tst.b	G_COUNTER(a6)
	bne.s	.st1
	clr.w	stg_ready			; trop tard : fin de tour déjà passée
	bra.s	.skip
.second:
	lea	stg_q1,a0			; file 1 : les deux, à V0+2 et V0+4
	move.w	#2,(a0)
	move.b	#5,2(a0)
	move.b	#3,3(a0)
	move.l	a5,d0
	sub.l	#SCREEN_BYTES,d0
	move.l	d0,4(a0)
	move.l	a5,8(a0)
	move.w	#1,stg_q			; un seul mot écrit : la VBL prend l'une ou l'autre
	moveq	#2,d5
	bra.s	.skip
.st1:	moveq	#1,d5
	subq.w	#1,d7
	beq.s	.skip
	moveq	#0,d0				; reste-t-il le temps d'une deuxième ?
	move.b	G_COUNTER(a6),d0		; (si elle déborde, la VBL l'abandonne)
	lsl.w	#2,d0
	subq.w	#2,d0
	move.w	est_interp,d1
	cmp.w	d0,d1
	bhi.s	.skip
	add.l	#SCREEN_BYTES,a5
	addq.w	#2,d6
	bra	.img
.skip:
	ifd	DBG
	tst.b	dbg_e+2
	beq.s	.nodbg
	move.l	a0,-(sp)
	move.l	dbg_ptr,a0
	move.b	dbg_e,(a0)+
	move.b	dbg_e+1,(a0)+
	move.b	dbg_e+2,(a0)+
	move.b	d5,(a0)
	tst.w	render_aborted
	beq.s	.d1
	or.b	#$10,(a0)
.d1:	addq.l	#1,a0
	cmp.l	#dbg_end,a0
	blo.s	.d2
	lea	dbg_ring,a0
.d2:	move.l	a0,dbg_ptr
	clr.b	dbg_e+2
	move.l	(sp)+,a0
.nodbg:
	endc
	lea	cam_cur,a0			; le tour N devient le précédent
	lea	cam_prev,a1
	moveq	#(CAM_BYTES/2)-1,d0
.cp:	move.w	(a0)+,(a1)+
	dbf	d0,.cp
	move.w	#1,have_prev
	movem.l	(sp)+,d0-d7/a0-a6
	jmp	([wait_addr])			; attente et échange des écrans du jeu

; ---------------------------------------------------------------------------
; Logique accélérée (touche F1 : normal, x2, x3) : le jeu fait un tour toutes les 3 ou 2 VBL
; au lieu de 6, avec un pas de temps divisé par 2 ou 3 ; chaque image est une vraie image du
; jeu (16,7 ou 25 par seconde au lieu de 8,33, si le tour tient dans ses VBL). Appelée à la
; place de « jsr $4B0A6 » (attente de fin de tour, qui recharge le compteur de VBL) : on pose
; le niveau voulu, puis l'attente. Seulement pendant la course proprement dite (compte à
; rebours $109C9 nul) : la grue, le départ et la remise en piste restent au rythme d'origine
; (ils comptent en tours). Modifications (mesurées contre le jeu d'origine dans le moteur
; fidèle, replica/js, par falcon/test/double_test.js) :
;  * facteur de pas #$EE -> #$77 / #$4F sur les 22 sites (physique, adversaire, compteurs
;    en temps de jeu de l'accumulateur $4B124) ;
;  * 6 -> 3 / 2 VBL par tour ($4B0C2) ;
;  * réalignement du cap, ajouté au lacet à chaque tour sans pas de temps ($4E6FC-$4E703) :
;    remplacé par « jsr yaw_div » (même calcul, divisé par le facteur) ;
;  * amortisseur proportionnel à la variation de compression d'un tour à l'autre ($4EE64) :
;    multiplié par le facteur ;
;  * chrono : 0,13 s ajoutée à chaque tour ($4B514) -> 13 x n / 6 centièmes par tour de
;    n VBL, avec le reste (0,06/0,07, ou 0,04/0,04/0,05).
; F1 : normal <-> x2 (cadence stable sur Falcon 16 MHz) ; avec l'option 3, normal <-> x3
; adaptatif (x2 dès qu'un tour ne tient pas en 2 VBL : pour un Falcon accéléré).
; Dégâts : mêmes passages rejoués depuis un même état, + 13 % en x2 sans correction.
tick_hook:
	movem.l	d0-d3/a0-a2/a6,-(sp)
	move.l	game_base,a6
	moveq	#0,d0
	tst.b	G_CD(a6)
	bne.s	.w
	move.b	dbl_req,d0
	cmp.b	#2,d0
	blo.s	.w
; adaptatif (x3 ou x6 au plus) : compteur de VBL restantes à l'entrée, rechargé à n au
; début du tour (juste après une VBL) : n = le tour a pris moins d'une VBL, n-1 moins de
; deux, 0 = débordé. Débordé : un niveau de moins ; un niveau de plus (x2 -> x3 : compteur
; >= 2 sur 3, x3 -> x6 : 2 sur 2) après 8 tours de suite qui y tiennent.
	move.b	d0,d2				; niveau le plus haut
	moveq	#0,d0
	move.b	dbl_on,d0
	bne.s	.cur
	moveq	#1,d0				; départ : x2
	clr.b	dbl_good
.cur:	cmp.b	#1,d0
	beq.s	.up
	tst.b	G_COUNTER(a6)
	bne.s	.up
	subq.b	#1,d0				; débordé
	clr.b	dbl_good
	bra.s	.w
.up:	cmp.b	d2,d0
	bhs.s	.top
	cmp.b	#2,G_COUNTER(a6)
	blo.s	.bad
	addq.b	#1,dbl_good
	cmp.b	#8,dbl_good
	blo.s	.w
	addq.b	#1,d0
.bad:	clr.b	dbl_good
	bra.s	.w
.top:	move.b	d2,d0
.w:	cmp.b	dbl_on,d0
	beq.s	.same
	move.b	d0,dbl_on
	bsr	dbl_patch
.same:	moveq	#0,d0
	move.b	dbl_on,d0
	beq.s	.nc
; pas de temps : $EE x n / 6 par tour de n VBL, reste gardé (x3 : $4F $4F $50, x6 : $27
; $28 $28...) ; chrono : 0,13 s par tour de 6 VBL, donc 13 x n / 6 centièmes, reste gardé.
; À 60 Hz (VBL comptées en vraies VBL) : n vraies VBL = 5n/6 VBL du jeu, $EE x 5n / 36.
	move.l	lvl_set,a1
	moveq	#0,d1
	move.b	LS_REL(a1,d0.w),d1
	move.w	d1,d3
	mulu.w	LS_DTN(a1),d1
	add.w	dt_rem,d1
	divu.w	LS_DEN(a1),d1
	move.b	d1,d2
	swap	d1
	move.w	d1,dt_rem
	bsr	set_dt
	mulu.w	LS_CHN(a1),d3
	add.w	chr_rem,d3
	divu.w	LS_DEN(a1),d3
	move.b	d3,G_CHRONO(a6)			; < 10 : même valeur en BCD
	swap	d3
	move.w	d3,chr_rem
	bsr	flush_ic
.nc:
	ifeq	AUTO
	tst.w	hd_avail
	beq.s	.nhd
	bsr	hd_tick
	tst.w	hd_on
	beq.s	.nhd
	movem.l	(sp)+,d0-d3/a0-a2/a6
	jsr	([wait_addr])			; attente et échange des écrans du jeu,
	bra	hd_postwait			; puis fenêtre du nouvel écran de travail
.nhd:
	endc
	movem.l	(sp)+,d0-d3/a0-a2/a6
	jmp	([wait_addr])

; facteur de pas d2.b sur les 22 sites (chacun vérifié : la dernière valeur posée)
set_dt:
	cmp.b	dt_cur,d2
	beq.s	.out
	move.l	d1,-(sp)
	lea	dbl_dt,a1
.d:	move.l	(a1)+,d1
	beq.s	.e
	lea	-$10100+3(a6,d1.l),a0
	move.b	(a0),d1
	cmp.b	dt_cur,d1
	bne.s	.d
	move.b	d2,(a0)
	bra.s	.d
.e:	move.b	d2,dt_cur
	move.l	(sp)+,d1
.out:	rts

; niveau d0.b (0 : jeu d'origine, 1 : x2, 2 : x3, 3 : x6 ; à 60 Hz : 15, 20, 30 images/s) ;
; chaque site est vérifié (valeur d'origine ou posée par nous) avant d'être modifié ; a6 = base
dbl_patch:
	ext.w	d0
	clr.w	dt_rem
	clr.w	cnt_real
	tst.w	d0
	bne.s	.acc
	move.b	#$ee,d2				; jeu d'origine
	bsr.s	set_dt
	bra.s	.rel
.acc:	move.w	div60,cnt_real			; 60 Hz : le compteur suit les vraies VBL
.rel:	move.l	lvl_set,a1
	lea	G_RELOAD+3(a6),a0		; VBL par tour
	move.b	(a0),d1
	beq.s	.damp
	cmp.b	#6,d1
	bhi.s	.damp
	move.b	LS_REL(a1,d0.w),(a0)
.damp:	lea	G_DAMP(a6),a0			; amortisseur
	move.w	d0,d2
	add.w	d2,d2
	move.w	(a0),d1
	cmp.w	#$0114,d1
	blo.s	.yaw
	cmp.w	#$0678,d1
	bhi.s	.yaw
	move.w	LS_DAMP(a1,d2.w),(a0)
.yaw:	move.w	LS_MUL(a1,d2.w),yaw_mul
	lea	G_YAW(a6),a0			; réalignement du cap
	tst.w	d0
	beq.s	.yo
	cmp.l	#$c1c3e380,(a0)			; calcul d'origine -> jsr yaw_div ; nop
	bne.s	.chr
	cmp.l	#$4840ee48,4(a0)
	bne.s	.chr
	move.w	#$4eb9,(a0)
	move.l	#yaw_div,2(a0)
	move.w	#$4e71,6(a0)
	bra.s	.chr
.yo:	cmp.w	#$4eb9,(a0)
	bne.s	.chr
	cmp.l	#yaw_div,2(a0)
	bne.s	.chr
	move.l	#$c1c3e380,(a0)
	move.l	#$4840ee48,4(a0)
.chr:	lea	G_CHRONO(a6),a0			; chrono : $13 d'origine
	tst.w	d0
	bne.s	.f
	move.b	#$13,(a0)
.f:	bra	flush_ic
; niveaux 0..3 : VBL par tour, amortisseur ($114 x facteur), cap (65536 / facteur), pas de
; temps et chrono par VBL (numérateur, dénominateur commun)
LS_REL		equ	0
LS_DAMP		equ	4
LS_MUL		equ	12
LS_DTN		equ	20
LS_DEN		equ	22
LS_CHN		equ	24
lvl_50:	dc.b	6,3,2,1				; x1, x2, x3, x6
	dc.w	$0114,$0228,$033c,$0678
	dc.w	$ffff,$8000,$5556,$2aab
	dc.w	$ee,6,13
; 60 Hz : n vraies VBL par tour (facteur 36 / 5n) : 15, 20, 30 images/s, cadence fixe
lvl_60:	dc.b	6,4,3,2				; x1, x1,8, x2,4, x3,6
	dc.w	$0114,$01f1,$0296,$03e2
	dc.w	$ffff,$8e39,$6aab,$471c
	dc.w	$ee*5,36,13*5

; code modifié : vider le cache d'instructions (68030 : CI) ; 68040/68060 : cache de
; données écrit en mémoire et caches vidés (CPUSHA), puis cache de branchements (CABC)
flush_ic:
	tst.w	is_060
	bne.s	.f6
	tst.w	is_030
	beq.s	.nf
	move.l	d1,-(sp)
	movec	cacr,d1
	bset	#3,d1
	movec	d1,cacr
	move.l	(sp)+,d1
.nf:	rts
.f6:	CPUSHA_BC
	cmp.l	#60,cpu_cookie
	bne.s	.nf
	move.l	d1,-(sp)
	movec	cacr,d1
	bset	#22,d1				; CABC
	movec	d1,cacr
	move.l	(sp)+,d1
	rts

; réalignement du cap ($4E6FC : muls.w d3,d0 ; asl.l #1,d0 ; swap d0 ; lsr.w #7,d0) : même
; calcul, divisé par le facteur (yaw_mul / 65536 : 1/2 ou 1/3)
yaw_div:
	muls.w	d3,d0
	asl.l	#1,d0
	swap	d0
	lsr.w	#7,d0
	mulu.w	yaw_mul,d0
	swap	d0
	rts

; image extrapolée inachevée quand le tour finit : la VBL fait reprendre ici (au retour
; d'interruption) ; pile du rendu abandonnée, état du jeu rétabli comme après un rendu
t_abort:
	move.l	render_sp,sp
	move.w	#1,render_aborted
	move.l	abort_pc,-(sp)
	rts

; VBL (transmise au jeu) : affiche les images extrapolées au bon instant. Le compteur
; du jeu, lu avant que sa VBL ne le décrémente, vaut 1 à la VBL qui finit le tour (V0) :
; la file préparée pendant le tour devient active ; sinon, on affiche l'image suivante
; de la file active quand le compteur atteint sa valeur.
vbl_flip:
	movem.l	d0-d1/a0-a1,-(sp)
	move.l	game_base,a0
	move.b	G_COUNTER(a0),d0
	cmp.b	#1,d0
	bne.s	.act
	tst.w	in_render			; image extrapolée en cours : abandonnée
	beq.s	.nab
	move.w	20(sp),d1			; SR empilé : programme principal ?
	and.w	#$0700,d1
	cmp.w	#$0300,d1
	bhi.s	.nab
	move.l	#t_abort,22(sp)			; PC empilé
	clr.w	in_render
.nab:	clr.w	act_n				; ce qui n'a pas été montré est abandonné
	tst.w	stg_ready
	beq.s	.out
	lea	stg_q0,a0
	tst.w	stg_q
	beq.s	.q
	lea	stg_q1,a0
.q:	lea	act_n,a1
	moveq	#(STG_BYTES/2)-1,d1
.cp:	move.w	(a0)+,(a1)+
	dbf	d1,.cp
	clr.w	act_i
	clr.w	stg_ready
	bra.s	.out
.act:	move.w	act_i,d1
	cmp.w	act_n,d1
	bhs.s	.out
	lea	act_c,a1
	cmp.b	(a1,d1.w),d0
	bne.s	.out
	move.l	act_a-act_c(a1,d1.w*4),d0
	lsr.l	#8,d0
	move.b	d0,$ffff8203.w
	lsr.w	#8,d0
	move.b	d0,$ffff8201.w
	addq.w	#1,act_i
	addq.l	#1,interp_count
.out:	movem.l	(sp)+,d0-d1/a0-a1
	rts

; routines réécrites (turbo.s) : adresses du jeu relogées, « jmp » posés (a0 = base)
turbo_reloc:
	movem.l	d0-d2/a1-a2,-(sp)
	move.l	a0,d0
	sub.l	#$10100,d0
	move.l	d0,d2
	sub.l	grel_delta,d0			; ce qui reste à ajouter
	move.l	d2,grel_delta
	lea	grel_start,a1
.r:	cmp.l	#grel_end,a1
	bhs.s	.d
	move.l	(a1)+,a2
	add.l	d0,(a2)
	bra.s	.r
.d:	move.l	cache_on_value,d0		; CACR pour vider une entrée du cache
	and.w	#$f7f7,d0			; d'instructions (CEI) sans tout vider
	or.w	#$0004,d0
	move.l	d0,cei_value
	movem.l	(sp)+,d0-d2/a1-a2
	rts
; table a1 : « jmp » posés (a0 = base)
turbo_patch:
	movem.l	d0-d2/a1-a2,-(sp)
.t:	move.l	(a1)+,d0
	bmi.s	.done
	lea	(a0,d0.l),a2
	move.w	(a1)+,d1
	move.l	(a1)+,d2
	cmp.w	(a2),d1				; instruction attendue (pas déjà posé)
	bne.s	.t
	move.w	#$4ef9,(a2)			; jmp remplaçante
	move.l	d2,2(a2)
	addq.w	#1,turbo_count
	bra.s	.t
.done:	movem.l	(sp)+,d0-d2/a1-a2
	rts

	data
dbl_dt:		dc.l	$48a08,$4b124,$4efaa,$4efc6,$4efe2,$4f014,$4f02c,$4f044,$4f136,$4f14e
		dc.l	$4f166,$4f180,$4f198,$4f1b0,$507fe,$509ea,$50ed4,$50eec,$50f06,$50f1e
		dc.l	$50f38,$50f50,0
	text

	section	grel,data
grel_start:
	section	turbo,code
	include	"turbo.s"
	section	grel,data
grel_end:
	text

; estimation d'une durée (ticks de 5 ms) : monte aussitôt à la mesure ; elle redescend
; d'un tick par tour à l'entrée d'interp_wait (decay)
estimate:
	cmp.l	#100,d0
	bls.s	.ok
	moveq	#100,d0
.ok:	cmp.w	(a0),d0
	bls.s	.keep
	move.w	d0,(a0)
.keep:	rts

decay:	addq.w	#1,decay_n			; un tick de moins tous les 4 tours
	and.w	#3,decay_n
	bne.s	.z
	tst.w	(a0)
	beq.s	.z
	subq.w	#1,(a0)
.z:	rts

; caméra et adversaire à mi-chemin entre les tours N-1 et N
set_extrap:
	move.w	slot_k,d3			; N + (N - (N-1)) * k/6
	lea	cam_prev,a0
	lea	cam_cur,a1
	lea	G_CAM(a6),a2
	moveq	#3-1,d2
.pos:	move.l	(a1)+,d1
	move.l	d1,d0
	sub.l	(a0)+,d0
	bsr	.frac
	add.l	d1,d0
	move.l	d0,(a2)+
	dbf	d2,.pos
	moveq	#3-1,d2
.ang:	move.w	(a1)+,d1			; angles : différence sur 16 bits (tour complet)
	move.w	d1,d0
	sub.w	(a0)+,d0
	ext.l	d0
	bsr	.frac
	add.w	d1,d0
	move.w	d0,(a2)+
	dbf	d2,.ang
;
;
; adversaire : pièce et section.fraction (octet fort : section de la pièce). Le rendu le
; dessine à la position qu'il avait en entrant, puis le fait avancer d'un tour ($5079C) :
; ce qu'on relève après le rendu N est donc la position du rendu N+1, et celle relevée
; après le rendu N-1 est celle dessinée au tour N. L'image à k/6 le place entre les deux :
; position du tour précédent + avance x k/6, en passant à la pièce suivante au-delà de
; la dernière section, comme le jeu ($5081E).
	movem.l	d5-d7,-(sp)
	move.b	(a0),d6				; pièce relevée en N-1 (dessinée en N)
	move.b	(a1),d7				; pièce relevée en N
	moveq	#0,d4
	move.w	2(a0),d4
	moveq	#0,d5
	move.w	2(a1),d5
	move.l	d5,d0
	sub.l	d4,d0
	cmp.b	d6,d7
	beq.s	.adv
	move.b	d6,d1				; pièce suivante seulement
	bsr	next_piece
	cmp.b	d1,d7
	bne.s	.opp_no
	move.b	d6,d1
	bsr	piece_len			; avance = N + longueur(N-1) - (N-1)
	lsl.l	#8,d0
	add.l	d5,d0
	sub.l	d4,d0
.adv:	bmi.s	.opp_no				; en arrière ou trop grande : rien
	cmp.l	#$800,d0
	bhi.s	.opp_no
	bsr	.frac
	add.l	d0,d4				; position dessinée + avance x k/6
	move.b	d6,d1
	bsr	piece_len
	move.w	d4,d2
	lsr.w	#8,d2
	move.b	d6,d1
	cmp.w	d0,d2
	blo.s	.same
	lsl.w	#8,d0				; au-delà de la pièce : pièce suivante
	sub.w	d0,d4
	bsr	next_piece
.same:	move.b	d1,G_OPP_PIECE(a6)
	move.w	d4,G_OPP_SEC(a6)
	move.w	4(a0),d1			; position en travers : de même
	move.w	4(a1),d0
	sub.w	d1,d0
	ext.l	d0
	bsr	.frac
	add.w	d1,d0
	move.w	d0,G_OPP_LAT(a6)
.opp_no:
	movem.l	(sp)+,d5-d7
.done:	rts
.frac:	muls.l	d3,d0				; d0 = d0 * k / 6 (écarts < $02000000 : pas de débordement)
	divs.l	#6,d0
	rts

; nombre de sections de la pièce d1.b -> d0.w (comme $4D3D2 et $4D4D6 : type de la
; pièce, données du type, octet de longueur / 2 - 1) ; d2/a2 détruits
piece_len:
	moveq	#0,d2
	move.b	d1,d2
	lea	G_PIECE_TYPE(a6),a2
	move.b	(a2,d2.w),d2
	and.w	#$0f,d2
	add.w	d2,d2
	lea	G_TYPE_TAB(a6),a2
	move.w	(a2,d2.w),d0
	rol.w	#8,d0				; mot petit-boutiste (6502)
	sub.w	#$b100,d0
	and.l	#$ffff,d0
	lea	(a2,d0.l),a2
	moveq	#0,d2
	move.b	(a2),d2
	moveq	#0,d0
	move.b	(a2,d2.w),d0
	lsr.w	#1,d0
	subq.w	#1,d0
	rts

; pièce suivante de d1.b (dernière -> 0)
next_piece:
	addq.b	#1,d1
	cmp.b	G_NPIECES(a6),d1
	blo.s	.ok
	moveq	#0,d1
.ok:	rts

; image du tour N (écran de travail du jeu) -> écran a1 : le tableau de bord y est à jour
copy_frame:
; seulement ce que le rendu ne repeint pas : la fenêtre 3D (128 lignes de 128 octets,
; à écran+2576, comme G_WIN) est toujours entièrement redessinée. Et d'un tour à
; l'autre, hors de la fenêtre, seuls changent le haut du cadre (lignes 0-15) et le bas
; entre les montants (lignes 144-199, octets 16-143 : tableau de bord) : le reste
; n'est recopié qu'à la 1re utilisation de l'écran puis une fois sur 8 (9,7 Ko au lieu
; de 15,6).
	move.l	a1,d0
	sub.l	ebuf,d0
	divu.w	#SCREEN_BYTES,d0
	lea	ebuf_use,a0
	addq.b	#1,(a0,d0.w)
	move.b	(a0,d0.w),d0
	and.b	#7,d0
	cmp.b	#1,d0
	beq.s	.full
	move.l	G_DRAW(a6),a0
	move.w	#2560/16-1,d7			; lignes 0-15
	bsr.s	.cp16
	lea	144*160+16-2560(a0),a0		; lignes 144-199, octets 16-143
	lea	144*160+16-2560(a1),a1
	moveq	#56-1,d6
.p:	movem.l	(a0)+,d0-d5/a2-a3
	movem.l	d0-d5/a2-a3,(a1)
	movem.l	(a0)+,d0-d5/a2-a3
	movem.l	d0-d5/a2-a3,32(a1)
	movem.l	(a0)+,d0-d5/a2-a3
	movem.l	d0-d5/a2-a3,64(a1)
	movem.l	(a0)+,d0-d5/a2-a3
	movem.l	d0-d5/a2-a3,96(a1)
	lea	32(a0),a0
	lea	160(a1),a1
	dbf	d6,.p
	rts
.full:	move.l	G_DRAW(a6),a0
	move.w	#2576/16-1,d7			; lignes 0-15 et début de la ligne 16
	bsr.s	.cp16
	moveq	#127-1,d6			; entre deux lignes de la fenêtre : 32 octets
.g:	lea	128(a0),a0
	lea	128(a1),a1
	movem.l	(a0)+,d0-d5/a2-a3
	movem.l	d0-d5/a2-a3,(a1)
	lea	32(a1),a1
	dbf	d6,.g
	lea	128(a0),a0			; fin de la ligne 143 et lignes 144-199
	lea	128(a1),a1
	move.w	#(32000-143*160-144)/16-1,d7
.cp16:	movem.l	(a0)+,d0-d3
	movem.l	d0-d3,(a1)
	lea	16(a1),a1
	dbf	d7,.cp16
	rts

; zones de snaptab : jeu -> snapbuf, et retour
snap_save:
	lea	snaptab,a3
	lea	snapbuf,a1
.l:	move.l	(a3)+,d0
	beq.s	.done
	move.l	(a3)+,d1
	lea	-$10100(a6,d0.l),a0
	bsr.s	copy_blk
	bra.s	.l
.done:	rts

snap_restore:
	lea	snaptab,a3
	lea	snapbuf,a0
.l:	move.l	(a3)+,d0
	beq.s	.done
	move.l	(a3)+,d1
	lea	-$10100(a6,d0.l),a1
	bsr.s	copy_blk
	bra.s	.l
.done:	rts

; d1 octets de (a0)+ vers (a1)+ (le 68030 accepte les longs non alignés)
copy_blk:
	move.w	d1,d2
	lsr.w	#2,d2
	bra.s	.ln
.lp:	move.l	(a0)+,(a1)+
.ln:	dbf	d2,.lp
	and.w	#3,d1
	bra.s	.bn
.bp:	move.b	(a0)+,(a1)+
.bn:	dbf	d1,.bp
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
; mode HD (F2) et mode texturé (F3), Falcon à 68040/68060 avec FPU, moniteur VGA.
; La logique du jeu tourne sans changement ; son décor 3D est dessiné dans un écran brouillon
; (fenêtre 3D $56C78 posée par $10824 sur hd_scratch, tracé de pixel $5313E : rts), la
; fenêtre de son écran de travail est mise en couleur 1 (que le cockpit n'emploie jamais)
; avant chaque tour, et l'écran affiché est le nôtre ($10824 n'écrit plus $FFFF8201/03) :
; 640x480 en 16 couleurs, dont 400 lignes dessinées par le moteur HD (falcon/hd/hd.c, C
; compilé pour 68060, relogé ici) à partir de l'état du jeu, cockpit du jeu incrusté.
	ifeq	AUTO
HDMODE		equ	VGA|8|BPS4		; 640x480, 16 couleurs (COL80)
HD_SCRBYTES	equ	640*480/2
HD_WSBYTES	equ	1100000			; >= sizeof(struct hdws)

hd_setup:
	clr.w	hd_avail
	cmp.l	#40,cpu_cookie
	blo	.no
	tst.w	fpu_cookie			; type de FPU (mot fort) : 0 = aucune
	beq	.no
	cmp.w	#2,montype
	bne	.no
	move.w	#3,-(sp)			; TT-RAM de préférence
	move.l	#HD_WSBYTES,-(sp)
	move.w	#$44,-(sp)			; Mxalloc
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	ble	.no
	move.l	d0,hd_ws
	move.w	#3,-(sp)			; brouillon du décor du jeu
	move.l	#32768,-(sp)
	move.w	#$44,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	ble	.no
	move.l	d0,hd_scratch
	clr.w	-(sp)				; écrans : ST-RAM
	move.l	#2*HD_SCRBYTES+256,-(sp)
	move.w	#$44,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	ble	.no
	add.l	#255,d0
	and.l	#$ffffff00,d0
	move.l	d0,hd_scr
	move.l	d0,a0
	add.l	#HD_SCRBYTES,d0
	move.l	d0,hd_scr+4
	move.l	#2*HD_SCRBYTES/4-1,d1
.clr:	clr.l	(a0)+
	subq.l	#1,d1
	bpl.s	.clr
	lea	hd_blob,a0			; moteur lié en 0 : mots longs absolus relogés
	lea	hd_rel,a1
	move.l	a0,d1
.rl:	move.l	(a1)+,d0
	bmi.s	.rd
	add.l	d1,(a0,d0.l)
	bra.s	.rl
.rd:
; registres du VIDEL du mode HD, posés par le TOS : avant set_video, mode et écrans du bureau
; rétablis ensuite (le chargeur JEK du jeu efface l'écran que rend Physbase et y recopie sa
; dernière routine : Physbase doit être l'écran de set_video, posé en dernier)
	move.w	#-1,-(sp)
	move.w	#88,-(sp)			; Vsetmode(-1)
	trap	#14
	addq.l	#4,sp
	move.w	d0,-(sp)			; mode du bureau
	move.w	#3,-(sp)			; Logbase
	trap	#14
	addq.l	#2,sp
	move.l	d0,-(sp)
	move.w	#2,-(sp)			; Physbase
	trap	#14
	addq.l	#2,sp
	move.l	d0,-(sp)
	move.w	#HDMODE,-(sp)
	move.w	#3,-(sp)
	move.l	hd_scr,-(sp)
	move.l	hd_scr,-(sp)
	move.w	#5,-(sp)			; Setscreen
	trap	#14
	lea	14(sp),sp
	move.w	#37,-(sp)			; Vsync
	trap	#14
	addq.l	#2,sp
	move.l	#hd_vregs,vsave_ptr
	pea	videl_save(pc)
	move.w	#38,-(sp)
	trap	#14
	addq.l	#6,sp
	move.l	(sp)+,d1			; écrans et mode du bureau
	move.l	(sp)+,d0
	move.w	(sp)+,d2
	move.w	d2,-(sp)
	move.w	#3,-(sp)
	move.l	d1,-(sp)
	move.l	d0,-(sp)
	move.w	#5,-(sp)
	trap	#14
	lea	14(sp),sp
	move.w	#1,hd_avail
.no:	rts

; registres du VIDEL -> (vsave_ptr)
videl_save:
	move.l	vsave_ptr,a0
	move.l	$ffff8282.w,(a0)+
	move.l	$ffff8286.w,(a0)+
	move.l	$ffff828a.w,(a0)+
	move.l	$ffff828e.w,(a0)+
	move.l	$ffff82a2.w,(a0)+
	move.l	$ffff82a6.w,(a0)+
	move.l	$ffff82aa.w,(a0)+
	move.w	$ffff820a.w,(a0)+
	move.w	$ffff82c0.w,(a0)+
	move.w	$ffff8266.w,(a0)+
	move.b	$ffff8260.w,(a0)+
	clr.b	(a0)+
	move.w	$ffff82c2.w,(a0)+
	move.w	$ffff8210.w,(a0)+
	move.w	$ffff820e.w,(a0)+
	rts
; a0 = registres, d0.w = 0 : mode Falcon, sinon compatible ST (interruptions coupées)
videl_load:
	move.l	(a0)+,$ffff8282.w
	move.l	(a0)+,$ffff8286.w
	move.l	(a0)+,$ffff828a.w
	move.l	(a0)+,$ffff828e.w
	move.l	(a0)+,$ffff82a2.w
	move.l	(a0)+,$ffff82a6.w
	move.l	(a0)+,$ffff82aa.w
	move.w	(a0)+,$ffff820a.w
	move.w	(a0)+,$ffff82c0.w
	clr.w	$ffff8266.w
	tst.w	d0
	bne.s	.st
	move.w	(a0),$ffff8266.w
	bra.s	.c
.st:	move.b	2(a0),$ffff8260.w
.c:	move.w	4(a0),$ffff82c2.w
	move.w	6(a0),$ffff8210.w
	move.w	8(a0),$ffff820e.w
	rts

; adresse d'écran d0 -> registres vidéo
set_vbase:
	move.l	d0,-(sp)
	lsr.l	#8,d0
	move.b	d0,$ffff8203.w
	lsr.w	#8,d0
	move.b	d0,$ffff8201.w
	move.l	(sp)+,d0
	move.b	d0,$ffff820d.w			; après $8201/03 (qui le remettent à 0)
	rts

; modifications du jeu en mode HD : décalage, longueur, premier mot attendu (0 : non
; vérifié), nouveaux octets
; (les remplissages du décor ne sont pas neutralisés : ils remettent à zéro les listes de
; bords que le tracé des bords fait avancer ; sans eux, ces listes écrasaient le jeu)
hd_patches:
	dc.l	$5313e-$10100			; tracé de pixel (ou t_pixel)
	dc.w	2,0
	dc.b	$4e,$75,0,0,0,0
	dc.l	$10824-$10100			; move.l $56C74,d3 -> move.l #hd_scratch,d3 : fenêtre 3D
	dc.w	6,$2639				; ($56C78 = d3 + $A10) dans le brouillon
hd_scr_imm:
	dc.b	$26,$3c,0,0,0,0
	dc.l	$1083e-$10100			; adresse d'écran : n'est plus écrite
	dc.w	6,$13c0
	dc.b	$4e,$71,$4e,$71,$4e,$71
	dc.l	$10846-$10100
	dc.w	6,$13c0
	dc.b	$4e,$71,$4e,$71,$4e,$71

; passage en mode HD (a6 = base du jeu) ; d0 = 0 si fait
hd_enter:
	movem.l	d1-d3/a0-a2,-(sp)
	tst.w	hd_inited
	bne.s	.i
	move.l	hd_ws,-(sp)
	move.l	a6,d0
	sub.l	#$10100,d0
	move.l	d0,-(sp)
	bsr	hd_call0
	addq.l	#8,sp
	tst.l	d0
	bne	.fail
	move.w	#1,hd_inited
.i:	move.l	hd_scratch,hd_scr_imm+2		; (TEXT : modifiable)
	lea	hd_patches(pc),a1		; tout vérifier avant de rien modifier
	moveq	#HD_NPATCH-1,d3
.v:	move.l	(a1),d0
	move.w	6(a1),d1
	beq.s	.vn
	cmp.w	(a6,d0.l),d1
	bne	.fail
.vn:	lea	14(a1),a1
	dbf	d3,.v
	move.w	sr,-(sp)
	or.w	#$0700,sr
	lea	hd_patches(pc),a1
	lea	hd_save,a2
	moveq	#HD_NPATCH-1,d3
.p:	move.l	(a1)+,d0
	lea	(a6,d0.l),a0
	move.w	(a1)+,d1
	addq.l	#2,a1
	subq.w	#1,d1
	moveq	#0,d2
.pb:	move.b	(a0,d2.w),(a2,d2.w)
	move.b	(a1,d2.w),(a0,d2.w)
	addq.w	#1,d2
	dbf	d1,.pb
	addq.l	#6,a1
	addq.l	#8,a2
	dbf	d3,.p
	bsr	flush_ic
	lea	hd_vregs,a0
	moveq	#0,d0
	bsr	videl_load
	bsr	hd_palette
	clr.w	hd_cur
	move.l	hd_scr,d0
	bsr	set_vbase
	move.w	#1,hd_on
	clr.w	hd_idle
	move.w	(sp)+,sr
	moveq	#0,d0
	bra.s	.out
.fail:	clr.w	hd_avail			; version du jeu inattendue : plus de HD
	clr.b	hd_req
	moveq	#-1,d0
.out:	movem.l	(sp)+,d1-d3/a0-a2
	rts

; retour au jeu d'origine (aussi depuis la VBL)
hd_leave:
	movem.l	d0-d3/a0-a2/a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	game_base,a6
	lea	hd_patches(pc),a1
	lea	hd_save,a2
	moveq	#HD_NPATCH-1,d3
.p:	move.l	(a1)+,d0
	lea	(a6,d0.l),a0
	move.w	(a1)+,d1
	addq.l	#8,a1
	subq.w	#1,d1
	moveq	#0,d2
.pb:	move.b	(a2,d2.w),(a0,d2.w)
	addq.w	#1,d2
	dbf	d1,.pb
	addq.l	#8,a2
	dbf	d3,.p
	bsr	flush_ic
	lea	st_vregs,a0
	moveq	#1,d0
	bsr	videl_load
	move.l	G_DRAW(a6),d0			; fenêtre 3D : de nouveau dans l'écran du jeu
	add.l	#$a10,d0
	move.l	d0,G_WIN(a6)
	move.l	G_DISP(a6),d0
	bsr	set_vbase
	clr.w	hd_on
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d3/a0-a2/a6
	rts

; VBL en mode HD : palette du jeu (table de course $6EA3C, format STE) dans le VIDEL ;
; plus de tour de jeu depuis une seconde (menus) : retour au jeu d'origine
hd_vbl:
	tst.w	hd_busy				; image HD en cours : le tour n'est pas fini
	bne.s	hd_palette
	addq.w	#1,hd_idle
	cmp.w	#50,hd_idle
	blo.s	hd_palette
	bra	hd_leave
hd_palette:
	movem.l	d0-d2/a0-a1,-(sp)
	move.l	game_base,a0
	add.l	#$6ea3c-$10100,a0
	lea	$ffff9800.w,a1
	moveq	#16-1,d2
.c:	move.w	(a0)+,d0
	moveq	#0,d1
	rol.w	#8,d0				; rouge
	bsr.s	.n
	lsl.l	#8,d1
	rol.w	#4,d0				; vert
	bsr.s	.n
	lsl.l	#8,d1
	lsl.l	#8,d1
	rol.w	#4,d0				; bleu
	bsr.s	.n
	move.l	d1,(a1)+
	dbf	d2,.c
	movem.l	(sp)+,d0-d2/a0-a1
	rts
; quartet STE (bits 2-0 + bit 3 de poids faible) de d0 -> 6 bits forts de l'octet faible de d1
.n:	move.w	d0,-(sp)
	and.w	#15,d0
	add.w	d0,d0
	btst	#4,d0
	beq.s	.n1
	or.w	#1,d0
.n1:	and.w	#15,d0
	mulu.w	#17,d0
	and.w	#$fc,d0
	or.b	d0,d1
	move.w	(sp)+,d0
	rts

; à chaque tour (tick_hook, a6 = base du jeu) : mode demandé, image HD
hd_tick:
	movem.l	d0-d1/a0-a1,-(sp)
	clr.w	hd_idle
	tst.w	hd_on
	bne.s	.on
	tst.b	hd_req
	beq	.out
	bsr	hd_enter
	tst.l	d0
	bne	.out
.on:	tst.b	hd_req
	bne.s	.draw
	bsr	hd_leave
	bra	.out
.draw:	tst.b	G_COUNTER(a6)			; tour déjà débordé : image HD sautée (le jeu
	bne.s	.go				; garde sa vitesse), au plus 3 de suite
	addq.w	#1,hd_skip
	cmp.w	#4,hd_skip
	blo.s	.out
.go:	clr.w	hd_skip
	move.w	hd_cur,d0			; écran caché
	eor.w	#1,d0
	lea	hd_scr,a0
	move.l	(a0,d0.w*4),a0
	add.l	#40*320,a0			; 400 lignes centrées
	moveq	#0,d1
	move.b	hd_req,d1
	move.l	d1,-(sp)			; 1 : HD, 2 : texturé
	move.l	a0,-(sp)
	move.l	G_DISP(a6),-(sp)		; image précédente du jeu, roues comprises (VBL)
	move.w	#1,hd_busy
	bsr	hd_call1
	clr.w	hd_busy
	lea	12(sp),sp
	bsr	flush_ic			; cache de données écrit en ST-RAM (VIDEL)
	move.w	hd_cur,d0
	eor.w	#1,d0
	move.w	d0,hd_cur
	lea	hd_scr,a0
	move.l	(a0,d0.w*4),d0
	bsr	set_vbase
.out:	movem.l	(sp)+,d0-d1/a0-a1
	rts

; après l'échange (mode HD) : fenêtre 3D de l'écran de travail en couleur 1 (plan 0), le
; cockpit y sera dessiné par le jeu ; registres et drapeaux rendus par l'attente gardés
hd_postwait:
	move.w	ccr,-(sp)
	movem.l	d0-d2/a0/a6,-(sp)
	move.l	game_base,a6
	move.l	G_DRAW(a6),a0
	add.l	#$a10,a0
	move.l	#$ffff0000,d1
	moveq	#0,d2
	moveq	#128-1,d0
.l:	rept	16
	move.l	d1,(a0)+
	move.l	d2,(a0)+
	endr
	lea	160-128(a0),a0
	dbf	d0,.l
	movem.l	(sp)+,d0-d2/a0/a6
	move.w	(sp)+,ccr
	rts

; appels du moteur (C) sur notre pile : arguments recopiés, d2-d7/a2-a6 gardés par lui
hd_call0:
	lea	hd_blob,a0
	bra.s	hd_call
hd_call1:
	lea	hd_blob+4,a0
hd_call:
	move.l	sp,a1
	move.l	sp,hd_sp
	lea	hd_stack,sp
	move.l	12(a1),-(sp)
	move.l	8(a1),-(sp)
	move.l	4(a1),-(sp)
	jsr	(a0)
	move.l	hd_sp,sp
	rts

	section	hdblob,data
	even
hd_blob:	incbin	"../hd/hd.bin"
		even
hd_rel:		include	"../hd/hdrel.s"
	text
	endc

; ---------------------------------------------------------------------------
	ifeq	AUTO
; GAME.PUT est chargé (Pexec 3), son chargeur JEK corrigé pour l'adressage 32 bits, puis
; lancé (Pexec 6 : mémoire rendue à la fin). Le chargeur écrit la palette en $0FFF8240,
; qui n'est $FF8240 qu'en adressage 24 bits (Falcon d'origine) : en 32 bits (CT60, TT-RAM)
; c'est une erreur de bus. $FFFF8240 convient aux deux.
run_game:
	move.l	#null_env,-(sp)			; environnement vide
	pea	null_cmd
	pea	game_name
	move.w	#3,-(sp)			; charger seulement
	move.w	#$4b,-(sp)			; Pexec
	trap	#1
	lea	16(sp),sp
	move.l	d0,exec_result
	bmi.s	.out
	move.l	d0,a0
	move.l	8(a0),a1			; TEXT
	lea	jek_tab(pc),a2
.p:	move.w	(a2)+,d1			; décalage de l'adresse, opcode attendu avant
	beq.s	.run
	move.w	(a2)+,d2
	cmp.w	-2(a1,d1.w),d2
	bne.s	.p
	cmp.l	#$0fff8240,(a1,d1.w)
	bne.s	.p
	move.l	#$ffff8240,(a1,d1.w)
	addq.w	#1,jek_count
	bra.s	.p
.run:	move.l	a0,-(sp)
	pea	flush_sup(pc)			; code écrit : caches
	move.w	#38,-(sp)			; Supexec
	trap	#14
	addq.l	#6,sp
	move.l	(sp)+,a0
	clr.l	-(sp)
	move.l	a0,-(sp)			; basepage
	clr.l	-(sp)
	move.w	#6,-(sp)			; lancer, puis libérer
	move.w	#$4b,-(sp)
	trap	#1
	lea	16(sp),sp
	move.l	d0,exec_result
.out:	rts
flush_sup:
	bra	flush_ic
; JEK : « move.w $1de(pc),$0FFF8240 », « move.w $0FFF8240,(a2) », « move.w a2,$0FFF8240 »
jek_tab:	dc.w	$80,$01de,$172,$34b9,$216,$33ca,0

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
	dc.b	"Alternate: pas de correction 60 Hz",13,10
	dc.b	"(O dans SCRF030.INF : jeu d'origine)",13,10,0
txt_opts:
	dc.b	"Options :",0
txt_o8:	dc.b	" 8MHz",0
txt_oc:	dc.b	" caches",0
txt_on:	dc.b	" 60Hz",0
txt_oo:	dc.b	" origine",0
txt_ot:	dc.b	" sans-turbo",0
txt_of:	dc.b	" fluide",0
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
dt_cur:	dc.b	$ee				; facteur de pas posé sur les 22 sites
	even
	include	"snaptab.s"
	ifd	DBG
dbg_magic:	dc.l	'HIST','HIST'
dbg_ptr:	dc.l	dbg_ring
dbg_e:		dc.l	0
dbg_ring:	dcb.l	256,0
dbg_end:
	endc

; ---------------------------------------------------------------------------
	bss

basepage:	ds.l	1
keep_size:	ds.l	1
options:	ds.w	1
is_falcon:	ds.w	1
addr32:		ds.w	1
montype:	ds.w	1
snd_cookie:	ds.l	1
cpu_cookie:	ds.l	1
fpu_cookie:	ds.l	1
old_mode:	ds.w	1
new_mode:	ds.w	1
old_phys:	ds.l	1
old_log:	ds.l	1
screen:		ds.l	1
exec_result:	ds.l	1
jek_count:	ds.w	1
old_vbl_m:	ds.l	1
vbl_count:	ds.l	1
vbl_per_halfsec: ds.w	1
hz60:		ds.w	1
sound_saved:	ds.w	1
old_adderin:	ds.w	1
old_adcinput:	ds.w	1
hw_installed:	ds.w	1
is_030:		ds.w	1
is_060:		ds.w	1			; 68040 ou 68060
old_cacr:	ds.l	1
old_vbr:	ds.l	1
old_busctrl:	ds.w	1
old_byte_ff:	ds.w	1
priv_count:	ds.l	1
div60:		ds.w	1
vbl_ticks:	ds.l	1
last_vbl70:	ds.l	1
game_ok:	ds.w	1
game_base:	ds.l	1
render_addr:	ds.l	1
wait_addr:	ds.l	1
cache_on_value:	ds.l	1
icache_on:	ds.w	1
interp_on:	ds.w	1
kj_prev:	ds.b	1
f1_prev:	ds.b	1
dbl_req:	ds.b	1
dbl_on:		ds.b	1
		even
yaw_mul:	ds.w	1
chr_rem:	ds.w	1
dt_rem:		ds.w	1
hd_avail:	ds.w	1
hd_on:		ds.w	1
hd_inited:	ds.w	1
hd_idle:	ds.w	1
hd_busy:	ds.w	1
hd_skip:	ds.w	1
hd_cur:		ds.w	1
hd_ws:		ds.l	1
hd_scratch:	ds.l	1
hd_scr:		ds.l	2
hd_sp:		ds.l	1
vsave_ptr:	ds.l	1
hd_vregs:	ds.w	32
st_vregs:	ds.w	32
hd_save:	ds.b	8*HD_NPATCH
hd_req:		ds.b	1
f2_prev:	ds.b	1
f3_prev:	ds.b	1
		even
cnt_real:	ds.w	1
lvl_set:	ds.l	1
dbl_max:	ds.b	1
dbl_good:	ds.b	1
		even
have_prev:	ds.w	1
last_call:	ds.l	1
interp_count:	ds.l	1
	ifd	SELFCHECK
chk_magic:	ds.l	1
chk_ok:		ds.l	1
chk_bad:	ds.l	1
chk_in:		ds.l	15
chk_out:	ds.l	15
chk_outA:	ds.l	15
chk_srin:	ds.w	1
chk_sr:		ds.w	1
chk_srA:	ds.w	1
chk_z:		ds.l	2*4+1
chk_fo:		ds.l	1
chk_fnew:	ds.l	1
chk_fn:		ds.l	1
chk_m0:		ds.b	32000
chk_m1:		ds.b	32000
	endc
grel_delta:	ds.l	1
cei_value:	ds.l	1
pix_col:	ds.b	1			; couleur des opcodes du pixel ($5313E)
pix_chg:	ds.b	1
tr_a1:		ds.l	1
tr_d0:		ds.l	1
tr_d3:		ds.l	1
render_sp:	ds.l	1
abort_pc:	ds.l	1
in_render:	ds.w	1
render_aborted:	ds.w	1
decay_n:	ds.w	1
turbo_count:	ds.w	1
ebuf:		ds.l	1
ebuf_par:	ds.w	1
ebuf_use:	ds.b	4			; utilisations de chaque écran
stg_ready:	ds.w	1
stg_q:		ds.w	1			; file préparée : 0 ou 1
stg_q0:		ds.w	1			; nombre d'images,
		ds.b	2			;   valeurs du compteur,
		ds.l	2			;   écrans
stg_q1:		ds.w	1
		ds.b	2
		ds.l	2
STG_BYTES	equ	12
act_i:		ds.w	1
act_n:		ds.w	1
act_c:		ds.b	2			; file active
act_a:		ds.l	2
save_draw:	ds.l	1
t_start:	ds.l	1
slot_k:		ds.w	1
est_interp:	ds.w	1
save_win:	ds.l	1
CAM_BYTES	equ	18+2+2+2		; caméra, pièce (x2), section, travers de l'adversaire
cam_cur:	ds.b	CAM_BYTES
cam_prev:	ds.b	CAM_BYTES
snapbuf:	ds.b	SNAP_BYTES+16
old_stpal:	ds.w	16
old_fpal:	ds.l	256
inf_buf:	ds.b	64
		ds.l	2
vectab:		ds.l	256			; nouvelle table (VBR), alignée sur 4
relays:		ds.w	3*256
		ds.l	512
stack_top:	ds.l	1
	ifeq	AUTO
		ds.l	4096			; pile du moteur HD (C)
hd_stack:	ds.l	1
	endc
; sous l'écran, au moins 32000 octets sans rien d'utile au chargement : le second chargeur
; du jeu y recopie sa routine de relogement (Physbase - $7D00, haut de la RAM sur un ST)
ebuf_mem:	ds.b	4*SCREEN_BYTES+256		; 4 écrans (32000 = 125*256 : alignés)
screen_mem:	ds.b	SCREEN_AREA+256
	ifd	PAD				; essais : décale l'adresse de chargement du jeu
		ds.b	PAD
	endc

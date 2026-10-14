; ---------------------------------------------------------------------------
; turbo.s - routines du jeu réécrites pour le 68030 (incluses par scrf030.s)
;
; Chaque routine remplace l'originale (« jmp » posé à son entrée par turbo_install)
; et rend EXACTEMENT le même résultat : mêmes octets écrits en mémoire, mêmes registres
; au retour, y compris les mots forts. Vérifié par falcon/test/bench (Musashi : routine
; d'origine contre routine réécrite sur des centaines de milliers d'entrées) puis dans
; le jeu sous Hatari (mêmes images, même partie). Les cas rares retournent au code
; d'origine, avant toute écriture.
;
; Adresses du jeu : écrites ici pour une base TEXT à $10100 (comme dans la doc) ;
; GREL marque le mot long qui précède comme adresse du jeu, à reloger par
; turbo_install selon la base réelle.
; ---------------------------------------------------------------------------

GREL	macro
.g\@	equ	*-4
	section	grel,data
	dc.l	.g\@
	section	turbo,code
	endm

; tracé d'un bord de polygone ($5353C) : sommets d1, d2 (indices de mot dans les
; tables X $6EC5C et Y $6ED9C), entrée du bord n° ($54D04) dans la table $702B8 ;
; écrit l'en-tête (y0, y1, x0, x1) puis un x par ligne de y0-1 à y1 (mot $8000 à la
; fin) à partir de ($54D00), qu'il fait avancer.
; Original : Bresenham pas à pas en x (bords plus larges que hauts : une boucle de
; 5 instructions par pixel) ; ici un pas par LIGNE, x = x0 + ceil(((j-1)*dx+f)/dy)
; avec f = dx/2+1, ce qui donne les mêmes x. L'erreur finale du Bresenham (d3) est
; celle de départ, x et y finissent sur (x1, y1).
	section	turbo,code
t_edge:
	move.l	($54d00).l,a0
	GREL
	cmp.l	#$72c50,a0			; table des bords pleine (original)
	GREL
	bge	t_edge_slow
	move.l	#$6ec5c,a4
	GREL
	move.l	#$6ed9c,a5
	GREL
	move.w	(a4,d1.w),d4
	move.w	(a4,d2.w),d6
	move.w	(a5,d1.w),d5
	move.w	(a5,d2.w),d7
	move.w	d4,d0				; hors de la fenêtre (x >= 256, y >= 128) :
	or.w	d6,d0				; découpage (original)
	and.w	#$ff00,d0
	bne	t_edge_slow
	move.w	d5,d0
	or.w	d7,d0
	and.w	#$ff80,d0
	bne	t_edge_slow
	move.l	#$702b8,a1
	GREL
	clr.w	($5353a).l
	GREL
	move.w	#-1,($53536).l
	GREL
	move.w	($54d04).l,d0
	GREL
	move.l	a0,(a1,d0.w)
	move.l	a0,a2
	addq.l	#8,a0
	cmp.w	d7,d5
	bge.s	.down
	exg	d7,d5
	exg	d6,d4
	or.b	#64,(a1,d0.w)
.down:	moveq	#0,d0				; comme l'original en $53ACA (mot fort nul)

; tracé proprement dit ($53ACA, atteint aussi après découpage d'un bord) : d4, d5 =
; x0, y0 et d6, d7 = x1, y1 (y0 >= y1), a2 = en-tête, a0 = x par ligne ; en-tête y
; écrit si ($5353A) >= 0 ; après les x, ($53536)+1 fois le mot ($53538) si
; ($53536) >= 0. a1 et le mot fort de d0 restent ceux de l'entrée, comme l'original.
; Un seul code pour les deux sens (d0 = pas de x, +1 ou -1). Drapeau X à la sortie :
; 0 dans tous les cas, comme le Bresenham d'origine (dernière retenue nulle).
t_trace:
	move.w	d5,d2
	sub.w	d7,d2				; dy
	move.w	d4,d1
	sub.w	d6,d1				; x0 - x1
	move.w	d1,d3
	bpl.s	.ab
	neg.w	d3
.ab:	cmp.w	#1024,d3			; hors des plages prévues : original
	bhs	.orig
	cmp.w	#1024,d2
	bhs	.orig
	move.l	a1,tr_a1
	move.l	d0,tr_d0
	tst.w	($5353a).l
	GREL
	bmi.s	.nh
	move.w	d5,(a2)				; en-tête
	move.w	d7,2(a2)
.nh:	move.w	d4,4(a2)
	move.w	d6,6(a2)
	moveq	#1,d0				; pas de x : +1 si x0 < x1
	neg.w	d1
	bpl.s	.dx
	neg.w	d1
	moveq	#-1,d0
.dx:	cmp.w	d2,d1				; d1 = dx
	bhs	.xmaj
	move.w	d2,d3				; plus haut que large : Bresenham d'origine
	lsr.w	#1,d3
	not.w	d3
	move.w	d2,d5
	subq.w	#1,d5
.yl:	move.w	d4,(a0)+
	add.w	d1,d3
	bcc.s	.yn
	sub.w	d2,d3
	add.w	d0,d4
.yn:	dbf	d5,.yl
.end:	and.b	#$ef,ccr
	move.l	tr_d0,d0
	move.w	($53536).l,d0			; prolongement du bord (découpage)
	GREL
	bmi.s	.nf
	move.w	($53538).l,d1
	GREL
.f:	move.w	d1,(a0)+
	dbf	d0,.f
.nf:	move.w	#$8000,(a0)+
	move.l	a0,($54d00).l
	GREL
	move.l	tr_a1,a1
	move.w	d6,d4				; fin du bord : (x1, y1)
	move.w	d7,d5
	clr.w	d1
	clr.w	d2
	rts
; plus large que haut : le j-ième x est x0 +- k_j, k_j = ceil(((j-1)*dx + f)/dy),
; f = dx/2 + 1 ; s = k_j*dy - (j-1)*dx - f (0 <= s < dy) ; dx = q*dy + r. Erreur d3 du
; Bresenham d'origine à la sortie : ~(dx/2), celle du départ.
.xmaj:	move.w	d1,d3
	lsr.w	#1,d3
	not.w	d3
	move.l	d3,tr_d3
	tst.w	d2
	beq.s	.xend				; horizontal : aucun x
	lea	(a0,d2.w*2),a1			; fin des x
	moveq	#0,d3
	move.w	d1,d3
	lsr.w	#1,d3
	addq.w	#1,d3				; f
	divu.w	d2,d3				; reste : quotient
	swap	d3
	move.w	d3,d5
	beq.s	.x0
	sub.w	d2,d5
	neg.w	d5				; s = dy - reste
	add.l	#$10000,d3			; k1 = quotient + 1
.x0:	swap	d3
	tst.w	d0
	bpl.s	.x1
	neg.w	d3
.x1:	add.w	d3,d4				; x0 +- k1
	move.w	d4,(a0)+
	moveq	#0,d3
	move.w	d1,d3
	divu.w	d2,d3				; r : q
	swap	d3
	move.w	d3,d1				; r
	swap	d3				; q
	tst.w	d0
	bpl.s	.x2
	neg.w	d3				; -q si x décroît
.x2:	cmp.l	a1,a0
	beq.s	.xend
.xl:	sub.w	d1,d5				; s -= r
	bcs.s	.xc
	add.w	d3,d4				; x +- q
	move.w	d4,(a0)+
	cmp.l	a1,a0
	bne.s	.xl
	bra.s	.xend
.xc:	add.w	d2,d5				; s += dy, x +- (q+1)
	add.w	d3,d4
	add.w	d0,d4
	move.w	d4,(a0)+
	cmp.l	a1,a0
	bne.s	.xl
.xend:	move.l	tr_d3,d3
	bra	.end
.orig:	move.w	d5,d2				; instructions déplacées par le « jmp »
	sub.w	d7,d2
	move.w	d4,d1
	jmp	($53ad0).l
	GREL
t_edge_slow:
	move.l	#$702b8,a1			; instruction déplacée par le « jmp »
	GREL
	jmp	($53542).l			; puis le code d'origine
	GREL

; sprite masqué du cockpit ($56762) : d0.b = n° du sprite. Par bloc de 16 pixels :
; masque (mot), puis 2 mots longs de plans ; écran = (écran ET masque) OU sprite.
; Original : lecture et écriture de l'écran pour chaque bloc. Ici : masque nul (bloc
; opaque) -> le sprite est écrit sans lire l'écran ; masque plein et plans nuls ->
; rien à écrire. Préparation identique à l'original (registres, drapeau X) ; d0 final =
; dernier mot long écrit, relu.
	section	turbo,code
t_sprite:
	move.l	d5,-(sp)
	move.w	d1,-(sp)
	andi.w	#255,d0
	asl.w	#2,d0
	move.l	#$73298,a1
	GREL
	move.l	(a1,d0.w),a1
	asl.w	#2,d0
	move.l	#$5692c,a2
	GREL
	lea	4(a2,d0.w),a2
	move.w	4(a2),d0
	move.w	6(a2),d3
	move.l	($56c74).l,a0
	GREL
	andi.l	#255,d0
	andi.l	#255,d3
	asl.l	#3,d0
	add.l	d0,a0
	move.l	d3,d0
	asl.l	#2,d0
	add.l	d0,d3
	asl.l	#5,d3
	add.l	d3,a0
	move.w	(a2),d1
	move.w	2(a2),d4
.row:	move.l	a0,a2
	move.w	d1,d3
.c:	move.w	(a1)+,d5
	beq.s	.op
	cmp.w	#-1,d5
	beq.s	.tr
	move.w	d5,d0				; masque sur les deux mots
	swap	d5
	move.w	d0,d5
	move.l	(a0),d0
	and.l	d5,d0
	or.l	(a1)+,d0
	move.l	d0,(a0)+
	move.l	(a0),d0
	and.l	d5,d0
	or.l	(a1)+,d0
	move.l	d0,(a0)+
	dbf	d3,.c
	bra.s	.next
.op:	move.l	(a1)+,(a0)+
	move.l	(a1)+,(a0)+
	dbf	d3,.c
	bra.s	.next
.tr:	move.l	(a1)+,d0
	beq.s	.t1
	or.l	d0,(a0)
.t1:	addq.l	#4,a0
	move.l	(a1)+,d0
	beq.s	.t2
	or.l	d0,(a0)
.t2:	addq.l	#4,a0
	dbf	d3,.c
.next:	lea	160(a2),a0
	dbf	d4,.row
	move.l	4(a2,d1.w*8),d0			; dernier mot long écrit
	move.w	(sp)+,d1
	move.l	(sp)+,d5
	rts

	ifd	SELFCHECK
; ---------------------------------------------------------------------------
; contrôle dans le jeu (assemblage avec -DSELFCHECK=1) : chaque appel exécute
; l'original puis la remplaçante sur les mêmes entrées (registres, CCR, mémoire) et
; compare registres, CCR et zone mémoire écrite ; appels conformes et écarts comptés
; dans chk_ok et chk_bad (repérés par 'CHK!' en mémoire). Le résultat rendu au jeu est
; celui de la remplaçante.
t_edge_chk:
	movem.l	d0-d7/a0-a6,chk_in
	move.w	ccr,chk_srin
	lea	chk_z,a0			; zones : tampon des bords, pointeur, drapeaux,
	move.l	($54d00).l,(a0)+		;   entrée de la table des bords
	GREL
	move.l	#640,(a0)+
	move.l	#$54d00,(a0)+
	GREL
	move.l	#4,(a0)+
	move.l	#$53536,(a0)+
	GREL
	move.l	#6,(a0)+			; $53536, $53538, $5353A
	moveq	#0,d0
	move.w	($54d04).l,d0
	GREL
	ext.l	d0
	add.l	#$702b8,d0
	GREL
	move.l	d0,(a0)+
	move.l	#4,(a0)+
	clr.l	(a0)
	move.l	#t_edge_slow,chk_fo
	move.l	#t_edge,chk_fnew
	bra.s	chk_both
t_sprite_chk:
	movem.l	d0-d7/a0-a6,chk_in
	move.w	ccr,chk_srin
	lea	chk_z,a0
	move.l	($56c74).l,(a0)+		; écran de travail entier
	GREL
	move.l	#32000,(a0)+
	clr.l	(a0)
	move.l	#t_sprite_o,chk_fo
	move.l	#t_sprite,chk_fnew
chk_both:
	lea	chk_m0,a1			; zones -> m0
	moveq	#0,d1
	bsr	chk_zones
	move.l	chk_fo,a5			; original
	bsr	chk_run
	lea	chk_out,a0
	lea	chk_outA,a1
	moveq	#15-1,d0
.c1:	move.l	(a0)+,(a1)+
	dbf	d0,.c1
	move.w	chk_sr,chk_srA
	lea	chk_m1,a1			; zones (résultat de l'original) -> m1
	moveq	#0,d1
	bsr	chk_zones
	lea	chk_m0,a1			; m0 -> zones
	moveq	#1,d1
	bsr	chk_zones
	move.l	chk_fnew,a5			; remplaçante
	bsr	chk_run
	lea	chk_out,a0			; comparaison
	lea	chk_outA,a1
	moveq	#15-1,d0
.c2:	cmp.l	(a0)+,(a1)+
	bne.s	.bad
	dbf	d0,.c2
	move.w	chk_sr,d0
	move.w	chk_srA,d1
	eor.w	d1,d0
	and.w	#$1f,d0
	bne.s	.bad
	lea	chk_m1,a1
	lea	chk_z,a2
.z3:	move.l	(a2)+,a0
	move.l	a0,d0
	beq.s	.okz
	move.l	(a2)+,d0
.c3:	cmp.l	#4,d0
	blo.s	.c4
	cmp.l	(a0)+,(a1)+
	bne.s	.bad
	subq.l	#4,d0
	bra.s	.c3
.c4:	subq.l	#1,d0
	bmi.s	.z3
	cmp.b	(a0)+,(a1)+
	bne.s	.bad
	bra.s	.c4
.okz:	addq.l	#1,chk_ok
	bra.s	.ret
.bad:	addq.l	#1,chk_bad
.ret:	movem.l	chk_out,d0-d7/a0-a6
	move.w	chk_sr,ccr
	rts
chk_run:					; a5 = routine ; registres et CCR d'entrée
	move.l	a5,chk_fn
	movem.l	chk_in,d0-d7/a0-a6
	move.w	chk_srin,ccr
	jsr	([chk_fn])
	move.w	ccr,chk_sr
	movem.l	d0-d7/a0-a6,chk_out
	rts
; zones de chk_z <-> tampon (a1) : d1 = 0 zones -> tampon, 1 tampon -> zones
chk_zones:
	lea	chk_z,a2
.z:	move.l	(a2)+,a0
	move.l	a0,d0
	beq.s	.done
	move.l	(a2)+,d0
	tst.w	d1
	beq.s	.l
	exg	a0,a1
.l:	cmp.l	#4,d0				; mots longs, puis octets
	blo.s	.b
	move.l	(a0)+,(a1)+
	subq.l	#4,d0
	bra.s	.l
.b:	subq.l	#1,d0
	bmi.s	.n
	move.b	(a0)+,(a1)+
	bra.s	.b
.n:	tst.w	d1
	beq.s	.z
	exg	a0,a1
	bra.s	.z
.done:	rts
; l'original du sprite, son entrée étant occupée par le « jmp » : instructions déplacées
t_sprite_o:
	move.l	d5,-(sp)
	move.w	d1,-(sp)
	andi.w	#255,d0
	jmp	($5676a).l
	GREL
	endc

; boucles par ligne du remplissage des polygones ($552C0, dans $55100) et des triangles
; ($53304, dans $53284) : les MÊMES instructions dans le même ordre, mais disposées pour
; que le chemin courant tienne dans le cache d'instructions du 68030 (256 octets) ; les
; cas rares (changement de bord, ligne particulière) repartent dans le code d'origine,
; à l'instruction exacte, qui revient ensuite ici.
	section	turbo,code
t_lines55:
.L:	move.w	($10a44).l,d0
	GREL
	cmp.w	($5662e).l,d0
	GREL
	beq	.c1
	move.w	(a0)+,d4			; x gauche
	bmi	.c2
	move.w	(a3)+,d5			; x droit
	bmi	.c3
	cmp.w	d4,d5
	bgt.s	.sp
	beq	.next
	jmp	($5538a).l
	GREL
.c1:	jmp	($552d0).l			; ligne où les bords changent
	GREL
.c2:	jmp	($55320).l			; bord gauche suivant
	GREL
.c3:	jmp	($55354).l			; bord droit suivant
	GREL
.sp:	move.w	d4,d1				; tracé d'une ligne, de x = d4 à d5
	andi.w	#240,d1
	lsr.w	#1,d1
	lea	(a6,d1.w),a4
	move.w	d4,d3
	move.w	d5,d1
	lsr.w	#4,d3
	lsr.w	#4,d1
	sub.w	d3,d1
	beq	.one
	subq.b	#1,d1				; plusieurs blocs de 16 pixels
	andi.w	#15,d4
	beq.s	.mid
	asl.w	#2,d4
	move.l	(a5,d4.w),d4
	move.l	d6,d2
	move.l	d7,d3
	and.l	d4,d2
	and.l	d4,d3
	not.l	d4
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d2,d0
	move.l	d0,(a4)+
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d3,d0
	move.l	d0,(a4)+
	bra.s	.dbf
.mid:	move.l	d6,(a4)+
	move.l	d7,(a4)+
.dbf:	dbf	d1,.mid
	andi.w	#15,d5
	beq.s	.next
	asl.w	#2,d5
	move.l	$40(a5,d5.w),d4
	move.l	d6,d2
	move.l	d7,d3
	and.l	d4,d2
	and.l	d4,d3
	not.l	d4
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d2,d0
	move.l	d0,(a4)+
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d3,d0
	move.l	d0,(a4)+
.next:	subq.w	#1,($10a44).l			; ligne suivante (au-dessus)
	GREL
	sub.l	#160,a6
	cmp.l	($56c78).l,a6
	GREL
	bge	.L
	jmp	($5545a).l			; fin de la boucle d'origine
	GREL
.one:	andi.w	#15,d4				; un seul bloc
	asl.w	#2,d4
	move.l	(a5,d4.w),d4
	andi.w	#15,d5
	asl.w	#2,d5
	move.l	$40(a5,d5.w),d5
	and.l	d5,d4
	move.l	d6,d2
	move.l	d7,d3
	and.l	d4,d2
	and.l	d4,d3
	not.l	d4
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d2,d0
	move.l	d0,(a4)+
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d3,d0
	move.l	d0,(a4)+
	bra	.next

	section	turbo,code
t_lines53:
.L:	move.w	(a0)+,d4			; x gauche
	bmi	.c2
	move.w	(a3)+,d5			; x droit
	bmi	.c3
	cmp.w	d4,d5
	bgt.s	.sp
	beq	.next
	jmp	($5339e).l
	GREL
.c2:	jmp	($5330a).l
	GREL
.c3:	jmp	($53352).l
	GREL
.sp:	move.w	d4,d1				; tracé d'une ligne, de x = d4 à d5
	andi.w	#240,d1
	lsr.w	#1,d1
	lea	(a6,d1.w),a4
	move.w	d4,d3
	move.w	d5,d1
	lsr.w	#4,d3
	lsr.w	#4,d1
	sub.w	d3,d1
	beq	.one
	subq.b	#1,d1				; plusieurs blocs de 16 pixels
	andi.w	#15,d4
	beq.s	.mid
	asl.w	#2,d4
	move.l	(a5,d4.w),d4
	move.l	d6,d2
	move.l	d7,d3
	and.l	d4,d2
	and.l	d4,d3
	not.l	d4
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d2,d0
	move.l	d0,(a4)+
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d3,d0
	move.l	d0,(a4)+
	bra.s	.dbf
.mid:	move.l	d6,(a4)+
	move.l	d7,(a4)+
.dbf:	dbf	d1,.mid
	andi.w	#15,d5
	beq.s	.next
	asl.w	#2,d5
	move.l	$40(a5,d5.w),d4
	move.l	d6,d2
	move.l	d7,d3
	and.l	d4,d2
	and.l	d4,d3
	not.l	d4
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d2,d0
	move.l	d0,(a4)+
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d3,d0
	move.l	d0,(a4)+
.next:	subq.w	#1,($10a44).l			; ligne suivante (au-dessus)
	GREL
	sub.l	#160,a6
	cmp.l	($56c78).l,a6
	GREL
	bge	.L
	jmp	($5346e).l			; fin de la boucle d'origine
	GREL
.one:	andi.w	#15,d4				; un seul bloc
	asl.w	#2,d4
	move.l	(a5,d4.w),d4
	andi.w	#15,d5
	asl.w	#2,d5
	move.l	$40(a5,d5.w),d5
	and.l	d5,d4
	move.l	d6,d2
	move.l	d7,d3
	and.l	d4,d2
	and.l	d4,d3
	not.l	d4
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d2,d0
	move.l	d0,(a4)+
	move.l	(a4),d0
	and.l	d4,d0
	or.l	d3,d0
	move.l	d0,(a4)+
	bra	.next

; choix de la couleur ($53094) : l'original réécrit les opcodes bset/bclr du tracé de
; pixel $5313E (un par plan). Le cache d'instructions du 68030 ne voit pas ces écritures :
; il pourrait exécuter l'ancienne couleur. Après l'original, si la couleur a changé, les
; mots longs modifiés sont retirés du cache (CAAR + CEI) ; drapeaux de l'original rendus.
; Posé seulement quand le cache d'instructions est allumé.
	section	turbo,code
t_color:					; d0.b : bit p = plan p (1 : bset)
	move.l	d1,-(sp)			; (drapeaux d'entrée : écrasés par l'original)
	move.b	d0,d1
	and.b	#15,d1
	eor.b	d1,pix_col			; plans qui changent
	beq.s	.same
	move.b	pix_col,pix_chg
	move.b	d1,pix_col
	move.l	(sp)+,d1
	bsr.s	.c				; l'original
	move.w	ccr,-(sp)
	movem.l	d0-d2/a0-a1,-(sp)
	moveq	#0,d0
	move.b	pix_chg,d0
	cmp.b	#16,d0				; premier appel (couleur inconnue) : tous
	blo.s	.k
	moveq	#15,d0
.k:	move.l	cei_value,d2
	lea	.adr(pc),a1
	moveq	#4-1,d1
	tst.w	is_060
	bne.s	.p6
.p:	lsr.w	#1,d0
	bcc.s	.n
	move.l	(a1),a0				; les deux mots longs du plan
	movec	a0,caar
	movec	d2,cacr
	move.l	4(a1),a0
	movec	a0,caar
	movec	d2,cacr
.n:	addq.l	#8,a1
	dbf	d1,.p
	bra.s	.e
.p6:	lsr.w	#1,d0				; 68040/68060 : ligne écrite en mémoire (cache à
	bcc.s	.n6				; recopie) et retirée des deux caches
	move.l	(a1),a0
	CPUSHL_BC_A0
	move.l	4(a1),a0
	CPUSHL_BC_A0
.n6:	addq.l	#8,a1
	dbf	d1,.p6
.e:
	movem.l	(sp)+,d0-d2/a0-a1
	move.w	(sp)+,ccr
	rts
.same:	move.b	d1,pix_col			; (inchangée : remise)
	move.l	(sp)+,d1
.c:	lsr.b	#1,d0				; instructions déplacées par le « jmp »
	bcs.s	.s
	jmp	($5309a).l
	GREL
.s:	jmp	($530ae).l
	GREL
.adr:	dc.l	$53150,$53164			; plan 0 : mots longs des deux opcodes
	GREL
	section	grel,data
	dc.l	.adr
	section	turbo,code
	dc.l	$53154,$53168			; plan 1
	GREL
	section	grel,data
	dc.l	.adr+8
	section	turbo,code
	dc.l	$53158,$5316c			; plan 2
	GREL
	section	grel,data
	dc.l	.adr+16
	section	turbo,code
	dc.l	$5315c,$53170			; plan 3
	GREL
	section	grel,data
	dc.l	.adr+24
	section	turbo,code

; tracé de pixel ($5313E) sans code automodifiant, posé sur 68040/68060 seulement : la
; couleur est lue dans pix_col (notée par t_color) au lieu des opcodes bset/bclr réécrits.
; Sur 68060, malgré CPUSHL, l'ancienne couleur restait exécutée (bordures de la piste d'une
; seule couleur, qui clignotait d'une image à l'autre). Mêmes écritures, même d0, même Z.
	section	turbo,code
t_pixel:
	movem.l	d1,-(sp)
	move.b	d4,d0
	andi.w	#15,d0
	eori.w	#15,d0
	move.b	pix_col,d1
	cmpi.w	#8,d0
	bge.s	.hi
	lsr.b	#1,d1				; octets impairs : plans 0 à 3
	bcc.s	.l0
	bset	d0,1(a0)
	bra.s	.l1
.l0:	bclr	d0,1(a0)
.l1:	lsr.b	#1,d1
	bcc.s	.l2
	bset	d0,3(a0)
	bra.s	.l3
.l2:	bclr	d0,3(a0)
.l3:	lsr.b	#1,d1
	bcc.s	.l4
	bset	d0,5(a0)
	bra.s	.l5
.l4:	bclr	d0,5(a0)
.l5:	lsr.b	#1,d1
	bcc.s	.l6
	bset	d0,7(a0)
	movem.l	(sp)+,d1
	rts
.l6:	bclr	d0,7(a0)
	movem.l	(sp)+,d1
	rts
.hi:	andi.w	#7,d0				; octets pairs
	lsr.b	#1,d1
	bcc.s	.h0
	bset	d0,(a0)
	bra.s	.h1
.h0:	bclr	d0,(a0)
.h1:	lsr.b	#1,d1
	bcc.s	.h2
	bset	d0,2(a0)
	bra.s	.h3
.h2:	bclr	d0,2(a0)
.h3:	lsr.b	#1,d1
	bcc.s	.h4
	bset	d0,4(a0)
	bra.s	.h5
.h4:	bclr	d0,4(a0)
.h5:	lsr.b	#1,d1
	bcc.s	.h6
	bset	d0,6(a0)
	movem.l	(sp)+,d1
	rts
.h6:	bclr	d0,6(a0)
	movem.l	(sp)+,d1
	rts

; routines remplacées : décalage depuis $10100, premier mot attendu, remplaçante
	section	turbo,code
	even
turbo_tab:
	dc.l	$5353c-$10100
	dc.w	$227c				; movea.l #$702B8,a1
	ifd	CHKEDGE
	dc.l	t_edge_chk
	elseif
	dc.l	t_edge
	endc
	dc.l	$53aca-$10100
	dc.w	$3405				; move.w d5,d2
	dc.l	t_trace
	dc.l	$552c0-$10100
	dc.w	$3039				; move.w $10A44,d0
	dc.l	t_lines55
	dc.l	$53304-$10100
	dc.w	$3818				; move.w (a0)+,d4
	dc.l	t_lines53
	dc.l	$56762-$10100
	dc.w	$2f05				; move.l d5,-(sp)
	ifd	CHKSPR
	dc.l	t_sprite_chk
	elseif
	dc.l	t_sprite
	endc
	dc.l	-1
; posées quand le cache d'instructions est allumé (même avec l'option T)
cache_tab:
	dc.l	$53094-$10100
	dc.w	$e208				; lsr.b #1,d0
	dc.l	t_color
	dc.l	-1
; posée sur 68040/68060 (avec cache_tab)
pix060_tab:
	dc.l	$5313e-$10100
	dc.w	$1004				; move.b d4,d0
	dc.l	t_pixel
	dc.l	-1

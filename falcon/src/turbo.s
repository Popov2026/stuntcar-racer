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
t_edge_slow:
	move.l	#$702b8,a1			; instruction déplacée par le « jmp »
	GREL
	jmp	($53542).l			; puis le code d'origine
	GREL
t_edge:
	move.l	($54d00).l,a0
	GREL
	cmp.l	#$72c50,a0			; table des bords pleine (original)
	GREL
	bge.s	t_edge_slow
	move.l	#$6ec5c,a4
	GREL
	move.l	#$6ed9c,a5
	GREL
	move.w	(a4,d1.w),d4
	move.w	(a4,d2.w),d6
	move.w	(a5,d1.w),d5
	move.w	(a5,d2.w),d7
	cmp.w	#256,d4				; hors de la fenêtre : découpage (original)
	bhs.s	t_edge_slow
	cmp.w	#256,d6
	bhs.s	t_edge_slow
	cmp.w	#128,d5
	bhs.s	t_edge_slow
	cmp.w	#128,d7
	bhs.s	t_edge_slow
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
	bra	t_trace

; tracé proprement dit ($53ACA, atteint aussi après découpage d'un bord) : d4, d5 =
; x0, y0 et d6, d7 = x1, y1 (y0 >= y1), a2 = en-tête, a0 = x par ligne ; en-tête y
; écrit si ($5353A) >= 0 ; après les x, ($53536)+1 fois le mot ($53538) si
; ($53536) >= 0. a1 et le mot fort de d0 restent ceux de l'entrée, comme l'original.
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
	tst.w	d1
	bpl	.left
	neg.w	d1				; dx
	cmp.w	d2,d1
	blt	.yr
	bsr	.xprep				; x croissant, plus large que haut
	tst.w	d2
	beq	.xend
	add.w	d0,d4				; x0 + k1
	move.w	d4,(a0)+
	bsr	.xqr
	cmp.l	a1,a0
	beq	.xend
.xr:	sub.w	d1,d5				; s -= r
	bcs.s	.xr1
	add.w	d0,d4				; x += q
	move.w	d4,(a0)+
	cmp.l	a1,a0
	bne.s	.xr
	bra.s	.xend
.xr1:	add.w	d2,d5				; s += dy, x += q+1
	add.w	d0,d4
	addq.w	#1,d4
	move.w	d4,(a0)+
	cmp.l	a1,a0
	bne.s	.xr
	bra.s	.xend

.orig:	move.w	d5,d2				; instructions déplacées par le « jmp »
	sub.w	d7,d2
	move.w	d4,d1
	jmp	($53ad0).l
	GREL

.yr:	move.w	d2,d3				; x croissant, plus haut que large
	lsr.w	#1,d3
	not.w	d3
	move.w	d2,d5
	subq.w	#1,d5
.yr1:	move.w	d4,(a0)+
	add.w	d1,d3
	bcc.s	.yr2
	sub.w	d2,d3
	addq.w	#1,d4
.yr2:	dbf	d5,.yr1
	bra.s	.end
.xend:	and.b	#$ef,ccr			; X : comme à la sortie du Bresenham d'origine
.end:	move.l	tr_d0,d0
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

.left:	cmp.w	d2,d1				; x décroissant
	blt.s	.yl
	bsr.s	.xprep
	tst.w	d2
	beq.s	.xend
	sub.w	d0,d4				; x0 - k1
	move.w	d4,(a0)+
	bsr.s	.xqr
	cmp.l	a1,a0
	beq.s	.xend
.xl:	sub.w	d1,d5
	bcs.s	.xl1
	sub.w	d0,d4
	move.w	d4,(a0)+
	cmp.l	a1,a0
	bne.s	.xl
	bra.s	.xend
.xl1:	add.w	d2,d5
	sub.w	d0,d4
	subq.w	#1,d4
	move.w	d4,(a0)+
	cmp.l	a1,a0
	bne.s	.xl
	bra.s	.xend

.yl:	move.w	d2,d3
	lsr.w	#1,d3
	not.w	d3
	move.w	d2,d5
	subq.w	#1,d5
.yl1:	move.w	d4,(a0)+
	add.w	d1,d3
	bcc.s	.yl2
	sub.w	d2,d3
	subq.w	#1,d4
.yl2:	dbf	d5,.yl1
	bra.s	.end

; plus large que haut : d1 = dx >= d2 = dy. Erreur d3 = ~(dx/2) comme l'original.
; Le j-ième x est x0 +- k_j, k_j = ceil(((j-1)*dx + f)/dy), f = dx/2 + 1 ;
; s = k_j*dy - (j-1)*dx - f (0 <= s < dy). Sortie : d0.w = k1, d5.w = s,
; a1 = fin des dy x. Seuls d0 et a1 servent en entier (rétablis à la fin) : les mots
; forts des autres registres restent ceux de l'original.
.xprep:	move.w	d1,d3
	lsr.w	#1,d3
	not.w	d3
	tst.w	d2
	beq.s	.xp1
	lea	(a0,d2.w*2),a1
	moveq	#0,d0
	move.w	d1,d0
	lsr.w	#1,d0
	addq.w	#1,d0				; f
	divu.w	d2,d0				; reste : quotient
	swap	d0
	move.w	d0,d5
	beq.s	.xp0
	sub.w	d2,d5
	neg.w	d5				; s = dy - reste
	add.l	#$10000,d0			; k1 = quotient + 1
.xp0:	swap	d0
.xp1:	rts
; dx = q*dy + r : d0.w = q, d1.w = r
.xqr:	moveq	#0,d0
	move.w	d1,d0
	divu.w	d2,d0
	swap	d0
	move.w	d0,d1
	swap	d0
	rts

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
	dc.l	$56762-$10100
	dc.w	$2f05				; move.l d5,-(sp)
	ifd	CHKSPR
	dc.l	t_sprite_chk
	elseif
	dc.l	t_sprite
	endc
	dc.l	-1

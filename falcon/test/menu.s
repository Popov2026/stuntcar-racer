; menu.s - doublure de AUTO/DEBUT.PRG (menu de la compilation) pour les tests :
; lance GAME.PUT comme le fait le menu d'origine, puis rend la main.
; vasmm68k_mot -Ftos -devpac -nosym -o DEBUT.PRG menu.s
	text
	move.l	4(sp),a5
	lea	stack_top,sp
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
	pea	empty
	pea	empty
	pea	game
	clr.w	-(sp)
	move.w	#$4b,-(sp)			; Pexec
	trap	#1
	lea	16(sp),sp
	clr.w	-(sp)
	trap	#1
	data
game:	dc.b	"\GAME.PUT",0
empty:	dc.b	0,0
	even
	bss
	ds.l	256
stack_top:
	ds.l	1

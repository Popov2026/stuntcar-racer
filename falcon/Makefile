# Version Falcon030 : lanceur, variante AUTO et doublure de test.
# vasm : http://sun.hasenbraten.de/vasm/  (make CPU=m68k SYNTAX=mot)
VASM   ?= vasmm68k_mot
VFLAGS  = -Ftos -m68030 -devpac -nosym -quiet

all: bin/SCRF030.PRG bin/F030AUTO.PRG test/build/GAME.PUT test/build/DEBUT.PRG

bin/SCRF030.PRG: src/scrf030.s src/snaptab.s
	@mkdir -p bin
	$(VASM) $(VFLAGS) -o $@ $<

bin/F030AUTO.PRG: src/scrf030.s src/snaptab.s
	@mkdir -p bin
	$(VASM) $(VFLAGS) -DAUTO=1 -o $@ $<

# doublure de GAME.PUT pour les tests sous Hatari (aucune donnée du jeu)
test/build/GAME.PUT: test/standin.s
	@mkdir -p test/build
	$(VASM) $(VFLAGS) -o $@ $<

test/build/DEBUT.PRG: test/menu.s
	@mkdir -p test/build
	$(VASM) $(VFLAGS) -o $@ $<

clean:
	rm -rf test/build

.PHONY: all clean

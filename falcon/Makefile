# Version Falcon030 : lanceur, variante AUTO et doublure de test.
# vasm : http://sun.hasenbraten.de/vasm/  (make CPU=m68k SYNTAX=mot)
VASM   ?= vasmm68k_mot
VFLAGS  = -Ftos -m68030 -devpac -nosym -quiet

all: bin/SCRF030.PRG bin/SCRCT60.PRG bin/F030AUTO.PRG test/build/GAME.PUT test/build/DEBUT.PRG

bin/SCRF030.PRG: src/scrf030.s src/snaptab.s src/turbo.s
	@mkdir -p bin
	$(VASM) $(VFLAGS) -o $@ $<

# Falcon à 68060 (CT60, CT63) : modes HD F2/F3 (moteur hd/hd.bin)
bin/SCRCT60.PRG: src/scrf030.s src/snaptab.s src/turbo.s hd/hd.bin hd/hdrel.s
	@mkdir -p bin
	$(VASM) $(VFLAGS) -DCT60=1 -o $@ $<

bin/F030AUTO.PRG: src/scrf030.s src/snaptab.s src/turbo.s
	@mkdir -p bin
	$(VASM) $(VFLAGS) -DAUTO=1 -o $@ $<

# moteur HD (F2/F3) : hd/hd.bin et hd/hdrel.s sont fournis ; pour les refaire (gcc m68k-elf) :
#   make -C falcon/hd CROSS=m68k-elf-

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

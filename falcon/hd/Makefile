# moteur HD (F2/F3) : C pour 68060, lié en 0, relogé au lancement par scrf030.s
# make -C falcon/hd CROSS=m68k-elf-   (gcc m68k-elf, testé : 16.1)
CROSS ?= m68k-elf-
CFLAGS = -m68060 -O2 -ffreestanding -fno-builtin -nostdlib -fno-common -ffast-math -fno-pic \
         -Wall -Wno-misleading-indentation

all: hd.bin hdtest

hd.bin hdrel.s: hd.c hd.h hd.ld mkblob.py
	$(CROSS)gcc $(CFLAGS) -c hd.c -o hd.o
	$(CROSS)ld -q -T hd.ld --no-warn-rwx-segments -o hd.elf hd.o
	$(CROSS)objcopy -O binary hd.elf hd.bin
	python3 mkblob.py hd.elf $(CROSS)objdump hd.bin hdrel.s
	rm -f hd.o hd.elf

# essai sur PC : copie de la mémoire du Falcon (Hatari « savebin ») -> image
hdtest: hdtest.c hd.c hd.h
	cc -O2 -w -o $@ hdtest.c hd.c -lm

clean:
	rm -f hdtest hd.o hd.elf

.PHONY: all clean

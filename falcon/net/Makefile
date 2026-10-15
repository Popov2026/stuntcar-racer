# module réseau (multijoueur en ligne de SCRCT60) : C sans bibliothèque ni FPU, lié en 0, relogé
# au lancement par scrf030.s. net.bin et netrel.s sont fournis ; pour les refaire :
#   make -C falcon/net CROSS=m68k-elf-   (gcc m68k-elf, testé : 16.1)
CROSS ?= m68k-elf-
CFLAGS = -m68020-60 -msoft-float -O2 -ffreestanding -fno-builtin -nostdlib -fno-common -fno-pic \
         -Wall -Wno-misleading-indentation

all: net.bin

net.bin netrel.s: net.c net.h net.ld mkblob.py
	$(CROSS)gcc $(CFLAGS) -c net.c -o net.o
	$(CROSS)ld -q -T net.ld --no-warn-rwx-segments -o net.elf net.o
	@if $(CROSS)objdump -d net.elf | grep -P '^\s*[0-9a-f]+:\t[0-9a-f ]+\t+f[a-z]'; then \
		echo "instructions FPU dans net.c"; exit 1; fi
	$(CROSS)objcopy -O binary net.elf net.bin
	python3 mkblob.py net.elf $(CROSS)objdump net.bin netrel.s
	rm -f net.o net.elf

clean:
	rm -f net.o net.elf

.PHONY: all clean

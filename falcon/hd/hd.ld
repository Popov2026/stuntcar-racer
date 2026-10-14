OUTPUT_FORMAT("elf32-m68k")
ENTRY(hd_init)
SECTIONS {
  . = 0;
  .blob : { *(.entry) *(.text*) *(.rodata*) *(.data*) *(.sdata*) *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); }
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}

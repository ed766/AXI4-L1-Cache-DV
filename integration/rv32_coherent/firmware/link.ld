OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text : { KEEP(*(.text.start)) *(.text .text.*) }
  . = ALIGN(4);
  .rodata : { *(.rodata .rodata.*) }
  . = 0x00002000;
  .data : { *(.data .data.*) }
  . = ALIGN(4);
  .bss : { *(.bss .bss.*) *(COMMON) }
}

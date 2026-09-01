    .section .text.start
    .globl _start
_start:
    li sp, 0x00003f00
    call main
    li t0, (0x400001f0 + (HART_ID * 8))
    sw a0, 0(t0)
    li t1, 1
    sw t1, 4(t0)
1:
    ebreak
    j 1b

    .section .text.trap
    .globl coherent_trap_entry
coherent_trap_entry:
    csrr t0, mcause
    li t1, 0x40000040
    sw t0, 0(t1)
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2
    mret

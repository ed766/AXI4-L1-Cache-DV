#include <stdint.h>

#ifndef HART_ID
#define HART_ID 0
#endif
#ifndef FAULT_MODE
#define FAULT_MODE 0
#endif

#define MMIO32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define SHARED_X MMIO32(0x80000000u)
#define TRAP_CAUSE MMIO32(0x40000040u)
#define FAULT_ADDR MMIO32(0x400000e0u)
#define FAULT_STATUS MMIO32(0x400000e4u)

extern void coherent_trap_entry(void);

int main(void) {
  if (HART_ID != 0) return 0;
  __asm__ volatile ("csrw mtvec,%0" :: "r"(coherent_trap_entry));
#if FAULT_MODE == 0
  volatile uint32_t value = SHARED_X;
  (void)value;
  return TRAP_CAUSE == 5u ? 0 : 10;
#else
  SHARED_X = 0xcafef00du;
  while ((FAULT_STATUS & 1u) == 0u) { }
  if (FAULT_ADDR != 0x80000000u) return 11;
  FAULT_STATUS = 1u;
  __asm__ volatile ("fence rw,rw" ::: "memory");
  return SHARED_X == 0xcafef00du ? 0 : 12;
#endif
}

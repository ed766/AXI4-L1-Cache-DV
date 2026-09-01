#include <stdint.h>

#ifndef HART_ID
#define HART_ID 0
#endif
#ifndef LITMUS_ID
#define LITMUS_ID 0
#endif

#define MMIO32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define X MMIO32(0x80000000u)
#define Y MMIO32(0x80000004u)
#define OBS0 MMIO32(0x40000020u)
#define OBS1 MMIO32(0x40000024u)

static inline void full_fence(void) {
  __asm__ volatile ("fence rw,rw" ::: "memory");
}

int main(void) {
  uint32_t value = 0;
  uint32_t first = 0;

#if LITMUS_ID == 0
  if (HART_ID == 0) { X = 1; value = Y; } else { Y = 1; value = X; }
#elif LITMUS_ID == 1
  if (HART_ID == 0) { X = 1; full_fence(); value = Y; }
  else { Y = 1; full_fence(); value = X; }
#elif LITMUS_ID == 2
  if (HART_ID == 0) { X = 1; Y = 1; }
  else { first = Y; value = X; }
#elif LITMUS_ID == 3
  if (HART_ID == 0) { X = 1; full_fence(); Y = 1; }
  else { first = Y; full_fence(); value = X; }
#elif LITMUS_ID == 4
  if (HART_ID == 0) { value = X; Y = 1; } else { value = Y; X = 1; }
#elif LITMUS_ID == 5
  if (HART_ID == 0) { value = X; full_fence(); Y = 1; }
  else { value = Y; full_fence(); X = 1; }
#elif LITMUS_ID == 6
  if (HART_ID == 0) { value = X; Y = 1; } else { X = 1; value = Y; }
#elif LITMUS_ID == 7
  if (HART_ID == 0) { value = X; full_fence(); Y = 1; }
  else { X = 1; full_fence(); value = Y; }
#elif LITMUS_ID == 8
  if (HART_ID == 0) { X = 1; value = X; } else { Y = 1; value = Y; }
#elif LITMUS_ID == 9
  if (HART_ID == 0) { X = 1; full_fence(); value = X; }
  else { Y = 1; full_fence(); value = Y; }
#elif LITMUS_ID == 10
  if (HART_ID == 0) { X = 1; full_fence(); X = 2; }
  else { first = X; value = X; }
#elif LITMUS_ID == 11
  if (HART_ID == 0) { X = 1; full_fence(); X = 2; }
  else { first = X; full_fence(); value = X; }
#elif LITMUS_ID == 12
  if (HART_ID == 0) { X = 1; X = 3; } else { X = 2; value = X; }
#elif LITMUS_ID == 13
  if (HART_ID == 0) { X = 1; full_fence(); X = 3; }
  else { X = 2; full_fence(); value = X; }
#elif LITMUS_ID == 14
  if (HART_ID == 0) { X = 1; value = Y; } else { value = X; Y = 1; }
#else
  if (HART_ID == 0) { X = 1; full_fence(); value = Y; }
  else { value = X; full_fence(); Y = 1; }
#endif

  (void)first;
  if (HART_ID == 0) OBS0 = value; else OBS1 = value;
  return 0;
}

#include <stdint.h>

#ifndef HART_ID
#define HART_ID 0
#endif
#ifndef WORKLOAD_ID
#define WORKLOAD_ID 0
#endif

#define MMIO32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define SHARED_X MMIO32(0x80000000u)
#define SHARED_Y MMIO32(0x80000004u)
#define SHARED_Z MMIO32(0x80000008u)
#define SHARED_B MMIO32(0x80000010u)
#define SYNC0 MMIO32(0x40000000u)
#define SYNC1 MMIO32(0x40000004u)
#define OBS0  MMIO32(0x40000020u)
#define OBS1  MMIO32(0x40000024u)

static inline void shared_fence(void) {
  __asm__ volatile ("fence rw,rw" ::: "memory");
}

static int producer_consumer(void) {
#if HART_ID == 0
  SHARED_X = 0x13579bdfu;
  shared_fence();
  SYNC0 = 1;
  while (SYNC1 == 0) { }
  return 0;
#else
  uint32_t value;
  while (SYNC0 == 0) { }
  shared_fence();
  value = SHARED_X;
  OBS1 = value;
  SYNC1 = 1;
  return value == 0x13579bdfu ? 0 : 1;
#endif
}

static int store_buffering(void) {
  uint32_t observed;
#if HART_ID == 0
  SHARED_X = 1;
  observed = SHARED_Y;
  OBS0 = observed;
#else
  SHARED_Y = 1;
  observed = SHARED_X;
  OBS1 = observed;
#endif
  return 0;
}

static int message_passing(void) {
#if HART_ID == 0
  SHARED_X = 0xc001c0deu;
  shared_fence();
  SHARED_Y = 1;
  return 0;
#else
  uint32_t flag;
  do { flag = SHARED_Y; } while (flag == 0);
  shared_fence();
  OBS1 = SHARED_X;
  return OBS1 == 0xc001c0deu ? 0 : 2;
#endif
}

static int ping_pong(void) {
  for (uint32_t round = 1; round <= 4; round++) {
#if HART_ID == 0
    SHARED_X = round;
    shared_fence();
    while (SHARED_Y != round) { }
#else
    while (SHARED_X != round) { }
    shared_fence();
    SHARED_Y = round;
#endif
  }
  return 0;
}

static int false_sharing(void) {
  for (uint32_t n = 0; n < 4; n++) {
#if HART_ID == 0
    SHARED_X = 0x100u + n;
#else
    SHARED_Y = 0x200u + n;
#endif
    shared_fence();
  }
  return 0;
}

static int intervention(void) {
#if HART_ID == 0
  SHARED_Z = 0x55aa55aau;
  shared_fence();
  SYNC0 = 1;
  while (SYNC1 == 0) { }
  return 0;
#else
  while (SYNC0 == 0) { }
  OBS1 = SHARED_Z;
  // Re-read the installed requester line. The first intervention response can
  // be correct even if a defective refill path cached stale backing data.
  uint32_t installed = SHARED_Z;
  SYNC1 = 1;
  return OBS1 == 0x55aa55aau && installed == 0x55aa55aau ? 0 : 3;
#endif
}

static int alternating_ownership(void) {
  for (uint32_t n = 1; n <= 3; n++) {
#if HART_ID == 0
    SHARED_X = n;
    shared_fence();
    while (SHARED_X != (0x100u + n)) { }
#else
    while (SHARED_X != n) { }
    SHARED_X = 0x100u + n;
    shared_fence();
#endif
  }
  return 0;
}

static int ordered_two_line(void) {
#if HART_ID == 0
  SHARED_X = 0x11112222u;
  SHARED_B = 0x33334444u;
  shared_fence();
  SYNC0 = 1;
  return 0;
#else
  while (SYNC0 == 0) { }
  shared_fence();
  return (SHARED_X == 0x11112222u && SHARED_B == 0x33334444u) ? 0 : 4;
#endif
}

static int same_address_forwarding(void) {
#if HART_ID == 0
  SHARED_X = 0x5aa55aa5u;
  return SHARED_X == 0x5aa55aa5u ? 0 : 5;
#else
  return 0;
#endif
}

static int parallel_banks(void) {
  for (uint32_t n = 1; n <= 8; n++) {
#if HART_ID == 0
    SHARED_X = 0x1000u + n;
#else
    SHARED_B = 0x2000u + n;
#endif
  }
  shared_fence();
  return 0;
}

int main(void) {
#if WORKLOAD_ID == 0
  return producer_consumer();
#elif WORKLOAD_ID == 1
  return store_buffering();
#elif WORKLOAD_ID == 2
  return message_passing();
#elif WORKLOAD_ID == 3
  return ping_pong();
#elif WORKLOAD_ID == 4
  return false_sharing();
#elif WORKLOAD_ID == 5
  return intervention();
#elif WORKLOAD_ID == 6
  return alternating_ownership();
#elif WORKLOAD_ID == 7
  return ordered_two_line();
#elif WORKLOAD_ID == 8
  return same_address_forwarding();
#else
  return parallel_banks();
#endif
}

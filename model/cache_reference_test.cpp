#include "cache_reference.hpp"

#include <cassert>
#include <iostream>

int main() {
  CacheReference model;
  auto cold = model.access(0x1000, false, 0, 0, 2);
  assert(!cold.error && !cold.hit);
  auto hit = model.access(0x1000, false, 0, 0, 2);
  assert(hit.hit && hit.data == cold.data);
  auto store = model.access(0x1000, true, 0xdeadbeef, 0xf, 2);
  assert(store.hit && !store.error);
  model.access(0x1800, false, 0, 0, 2);
  auto eviction = model.access(0x2000, false, 0, 0, 2);
  assert(eviction.eviction);
  assert(model.get_memory(0x1000) == 0xdeadbeef);
  auto misaligned = model.access(0x1001, false, 0, 0, 2);
  assert(misaligned.error);

  CacheReference direct_mapped(128, 1);
  auto dm_cold = direct_mapped.access(0x1000, false, 0, 0, 2);
  auto dm_conflict = direct_mapped.access(0x2000, false, 0, 0, 2);
  auto dm_revisit = direct_mapped.access(0x1000, false, 0, 0, 2);
  assert(!dm_cold.hit && !dm_conflict.hit && !dm_revisit.hit);
  std::cout << "MODEL_RESULT|status=PASS|cases=9|geometries=2\n";
}

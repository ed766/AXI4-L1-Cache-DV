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

  constexpr uint32_t ecc_word = 0xa55ac33cu;
  const uint8_t ecc = CacheReference::secded_encode(ecc_word);
  for (unsigned bit = 0; bit < 32; ++bit) {
    const auto corrected = CacheReference::secded_decode(ecc_word ^ (1u << bit), ecc);
    assert(corrected.corrected && !corrected.uncorrectable && corrected.data == ecc_word);
  }
  for (unsigned bit = 0; bit < 7; ++bit) {
    const auto corrected = CacheReference::secded_decode(ecc_word, ecc ^ (1u << bit));
    assert(corrected.corrected && !corrected.uncorrectable && corrected.data == ecc_word);
  }
  const auto double_fault = CacheReference::secded_decode(ecc_word ^ 3u, ecc);
  assert(!double_fault.corrected && double_fault.uncorrectable);
  std::cout << "MODEL_RESULT|status=PASS|cases=49|geometries=2|secded=40\n";
}

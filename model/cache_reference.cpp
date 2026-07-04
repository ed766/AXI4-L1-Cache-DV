#include "cache_reference.hpp"

#include <stdexcept>

CacheReference::CacheReference() { reset(); }

void CacheReference::reset() {
  for (auto& set : lines_)
    for (auto& line : set) line = Line{};
  lru_.fill(0);
}

void CacheReference::set_memory(uint32_t address, uint32_t value) {
  memory_[address >> 2] = value;
}

uint32_t CacheReference::memory_word(uint32_t word_address) const {
  auto found = memory_.find(word_address);
  return found == memory_.end() ? (0x10000000u ^ word_address) : found->second;
}

uint32_t CacheReference::get_memory(uint32_t address) const {
  return memory_word(address >> 2);
}

void CacheReference::writeback(unsigned set, unsigned way) {
  Line& line = lines_.at(set).at(way);
  const uint32_t line_base = ((line.tag << 6) | set) << 5;
  for (unsigned word = 0; word < kWordsPerLine; ++word)
    memory_[line_base / 4 + word] = line.words[word];
  line.dirty = false;
}

CacheReference::Response CacheReference::access(uint32_t address, bool write,
                                                uint32_t data, uint8_t strobes,
                                                uint8_t size) {
  const bool aligned = size <= 2 &&
      (size == 0 || (size == 1 && !(address & 1)) ||
       (size == 2 && !(address & 3)));
  if (!aligned) return {0, true, false, false};

  const unsigned set = (address >> 5) & 0x3f;
  const unsigned word = (address >> 2) & 0x7;
  const uint32_t tag = address >> 11;
  int way = -1;
  for (unsigned candidate = 0; candidate < kWays; ++candidate)
    if (lines_[set][candidate].valid && lines_[set][candidate].tag == tag)
      way = static_cast<int>(candidate);

  const bool hit = way >= 0;
  bool eviction = false;
  if (!hit) {
    if (!lines_[set][0].valid) way = 0;
    else if (!lines_[set][1].valid) way = 1;
    else way = lru_[set];
    Line& victim = lines_[set][way];
    if (victim.valid && victim.dirty) {
      writeback(set, way);
      eviction = true;
    }
    const uint32_t line_base = address & ~0x1fu;
    for (unsigned index = 0; index < kWordsPerLine; ++index)
      victim.words[index] = memory_word(line_base / 4 + index);
    victim.valid = true;
    victim.dirty = false;
    victim.tag = tag;
  }

  Line& line = lines_[set][way];
  uint32_t result = line.words[word];
  if (write) {
    for (unsigned byte = 0; byte < 4; ++byte) {
      if (strobes & (1u << byte)) {
        const uint32_t mask = 0xffu << (byte * 8);
        result = (result & ~mask) | (data & mask);
      }
    }
    line.words[word] = result;
    line.dirty = true;
    result = 0;
  }
  lru_[set] = static_cast<uint8_t>(1 - way);
  return {result, false, hit, eviction};
}

bool CacheReference::flush(bool invalidate) {
  for (unsigned set = 0; set < kSets; ++set) {
    for (unsigned way = 0; way < kWays; ++way) {
      if (lines_[set][way].valid && lines_[set][way].dirty) writeback(set, way);
      if (invalidate) lines_[set][way].valid = false;
    }
  }
  return true;
}

extern "C" {
void* cache_ref_create() { return new CacheReference(); }
void cache_ref_destroy(void* handle) { delete static_cast<CacheReference*>(handle); }
void cache_ref_reset(void* handle) { static_cast<CacheReference*>(handle)->reset(); }
void cache_ref_set_memory(void* handle, uint32_t address, uint32_t value) {
  static_cast<CacheReference*>(handle)->set_memory(address, value);
}
uint64_t cache_ref_access(void* handle, uint32_t address, uint32_t write,
                          uint32_t data, uint32_t strobes, uint32_t size) {
  const auto result = static_cast<CacheReference*>(handle)->access(
      address, write != 0, data, static_cast<uint8_t>(strobes), static_cast<uint8_t>(size));
  return static_cast<uint64_t>(result.data) |
         (static_cast<uint64_t>(result.error) << 32) |
         (static_cast<uint64_t>(result.hit) << 33) |
         (static_cast<uint64_t>(result.eviction) << 34);
}
}


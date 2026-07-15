#include "cache_reference.hpp"

#include <algorithm>
#include <stdexcept>

uint8_t CacheReference::secded_encode(uint32_t data) {
  uint8_t hamming = 0;
  for (unsigned parity = 0; parity < 6; ++parity) {
    unsigned data_index = 0;
    for (unsigned position = 1; position <= 38; ++position) {
      if ((position & (position - 1)) != 0) {
        if (position & (1u << parity))
          hamming ^= static_cast<uint8_t>(((data >> data_index) & 1u) << parity);
        ++data_index;
      }
    }
  }
  const bool overall = (__builtin_parity(data) ^ __builtin_parity(hamming)) != 0;
  return static_cast<uint8_t>(hamming | (static_cast<uint8_t>(overall) << 6));
}

CacheReference::EccResult CacheReference::secded_decode(uint32_t data, uint8_t code) {
  uint8_t syndrome = 0;
  for (unsigned parity = 0; parity < 6; ++parity) {
    bool parity_value = ((code >> parity) & 1u) != 0;
    unsigned data_index = 0;
    for (unsigned position = 1; position <= 38; ++position) {
      if ((position & (position - 1)) != 0) {
        if (position & (1u << parity)) parity_value ^= ((data >> data_index) & 1u) != 0;
        ++data_index;
      }
    }
    if (parity_value) syndrome |= static_cast<uint8_t>(1u << parity);
  }
  const bool overall_bad = (__builtin_parity(data) ^ __builtin_parity(code & 0x3f) ^
                            ((code >> 6) & 1u)) != 0;
  EccResult result{data, false, false};
  if (syndrome != 0 && overall_bad) {
    unsigned data_index = 0;
    for (unsigned position = 1; position <= 38; ++position) {
      if ((position & (position - 1)) != 0) {
        if (position == syndrome) result.data ^= 1u << data_index;
        ++data_index;
      }
    }
    result.corrected = true;
  } else if (syndrome == 0 && overall_bad) {
    result.corrected = true;
  } else if (syndrome != 0) {
    result.uncorrectable = true;
  }
  return result;
}

CacheReference::CacheReference(unsigned sets, unsigned ways)
    : sets_(sets), ways_(ways), index_bits_(0),
      lines_(sets, std::vector<Line>(ways)), lru_(sets, 0) {
  if (!((sets == 64 && ways == 2) || (sets == 128 && ways == 1)))
    throw std::invalid_argument("supported cache geometries are 64x2 and 128x1");
  while ((1u << index_bits_) < sets_) ++index_bits_;
  reset();
}

void CacheReference::reset() {
  for (auto& set : lines_)
    for (auto& line : set) line = Line{};
  std::fill(lru_.begin(), lru_.end(), 0);
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
  const uint32_t line_base = ((line.tag << index_bits_) | set) << 5;
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
  if (!aligned) {
    Response result;
    result.error = true;
    return result;
  }

  const unsigned set = (address >> 5) & (sets_ - 1);
  const unsigned word = (address >> 2) & 0x7;
  const uint32_t tag = address >> (5 + index_bits_);
  int way = -1;
  for (unsigned candidate = 0; candidate < ways_; ++candidate)
    if (lines_[set][candidate].valid && lines_[set][candidate].tag == tag)
      way = static_cast<int>(candidate);

  const bool hit = way >= 0;
  bool eviction = false;
  Response response;
  response.hit = hit;
  response.prior_lru = lru_[set];
  response.refill_base = address & ~0x1fu;
  if (!hit) {
    way = 0;
    for (unsigned candidate = 0; candidate < ways_; ++candidate) {
      if (!lines_[set][candidate].valid) {
        way = static_cast<int>(candidate);
        break;
      }
      if (candidate + 1 == ways_) way = ways_ == 1 ? 0 : lru_[set];
    }
    Line& victim = lines_[set][way];
    response.victim_valid = victim.valid;
    response.victim_dirty = victim.dirty;
    response.victim_base = ((victim.tag << index_bits_) | set) << 5;
    response.victim_words = victim.words;
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
  response.way = static_cast<unsigned>(way);
  response.eviction = eviction;
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
  if (ways_ == 2) lru_[set] = static_cast<uint8_t>(1 - way);
  response.data = result;
  return response;
}

bool CacheReference::flush(bool invalidate) {
  return maintenance(invalidate ? 2 : 0);
}

bool CacheReference::maintenance(uint8_t command) {
  for (unsigned set = 0; set < sets_; ++set) {
    for (unsigned way = 0; way < ways_; ++way) {
      if (command != 1 && lines_[set][way].valid && lines_[set][way].dirty)
        writeback(set, way);
      if (command != 0) lines_[set][way].valid = false;
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

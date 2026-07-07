#pragma once

#include <array>
#include <cstdint>
#include <unordered_map>
#include <vector>

class CacheReference {
 public:
  struct Response {
    uint32_t data = 0;
    bool error = false;
    bool hit = false;
    bool eviction = false;
    unsigned way = 0;
    bool victim_valid = false;
    bool victim_dirty = false;
    unsigned prior_lru = 0;
    uint32_t refill_base = 0;
    uint32_t victim_base = 0;
    std::array<uint32_t, 8> victim_words{};
  };

  explicit CacheReference(unsigned sets = 64, unsigned ways = 2);
  void reset();
  void set_memory(uint32_t address, uint32_t value);
  uint32_t get_memory(uint32_t address) const;
  Response access(uint32_t address, bool write, uint32_t data,
                  uint8_t strobes, uint8_t size);
  bool flush(bool invalidate);
  bool maintenance(uint8_t command);

 private:
  static constexpr unsigned kWordsPerLine = 8;

  struct Line {
    bool valid = false;
    bool dirty = false;
    uint32_t tag = 0;
    std::array<uint32_t, kWordsPerLine> words{};
  };

  unsigned sets_;
  unsigned ways_;
  unsigned index_bits_;
  std::vector<std::vector<Line>> lines_;
  std::vector<uint8_t> lru_;
  std::unordered_map<uint32_t, uint32_t> memory_;

  uint32_t memory_word(uint32_t word_address) const;
  void writeback(unsigned set, unsigned way);
};

extern "C" {
void* cache_ref_create();
void cache_ref_destroy(void* handle);
void cache_ref_reset(void* handle);
void cache_ref_set_memory(void* handle, uint32_t address, uint32_t value);
uint64_t cache_ref_access(void* handle, uint32_t address, uint32_t write,
                          uint32_t data, uint32_t strobes, uint32_t size);
}

#include "cache_reference.hpp"

#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
struct Event {
  uint64_t cycle = 0;
  unsigned epoch = 0;
  std::string name;
  int id = -1;
  uint32_t addr = 0;
  bool write = false;
  uint64_t data = 0;
  unsigned wstrb = 0;
  unsigned size = 0;
  bool error = false;
  bool hit = false;
  unsigned way = 0;
  bool valid = false;
  bool dirty = false;
  unsigned lru = 0;
  unsigned beat = 0;
  unsigned resp = 0;
  unsigned maint = 0;
  unsigned state = 0;
};

std::vector<std::string> split(const std::string& line) {
  std::vector<std::string> result;
  std::stringstream stream(line);
  std::string item;
  while (std::getline(stream, item, ',')) result.push_back(item);
  return result;
}

uint64_t number(const std::string& text, int base = 10) {
  return text.empty() ? 0 : std::stoull(text, nullptr, base);
}

Event parse(const std::string& line) {
  const auto c = split(line);
  if (c.size() != 20) throw std::runtime_error("invalid trace column count");
  Event e;
  e.cycle = number(c[0]); e.epoch = number(c[1]); e.name = c[2];
  e.id = std::stoi(c[3]); e.addr = number(c[4], 16); e.write = number(c[5]);
  e.data = number(c[6], 16); e.wstrb = number(c[7]); e.size = number(c[8]);
  e.error = number(c[9]); e.hit = number(c[10]); e.way = number(c[11]);
  e.valid = number(c[12]); e.dirty = number(c[13]); e.lru = number(c[14]);
  e.beat = number(c[15]); e.resp = number(c[16]); e.maint = number(c[17]);
  e.state = number(c[19]);
  return e;
}

struct Pending {
  int id = -1;
  uint32_t addr = 0;
  bool write = false;
  uint32_t data = 0;
  unsigned wstrb = 0;
  unsigned size = 0;
  bool axi_error = false;
  bool predicted = false;
  CacheReference before;
  CacheReference::Response expected;
};
}

int main(int argc, char** argv) {
  if (argc != 2 && argc != 4) {
    std::cerr << "usage: cache_trace_checker TRACE.csv [SETS WAYS]\n";
    return 2;
  }
  std::ifstream input(argv[1]);
  if (!input) {
    std::cerr << "unable to open " << argv[1] << "\n";
    return 2;
  }
  std::string line;
  std::getline(input, line);
  const unsigned sets = argc == 4 ? static_cast<unsigned>(std::stoul(argv[2])) : 64;
  const unsigned ways = argc == 4 ? static_cast<unsigned>(std::stoul(argv[3])) : 2;
  CacheReference model(sets, ways);
  std::optional<Pending> pending;
  std::optional<CacheReference> maintenance_before;
  std::unordered_map<uint32_t, uint32_t> observed_memory;
  std::unordered_map<uint32_t, uint32_t> final_memory;
  std::unordered_map<uint32_t, uint32_t> pending_write;
  unsigned responses = 0, axi_beats = 0, evictions = 0, memory_words = 0;
  unsigned mismatches = 0;
  auto mismatch = [&](const std::string& message, const Event& event) {
    std::cerr << argv[1] << ':' << event.cycle << ": " << message << '\n';
    ++mismatches;
  };

  while (std::getline(input, line)) {
    if (line.empty()) continue;
    const Event e = parse(line);
    if (e.name == "RESET_ASSERT") {
      if (pending) model = pending->before;
      else if (maintenance_before) model = *maintenance_before;
      for (const auto& [address, value] : observed_memory)
        model.set_memory(address << 2, value);
      model.reset(); pending.reset(); maintenance_before.reset();
    } else if (e.name == "CPU_ACCEPT") {
      if (pending) mismatch("accepted request while another request is pending", e);
      Pending next;
      next.id = e.id; next.addr = e.addr; next.write = e.write;
      next.data = static_cast<uint32_t>(e.data); next.wstrb = e.wstrb; next.size = e.size;
      next.before = model;
      pending = next;
    } else if (e.name == "LOOKUP" && pending) {
      pending->expected = model.access(pending->addr, pending->write, pending->data,
                                       pending->wstrb, pending->size);
      pending->predicted = true;
      if (e.hit != pending->expected.hit) mismatch("lookup hit/miss mismatch", e);
      if (!pending->expected.error && e.way != pending->expected.way)
        mismatch("selected way mismatch", e);
      if (!e.hit && (e.valid != pending->expected.victim_valid ||
                     e.dirty != pending->expected.victim_dirty ||
                     e.lru != pending->expected.prior_lru))
        mismatch("victim metadata mismatch", e);
      if (pending->expected.eviction) ++evictions;
    } else if (e.name == "AXI_AW") {
      pending_write.clear();
      if (pending && pending->predicted && pending->expected.eviction &&
          e.addr != pending->expected.victim_base)
        mismatch("writeback address mismatch", e);
    } else if (e.name == "AXI_W") {
      ++axi_beats;
      const uint32_t low = static_cast<uint32_t>(e.data);
      const uint32_t high = static_cast<uint32_t>(e.data >> 32);
      pending_write[(e.addr >> 2) + e.beat * 2] = low;
      pending_write[(e.addr >> 2) + e.beat * 2 + 1] = high;
      if (model.get_memory(e.addr + e.beat * 8) != low ||
          model.get_memory(e.addr + e.beat * 8 + 4) != high)
        mismatch("writeback data mismatch", e);
      if ((e.beat == 3) != (e.resp != 0)) mismatch("invalid WLAST", e);
      observed_memory[(e.addr >> 2) + e.beat * 2] = low;
      observed_memory[(e.addr >> 2) + e.beat * 2 + 1] = high;
      model.set_memory(e.addr + e.beat * 8, low);
      model.set_memory(e.addr + e.beat * 8 + 4, high);
    } else if (e.name == "AXI_B") {
      if (e.error) {
        if (pending) pending->axi_error = true;
      }
      pending_write.clear();
    } else if (e.name == "AXI_AR") {
      if (pending && pending->predicted && e.addr != pending->expected.refill_base)
        mismatch("refill address mismatch", e);
    } else if (e.name == "AXI_R") {
      ++axi_beats;
      if (e.error && pending) pending->axi_error = true;
      const uint32_t low = static_cast<uint32_t>(e.data);
      const uint32_t high = static_cast<uint32_t>(e.data >> 32);
      if (!e.error && (model.get_memory(e.addr + e.beat * 8) != low ||
                       model.get_memory(e.addr + e.beat * 8 + 4) != high))
        mismatch("refill data mismatch", e);
    } else if (e.name == "CPU_RESPONSE") {
      ++responses;
      if (!pending || pending->id != e.id) {
        mismatch("orphan or mismatched response", e);
      } else {
        if (!pending->predicted) {
          pending->expected = model.access(pending->addr, pending->write, pending->data,
                                           pending->wstrb, pending->size);
          pending->predicted = true;
        }
        const bool expected_error = pending->expected.error || pending->axi_error;
        if (e.error != expected_error) mismatch("response error mismatch", e);
        if (!expected_error && !pending->write &&
            static_cast<uint32_t>(e.data) != pending->expected.data)
          mismatch("response data mismatch", e);
        if (pending->axi_error) {
          model = pending->before;
          for (const auto& [address, value] : observed_memory)
            model.set_memory(address << 2, value);
        }
        pending.reset();
      }
    } else if (e.name == "MAINT_ACCEPT") {
      maintenance_before = model;
      model.maintenance(static_cast<uint8_t>(e.maint));
    } else if (e.name == "MAINT_DONE" && e.error && maintenance_before) {
      model = *maintenance_before;
      for (const auto& [address, value] : observed_memory)
        model.set_memory(address << 2, value);
      maintenance_before.reset();
    } else if (e.name == "MAINT_DONE") {
      maintenance_before.reset();
    } else if (e.name == "FINAL_MEMORY") {
      final_memory[e.addr >> 2] = static_cast<uint32_t>(e.data);
    }
  }

  for (const auto& [address, value] : final_memory) {
    ++memory_words;
    if (model.get_memory(address << 2) != value) {
      Event e; e.cycle = 0;
      mismatch("final backing-memory mismatch at word " + std::to_string(address), e);
    }
  }
  std::cout << "TRACE_CHECK|status=" << (mismatches ? "FAIL" : "PASS")
            << "|responses=" << responses << "|axi_beats=" << axi_beats
            << "|evictions=" << evictions << "|memory_words=" << memory_words
            << "|mismatches=" << mismatches << '\n';
  return mismatches ? 1 : 0;
}

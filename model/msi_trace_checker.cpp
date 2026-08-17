#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {
constexpr unsigned kLines = 8;
constexpr unsigned kWordsPerLine = 4;
enum State { I = 0, S = 1, M = 2 };
struct Line { State state = I; uint32_t tag = 0; std::array<uint32_t, kWordsPerLine> data{}; };
struct Model {
  std::array<std::array<Line, kLines>, 2> cache{};
  std::array<uint32_t, 1024> memory{};
  uint32_t read_miss = 0, write_miss = 0, invalidations = 0, interventions = 0, writebacks = 0;
  Model() { for (unsigned word = 0; word < 256; ++word) memory[word] = 0x10000000u ^ word; }
  uint32_t access(unsigned owner, bool write, uint32_t address, uint32_t wdata) {
    const unsigned other = owner ^ 1u;
    const unsigned index = (address >> 4) & (kLines - 1);
    const unsigned word = (address >> 2) & (kWordsPerLine - 1);
    const uint32_t tag = address >> 7;
    Line &local = cache[owner][index]; Line &peer = cache[other][index];
    const bool local_hit = local.state != I && local.tag == tag;
    const bool peer_hit = peer.state != I && peer.tag == tag;
    if (!local_hit && local.state == M) {
      const uint32_t base = ((local.tag << 7) | (index << 4)) >> 2;
      for (unsigned i = 0; i < kWordsPerLine; ++i) memory[base + i] = local.data[i];
      ++writebacks;
    }
    if (!local_hit) {
      write ? ++write_miss : ++read_miss;
      if (peer_hit) {
        if (peer.state == M) {
          const uint32_t base = address >> 2 & ~uint32_t(kWordsPerLine - 1);
          for (unsigned i = 0; i < kWordsPerLine; ++i) memory[base + i] = peer.data[i];
          ++interventions;
        }
        local.data = peer.data;
      } else {
        const uint32_t base = address >> 2 & ~uint32_t(kWordsPerLine - 1);
        for (unsigned i = 0; i < kWordsPerLine; ++i) local.data[i] = memory[base + i];
      }
      local.tag = tag;
    }
    if (write) {
      if (peer_hit) { peer.state = I; ++invalidations; }
      local.state = M; local.tag = tag; local.data[word] = wdata; return wdata;
    }
    if (!local_hit) { local.state = S; if (peer_hit) peer.state = S; }
    return local.data[word];
  }
};
std::vector<std::string> split(const std::string &line) {
  std::vector<std::string> fields; std::stringstream stream(line); std::string field;
  while (std::getline(stream, field, ',')) fields.push_back(field);
  return fields;
}
uint32_t hex(const std::string &value) { return static_cast<uint32_t>(std::stoul(value, nullptr, 16)); }
}

int main(int argc, char **argv) {
  if (argc != 2) { std::cerr << "usage: msi_trace_checker trace.csv\n"; return 2; }
  std::ifstream input(argv[1]); Model model; std::string line; unsigned checked = 0, mismatches = 0;
  while (std::getline(input, line)) {
    auto f = split(line); if (f.empty()) continue;
    if (f[0] == "OP") {
      const auto expected = model.access(std::stoul(f[2]), std::stoul(f[3]), hex(f[4]), hex(f[5]));
      const auto observed = hex(f[6]); ++checked;
      if (expected != observed) { ++mismatches; std::cerr << "response mismatch op=" << f[1]
          << " expected=0x" << std::hex << expected << " observed=0x" << observed << std::dec << "\n"; }
    } else if (f[0] == "STATS") {
      const std::array<uint32_t, 5> expected = {model.read_miss, model.write_miss, model.invalidations,
                                                model.interventions, model.writebacks};
      for (unsigned i = 0; i < expected.size(); ++i) if (expected[i] != std::stoul(f[i + 1])) {
        ++mismatches; std::cerr << "counter mismatch index=" << i << " expected=" << expected[i]
                               << " observed=" << f[i + 1] << "\n";
      }
    }
  }
  std::cout << "MSI_MODEL|status=" << (mismatches ? "FAIL" : "PASS") << "|operations=" << checked
            << "|mismatches=" << mismatches << "|read_miss=" << model.read_miss
            << "|write_miss=" << model.write_miss << "|invalidations=" << model.invalidations
            << "|interventions=" << model.interventions << "|writebacks=" << model.writebacks << "\n";
  return mismatches ? 1 : 0;
}

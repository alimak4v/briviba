#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

namespace {

struct Entry {
  std::string_view type;
  std::string_view filename;
};

constexpr Entry kEntries[] = {
    {"icp4", "icon_16x16.png"},
    {"icp5", "icon_32x32.png"},
    {"icp6", "icon_32x32@2x.png"},
    {"ic07", "icon_128x128.png"},
    {"ic08", "icon_256x256.png"},
    {"ic09", "icon_512x512.png"},
    {"ic10", "icon_512x512@2x.png"},
};

std::vector<char> ReadFile(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  return std::vector<char>(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

void WriteAscii(std::ofstream& output, std::string_view value) {
  output.write(value.data(), static_cast<std::streamsize>(value.size()));
}

void WriteUInt32BE(std::ofstream& output, uint32_t value) {
  const char bytes[] = {
      static_cast<char>((value >> 24U) & 0xFFU),
      static_cast<char>((value >> 16U) & 0xFFU),
      static_cast<char>((value >> 8U) & 0xFFU),
      static_cast<char>(value & 0xFFU),
  };
  output.write(bytes, sizeof(bytes));
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc != 3) {
    std::cerr << "usage: make_icns iconset output.icns\n";
    return EXIT_FAILURE;
  }

  const std::filesystem::path iconset_path(argv[1]);
  const std::filesystem::path output_path(argv[2]);
  std::vector<std::pair<Entry, std::vector<char>>> payloads;
  uint32_t total_size = 8;

  for (const Entry& entry : kEntries) {
    std::vector<char> data = ReadFile(iconset_path / entry.filename);
    if (data.empty()) {
      std::cerr << "missing or empty " << entry.filename << "\n";
      return EXIT_FAILURE;
    }
    total_size += static_cast<uint32_t>(8 + data.size());
    payloads.push_back({entry, std::move(data)});
  }

  std::ofstream output(output_path, std::ios::binary);
  if (!output) {
    std::cerr << "failed to open output\n";
    return EXIT_FAILURE;
  }

  WriteAscii(output, "icns");
  WriteUInt32BE(output, total_size);

  for (const auto& payload : payloads) {
    WriteAscii(output, payload.first.type);
    WriteUInt32BE(output, static_cast<uint32_t>(8 + payload.second.size()));
    output.write(payload.second.data(), static_cast<std::streamsize>(payload.second.size()));
  }

  return EXIT_SUCCESS;
}

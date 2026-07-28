#include "briviba/app_paths.h"

#include <cstdlib>
#include <filesystem>
#include <string>

namespace briviba {
namespace {

std::filesystem::path HomeDirectory() {
  const char* home = std::getenv("HOME");
  if (home == nullptr || std::string(home).empty()) {
    return std::filesystem::current_path();
  }
  return std::filesystem::path(home);
}

}  // namespace

std::filesystem::path ApplicationSupportFile(const std::string& filename) {
  return HomeDirectory() / "Library" / "Application Support" / "Briviba" / filename;
}

}  // namespace briviba

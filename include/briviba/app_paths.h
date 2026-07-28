#ifndef BRIVIBA_APP_PATHS_H_
#define BRIVIBA_APP_PATHS_H_

#include <filesystem>
#include <string>

namespace briviba {

std::filesystem::path ApplicationSupportFile(const std::string& filename);

}  // namespace briviba

#endif  // BRIVIBA_APP_PATHS_H_

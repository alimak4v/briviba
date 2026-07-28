#ifndef BRIVIBA_HISTORY_MANAGER_H_
#define BRIVIBA_HISTORY_MANAGER_H_

#include <filesystem>
#include <memory>
#include <string>

namespace briviba {

class HistoryManager {
 public:
  explicit HistoryManager(std::filesystem::path database_path);
  ~HistoryManager();

  HistoryManager(const HistoryManager&) = delete;
  HistoryManager& operator=(const HistoryManager&) = delete;

  static std::filesystem::path DefaultDatabasePath();

  bool RecordVisit(const std::string& url);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_HISTORY_MANAGER_H_

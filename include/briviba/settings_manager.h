#ifndef BRIVIBA_SETTINGS_MANAGER_H_
#define BRIVIBA_SETTINGS_MANAGER_H_

#include <filesystem>
#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace briviba {

class SettingsManager {
 public:
  explicit SettingsManager(std::filesystem::path database_path);
  ~SettingsManager();

  SettingsManager(const SettingsManager&) = delete;
  SettingsManager& operator=(const SettingsManager&) = delete;

  static std::filesystem::path DefaultDatabasePath();

  bool StartWithSecureMode() const;
  void SetStartWithSecureMode(bool value);
  bool ToggleStartWithSecureMode();
  std::string DefaultSearchEngine() const;
  void SetDefaultSearchEngine(const std::string& engine_id);
  std::vector<std::string> SessionTabUrls() const;
  size_t SessionActiveTabIndex() const;
  void SetSessionState(const std::vector<std::string>& urls, size_t active_index);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_SETTINGS_MANAGER_H_

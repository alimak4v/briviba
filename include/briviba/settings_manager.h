#ifndef BRIVIBA_SETTINGS_MANAGER_H_
#define BRIVIBA_SETTINGS_MANAGER_H_

#include <filesystem>
#include <memory>
#include <string>

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

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_SETTINGS_MANAGER_H_

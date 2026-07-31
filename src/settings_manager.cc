#include "briviba/settings_manager.h"

#include "briviba/app_paths.h"

#include <sqlite3.h>

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace briviba {
namespace {

constexpr const char* kStartWithSecureModeKey = "start_with_secure_mode";
constexpr const char* kDefaultSearchEngineKey = "default_search_engine";
constexpr const char* kTabDockPositionKey = "tab_dock_position";
constexpr const char* kSessionTabsKey = "session_tabs";
constexpr const char* kSessionActiveTabKey = "session_active_tab";
constexpr const char* kDefaultSearchEngine = "duckduckgo";
constexpr const char* kDefaultTabDockPosition = "left";

class Statement {
 public:
  Statement(sqlite3* database, const char* sql) {
    if (sqlite3_prepare_v2(database, sql, -1, &statement_, nullptr) != SQLITE_OK) {
      statement_ = nullptr;
    }
  }

  ~Statement() {
    if (statement_ != nullptr) {
      sqlite3_finalize(statement_);
    }
  }

  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;

  sqlite3_stmt* get() const { return statement_; }

 private:
  sqlite3_stmt* statement_ = nullptr;
};

std::vector<std::string> SplitLines(const std::string& value) {
  std::vector<std::string> lines;
  size_t start = 0;
  while (start <= value.size()) {
    const size_t end = value.find('\n', start);
    std::string line = value.substr(start, end == std::string::npos ? std::string::npos
                                                                    : end - start);
    if (!line.empty()) {
      lines.push_back(std::move(line));
    }
    if (end == std::string::npos) {
      break;
    }
    start = end + 1;
  }
  return lines;
}

std::string JoinLines(const std::vector<std::string>& values) {
  std::string result;
  for (const std::string& value : values) {
    if (value.empty()) {
      continue;
    }
    if (!result.empty()) {
      result += '\n';
    }
    result += value;
  }
  return result;
}

}  // namespace

class SettingsManager::Impl {
 public:
  explicit Impl(std::filesystem::path database_path) : database_path_(std::move(database_path)) {
    std::filesystem::create_directories(database_path_.parent_path());

    sqlite3* database = nullptr;
    if (sqlite3_open(database_path_.string().c_str(), &database) == SQLITE_OK) {
      database_.reset(database);
      EnsureSchema();
    } else if (database != nullptr) {
      sqlite3_close(database);
    }
  }

  bool StartWithSecureMode() const { return BoolValue(kStartWithSecureModeKey); }

  void SetStartWithSecureMode(bool value) { SetBoolValue(kStartWithSecureModeKey, value); }

  std::string DefaultSearchEngine() const {
    const std::string engine_id = StringValue(kDefaultSearchEngineKey, kDefaultSearchEngine);
    if (engine_id == "duckduckgo" || engine_id == "google" || engine_id == "bing" ||
        engine_id == "yandex") {
      return engine_id;
    }
    return kDefaultSearchEngine;
  }

  void SetDefaultSearchEngine(const std::string& engine_id) {
    if (engine_id != "duckduckgo" && engine_id != "google" && engine_id != "bing" &&
        engine_id != "yandex") {
      return;
    }
    SetStringValue(kDefaultSearchEngineKey, engine_id);
  }

  SettingsManager::SidebarDockPosition TabDockPosition() const {
    const std::string value = StringValue(kTabDockPositionKey, kDefaultTabDockPosition);
    if (value == "top") {
      return SettingsManager::SidebarDockPosition::kTop;
    }
    return SettingsManager::SidebarDockPosition::kLeft;
  }

  void SetTabDockPosition(SettingsManager::SidebarDockPosition position) {
    SetStringValue(kTabDockPositionKey,
                   position == SettingsManager::SidebarDockPosition::kTop ? "top" : "left");
  }

  std::vector<std::string> SessionTabUrls() const {
    return SplitLines(StringValue(kSessionTabsKey, std::string()));
  }

  size_t SessionActiveTabIndex() const {
    const std::string value = StringValue(kSessionActiveTabKey, "0");
    char* end = nullptr;
    const unsigned long long parsed = std::strtoull(value.c_str(), &end, 10);
    if (end == value.c_str() || (end != nullptr && *end != '\0')) {
      return 0;
    }
    return static_cast<size_t>(parsed);
  }

  void SetSessionState(const std::vector<std::string>& urls, size_t active_index) {
    std::vector<std::string> filtered_urls;
    filtered_urls.reserve(urls.size());
    for (const std::string& url : urls) {
      if (!url.empty()) {
        filtered_urls.push_back(url);
      }
    }
    if (filtered_urls.empty()) {
      return;
    }

    const size_t clamped_active_index =
        std::min(active_index, filtered_urls.empty() ? size_t{0} : filtered_urls.size() - 1);
    SetStringValue(kSessionTabsKey, JoinLines(filtered_urls));
    SetStringValue(kSessionActiveTabKey, std::to_string(clamped_active_index));
  }

  bool ToggleStartWithSecureMode() {
    const bool next_value = !StartWithSecureMode();
    SetBoolValue(kStartWithSecureModeKey, next_value);
    return next_value;
  }

 private:
  struct DatabaseDeleter {
    void operator()(sqlite3* database) const {
      if (database != nullptr) {
        sqlite3_close(database);
      }
    }
  };

  void EnsureSchema() {
    const char* sql =
        "CREATE TABLE IF NOT EXISTS settings("
        "key TEXT PRIMARY KEY,"
        "value TEXT NOT NULL"
        ");";
    sqlite3_exec(database_.get(), sql, nullptr, nullptr, nullptr);
  }

  bool BoolValue(const std::string& key) const {
    if (database_ == nullptr) {
      return false;
    }

    Statement statement(database_.get(), "SELECT value FROM settings WHERE key = ?1;");
    if (statement.get() == nullptr) {
      return false;
    }

    sqlite3_bind_text(statement.get(), 1, key.c_str(), -1, SQLITE_TRANSIENT);
    if (sqlite3_step(statement.get()) != SQLITE_ROW) {
      return false;
    }

    const unsigned char* text = sqlite3_column_text(statement.get(), 0);
    return text != nullptr && std::string(reinterpret_cast<const char*>(text)) == "true";
  }

  std::string StringValue(const std::string& key, const std::string& default_value) const {
    if (database_ == nullptr) {
      return default_value;
    }

    Statement statement(database_.get(), "SELECT value FROM settings WHERE key = ?1;");
    if (statement.get() == nullptr) {
      return default_value;
    }

    sqlite3_bind_text(statement.get(), 1, key.c_str(), -1, SQLITE_TRANSIENT);
    if (sqlite3_step(statement.get()) != SQLITE_ROW) {
      return default_value;
    }

    const unsigned char* text = sqlite3_column_text(statement.get(), 0);
    return text == nullptr ? default_value : std::string(reinterpret_cast<const char*>(text));
  }

  void SetBoolValue(const std::string& key, bool value) {
    SetStringValue(key, value ? "true" : "false");
  }

  void SetStringValue(const std::string& key, const std::string& value) {
    if (database_ == nullptr) {
      return;
    }

    Statement statement(database_.get(),
                        "INSERT INTO settings(key, value) VALUES(?1, ?2) "
                        "ON CONFLICT(key) DO UPDATE SET value = excluded.value;");
    if (statement.get() == nullptr) {
      return;
    }

    sqlite3_bind_text(statement.get(), 1, key.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement.get(), 2, value.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_step(statement.get());
  }

  std::filesystem::path database_path_;
  std::unique_ptr<sqlite3, DatabaseDeleter> database_;
};

SettingsManager::SettingsManager(std::filesystem::path database_path)
    : impl_(std::make_unique<Impl>(std::move(database_path))) {}

SettingsManager::~SettingsManager() = default;

std::filesystem::path SettingsManager::DefaultDatabasePath() {
  return ApplicationSupportFile("settings.sqlite3");
}

bool SettingsManager::StartWithSecureMode() const {
  return impl_->StartWithSecureMode();
}

void SettingsManager::SetStartWithSecureMode(bool value) {
  impl_->SetStartWithSecureMode(value);
}

bool SettingsManager::ToggleStartWithSecureMode() {
  return impl_->ToggleStartWithSecureMode();
}

std::string SettingsManager::DefaultSearchEngine() const {
  return impl_->DefaultSearchEngine();
}

void SettingsManager::SetDefaultSearchEngine(const std::string& engine_id) {
  impl_->SetDefaultSearchEngine(engine_id);
}

SettingsManager::SidebarDockPosition SettingsManager::TabDockPosition() const {
  return impl_->TabDockPosition();
}

void SettingsManager::SetTabDockPosition(SidebarDockPosition position) {
  impl_->SetTabDockPosition(position);
}

std::vector<std::string> SettingsManager::SessionTabUrls() const {
  return impl_->SessionTabUrls();
}

size_t SettingsManager::SessionActiveTabIndex() const {
  return impl_->SessionActiveTabIndex();
}

void SettingsManager::SetSessionState(const std::vector<std::string>& urls, size_t active_index) {
  impl_->SetSessionState(urls, active_index);
}

}  // namespace briviba

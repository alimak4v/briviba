#include "briviba/cookie_manager.h"

#include "briviba/app_paths.h"

#include <sqlite3.h>

#import <WebKit/WebKit.h>

#include <filesystem>
#include <memory>
#include <string>
#include <utility>

namespace briviba {
namespace {

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

}  // namespace

class CookieManager::Impl {
 public:
  explicit Impl(std::filesystem::path database_path) : database_path_(std::move(database_path)) {
    normal_data_store_ = [WKWebsiteDataStore defaultDataStore];
    std::filesystem::create_directories(database_path_.parent_path());

    sqlite3* database = nullptr;
    if (sqlite3_open(database_path_.string().c_str(), &database) == SQLITE_OK) {
      database_.reset(database);
      EnsureSchema();
      return;
    }

    if (database != nullptr) {
      sqlite3_close(database);
    }
  }

  WKWebsiteDataStore* NormalWebsiteDataStore() const { return normal_data_store_; }

  WKWebsiteDataStore* SecureWebsiteDataStore() const {
    if (secure_data_store_ == nil) {
      secure_data_store_ = [WKWebsiteDataStore nonPersistentDataStore];
    }
    return secure_data_store_;
  }

  WKWebsiteDataStore* WebsiteDataStoreForTopLevelSite(const std::string& top_level_site) {
    if (top_level_site.empty() || database_ == nullptr) {
      return normal_data_store_;
    }

    NSUUID* identifier = IdentifierForTopLevelSite(top_level_site);
    if (identifier == nil) {
      return normal_data_store_;
    }
    return [WKWebsiteDataStore dataStoreForIdentifier:identifier];
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
        "CREATE TABLE IF NOT EXISTS top_level_site_containers("
        "top_level_site TEXT PRIMARY KEY,"
        "identifier TEXT NOT NULL UNIQUE"
        ");";
    sqlite3_exec(database_.get(), sql, nullptr, nullptr, nullptr);
  }

  NSUUID* IdentifierForTopLevelSite(const std::string& top_level_site) {
    NSUUID* existing_identifier = ExistingIdentifierForTopLevelSite(top_level_site);
    if (existing_identifier != nil) {
      return existing_identifier;
    }

    NSUUID* identifier = [NSUUID UUID];
    Statement statement(database_.get(),
                        "INSERT INTO top_level_site_containers(top_level_site, identifier) "
                        "VALUES(?1, ?2);");
    if (statement.get() == nullptr) {
      return nil;
    }

    NSString* identifier_string = [identifier UUIDString];
    sqlite3_bind_text(statement.get(), 1, top_level_site.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement.get(), 2, [identifier_string UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(statement.get()) != SQLITE_DONE) {
      return nil;
    }
    return identifier;
  }

  NSUUID* ExistingIdentifierForTopLevelSite(const std::string& top_level_site) {
    Statement statement(database_.get(),
                        "SELECT identifier FROM top_level_site_containers "
                        "WHERE top_level_site = ?1;");
    if (statement.get() == nullptr) {
      return nil;
    }

    sqlite3_bind_text(statement.get(), 1, top_level_site.c_str(), -1, SQLITE_TRANSIENT);
    if (sqlite3_step(statement.get()) != SQLITE_ROW) {
      return nil;
    }

    const unsigned char* text = sqlite3_column_text(statement.get(), 0);
    if (text == nullptr) {
      return nil;
    }

    NSString* identifier_string =
        [NSString stringWithUTF8String:reinterpret_cast<const char*>(text)];
    return [[NSUUID alloc] initWithUUIDString:identifier_string];
  }

  std::filesystem::path database_path_;
  std::unique_ptr<sqlite3, DatabaseDeleter> database_;
  mutable WKWebsiteDataStore* secure_data_store_ = nil;
  WKWebsiteDataStore* normal_data_store_ = nil;
};

CookieManager::CookieManager(std::filesystem::path database_path)
    : impl_(std::make_unique<Impl>(std::move(database_path))) {}

CookieManager::~CookieManager() = default;

std::filesystem::path CookieManager::DefaultDatabasePath() {
  return ApplicationSupportFile("site-containers.sqlite3");
}

WKWebsiteDataStore* CookieManager::NormalWebsiteDataStore() const {
  return impl_->NormalWebsiteDataStore();
}

WKWebsiteDataStore* CookieManager::SecureWebsiteDataStore() const {
  return impl_->SecureWebsiteDataStore();
}

WKWebsiteDataStore* CookieManager::WebsiteDataStoreForTopLevelSite(
    const std::string& top_level_site) {
  return impl_->WebsiteDataStoreForTopLevelSite(top_level_site);
}

}  // namespace briviba

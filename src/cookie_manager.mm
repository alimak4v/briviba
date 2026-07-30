#include "briviba/cookie_manager.h"

#include "briviba/app_paths.h"

#include <sqlite3.h>

#import <WebKit/WebKit.h>

#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <vector>

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
  explicit Impl(std::filesystem::path database_path) {
    normal_data_store_ = [WKWebsiteDataStore defaultDataStore];
    StartLegacySiteContainerCookieMigration(database_path);
  }

  WKWebsiteDataStore* NormalWebsiteDataStore() const { return normal_data_store_; }

  WKWebsiteDataStore* SecureWebsiteDataStore() const {
    if (secure_data_store_ == nil) {
      secure_data_store_ = [WKWebsiteDataStore nonPersistentDataStore];
    }
    return secure_data_store_;
  }

  WKWebsiteDataStore* WebsiteDataStoreForTopLevelSite(const std::string& top_level_site) {
    (void)top_level_site;
    return normal_data_store_;
  }

  void WhenReady(std::function<void()> callback) {
    if (ready_) {
      callback();
      return;
    }
    ready_callbacks_.push_back(std::move(callback));
  }

 private:
  struct DatabaseDeleter {
    void operator()(sqlite3* database) const {
      if (database != nullptr) {
        sqlite3_close(database);
      }
    }
  };

  void StartLegacySiteContainerCookieMigration(const std::filesystem::path& database_path) {
    if (!std::filesystem::exists(database_path)) {
      MarkReady();
      return;
    }

    sqlite3* raw_database = nullptr;
    if (sqlite3_open_v2(database_path.string().c_str(), &raw_database,
                        SQLITE_OPEN_READONLY | SQLITE_OPEN_PRIVATECACHE, nullptr) != SQLITE_OK) {
      if (raw_database != nullptr) {
        sqlite3_close(raw_database);
      }
      MarkReady();
      return;
    }

    std::unique_ptr<sqlite3, DatabaseDeleter> database(raw_database);
    Statement statement(database.get(),
                        "SELECT identifier FROM top_level_site_containers "
                        "WHERE identifier IS NOT NULL AND identifier <> '';");
    if (statement.get() == nullptr) {
      MarkReady();
      return;
    }

    std::vector<std::string> identifiers;
    while (sqlite3_step(statement.get()) == SQLITE_ROW) {
      const unsigned char* text = sqlite3_column_text(statement.get(), 0);
      if (text != nullptr) {
        identifiers.emplace_back(reinterpret_cast<const char*>(text));
      }
    }
    if (identifiers.empty()) {
      MarkReady();
      return;
    }

    WKHTTPCookieStore* target_cookie_store = [normal_data_store_ httpCookieStore];
    pending_legacy_cookie_operations_ = identifiers.size();
    for (const std::string& identifier : identifiers) {
      NSString* identifier_string = [NSString stringWithUTF8String:identifier.c_str()];
      NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:identifier_string];
      if (uuid == nil) {
        CompleteLegacyCookieOperation();
        continue;
      }

      WKWebsiteDataStore* legacy_data_store = [WKWebsiteDataStore dataStoreForIdentifier:uuid];
      WKHTTPCookieStore* source_cookie_store = [legacy_data_store httpCookieStore];
      [source_cookie_store getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
        dispatch_async(dispatch_get_main_queue(), ^{
          pending_legacy_cookie_operations_ += [cookies count];
          CompleteLegacyCookieOperation();
          for (NSHTTPCookie* cookie in cookies) {
            [target_cookie_store setCookie:cookie
                         completionHandler:^{
                           dispatch_async(dispatch_get_main_queue(), ^{
                             CompleteLegacyCookieOperation();
                           });
                         }];
          }
        });
      }];
    }
  }

  void CompleteLegacyCookieOperation() {
    if (pending_legacy_cookie_operations_ == 0) {
      return;
    }
    --pending_legacy_cookie_operations_;
    if (pending_legacy_cookie_operations_ == 0) {
      MarkReady();
    }
  }

  void MarkReady() {
    if (ready_) {
      return;
    }
    ready_ = true;
    std::vector<std::function<void()>> callbacks;
    callbacks.swap(ready_callbacks_);
    for (auto& callback : callbacks) {
      callback();
    }
  }

  size_t pending_legacy_cookie_operations_ = 0;
  bool ready_ = false;
  std::vector<std::function<void()>> ready_callbacks_;
  mutable WKWebsiteDataStore* secure_data_store_ = nil;
  WKWebsiteDataStore* normal_data_store_ = nil;
};

CookieManager::CookieManager(std::filesystem::path database_path)
    : impl_(std::make_unique<Impl>(std::move(database_path))) {}

CookieManager::~CookieManager() = default;

std::filesystem::path CookieManager::DefaultDatabasePath() {
  return ApplicationSupportFile("site-containers.sqlite3");
}

void CookieManager::WhenReady(std::function<void()> callback) {
  impl_->WhenReady(std::move(callback));
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

#include "briviba/cookie_manager.h"

#include "briviba/app_paths.h"

#include <sqlite3.h>

#import <WebKit/WebKit.h>

#include <algorithm>
#include <cctype>
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

std::string StringFromNSString(NSString* value) {
  const char* utf8 = [value UTF8String];
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

std::string NormalizeDomain(std::string domain) {
  while (!domain.empty() && domain.front() == '.') {
    domain.erase(domain.begin());
  }
  std::transform(domain.begin(), domain.end(), domain.begin(), [](unsigned char character) {
    return static_cast<char>(std::tolower(character));
  });
  return domain;
}

bool DomainMatches(const std::string& candidate, const std::string& domain) {
  const std::string normalized_candidate = NormalizeDomain(candidate);
  const std::string normalized_domain = NormalizeDomain(domain);
  if (normalized_candidate.empty() || normalized_domain.empty()) {
    return false;
  }
  if (normalized_candidate == normalized_domain) {
    return true;
  }
  return normalized_candidate.size() > normalized_domain.size() &&
         normalized_candidate.ends_with("." + normalized_domain);
}

std::string DateString(NSDate* date) {
  if (date == nil) {
    return std::string();
  }
  NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
  [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
  [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  return StringFromNSString([formatter stringFromDate:date]);
}

NSSet<NSString*>* CookieAndSiteStateTypes() {
  return [NSSet setWithArray:@[
    WKWebsiteDataTypeCookies,
    WKWebsiteDataTypeLocalStorage,
    WKWebsiteDataTypeSessionStorage,
    WKWebsiteDataTypeIndexedDBDatabases,
    WKWebsiteDataTypeWebSQLDatabases,
  ]];
}

NSSet<NSString*>* CacheTypes() {
  return [NSSet setWithArray:@[
    WKWebsiteDataTypeDiskCache,
    WKWebsiteDataTypeMemoryCache,
    WKWebsiteDataTypeOfflineWebApplicationCache,
    WKWebsiteDataTypeServiceWorkerRegistrations,
  ]];
}

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

  void ClearAllCookiesAndSiteState(std::function<void()> callback) {
    [normal_data_store_
        removeDataOfTypes:CookieAndSiteStateTypes()
            modifiedSince:[NSDate distantPast]
        completionHandler:^{
          RunCallback(std::move(callback));
        }];
  }

  void ClearAllCaches(std::function<void()> callback) {
    [normal_data_store_ removeDataOfTypes:CacheTypes()
                            modifiedSince:[NSDate distantPast]
                        completionHandler:^{
                          RunCallback(std::move(callback));
                        }];
  }

  void ClearCookiesAndSiteStateForDomain(const std::string& domain, std::function<void()> callback) {
    const std::string normalized_domain = NormalizeDomain(domain);
    WKHTTPCookieStore* cookie_store = [normal_data_store_ httpCookieStore];
    [cookie_store getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
      __block size_t pending_cookie_deletes = 0;
      for (NSHTTPCookie* cookie in cookies) {
        if (DomainMatches(StringFromNSString([cookie domain]), normalized_domain)) {
          ++pending_cookie_deletes;
        }
      }

      auto remove_records = [this, normalized_domain, callback = std::move(callback)]() mutable {
        RemoveWebsiteDataRecords(CookieAndSiteStateTypes(), normalized_domain, std::move(callback));
      };

      if (pending_cookie_deletes == 0) {
        remove_records();
        return;
      }

      __block auto record_removal = std::move(remove_records);
      for (NSHTTPCookie* cookie in cookies) {
        if (!DomainMatches(StringFromNSString([cookie domain]), normalized_domain)) {
          continue;
        }
        [cookie_store deleteCookie:cookie
                 completionHandler:^{
                   --pending_cookie_deletes;
                   if (pending_cookie_deletes == 0) {
                     record_removal();
                   }
                 }];
      }
    }];
  }

  void ClearCachesForDomain(const std::string& domain, std::function<void()> callback) {
    RemoveWebsiteDataRecords(CacheTypes(), NormalizeDomain(domain), std::move(callback));
  }

  void ListCookies(std::function<void(std::vector<CookieInfo>)> callback) {
    [[normal_data_store_ httpCookieStore] getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
      std::vector<CookieInfo> infos;
      infos.reserve([cookies count]);
      for (NSHTTPCookie* cookie in cookies) {
        CookieInfo info;
        info.name = StringFromNSString([cookie name]);
        info.value = StringFromNSString([cookie value]);
        info.domain = StringFromNSString([cookie domain]);
        info.path = StringFromNSString([cookie path]);
        info.expires = DateString([cookie expiresDate]);
        info.secure = [cookie isSecure];
        info.http_only = [[cookie properties][@"HttpOnly"] boolValue];
        infos.push_back(std::move(info));
      }
      callback(std::move(infos));
    }];
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

  void RemoveWebsiteDataRecords(NSSet<NSString*>* data_types, const std::string& domain,
                                std::function<void()> callback) {
    [normal_data_store_ fetchDataRecordsOfTypes:data_types
                              completionHandler:^(NSArray<WKWebsiteDataRecord*>* records) {
                                NSMutableArray<WKWebsiteDataRecord*>* matching_records =
                                    [NSMutableArray array];
                                for (WKWebsiteDataRecord* record in records) {
                                  if (DomainMatches(StringFromNSString([record displayName]),
                                                    domain)) {
                                    [matching_records addObject:record];
                                  }
                                }
                                if ([matching_records count] == 0) {
                                  RunCallback(std::move(callback));
                                  return;
                                }
                                [normal_data_store_
                                      removeDataOfTypes:data_types
                                        forDataRecords:matching_records
                                     completionHandler:^{
                                       RunCallback(std::move(callback));
                                     }];
                              }];
  }

  void RunCallback(std::function<void()> callback) {
    if (!callback) {
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      callback();
    });
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

void CookieManager::ClearAllCookiesAndSiteState(std::function<void()> callback) {
  impl_->ClearAllCookiesAndSiteState(std::move(callback));
}

void CookieManager::ClearAllCaches(std::function<void()> callback) {
  impl_->ClearAllCaches(std::move(callback));
}

void CookieManager::ClearCookiesAndSiteStateForDomain(const std::string& domain,
                                                      std::function<void()> callback) {
  impl_->ClearCookiesAndSiteStateForDomain(domain, std::move(callback));
}

void CookieManager::ClearCachesForDomain(const std::string& domain,
                                         std::function<void()> callback) {
  impl_->ClearCachesForDomain(domain, std::move(callback));
}

void CookieManager::ListCookies(std::function<void(std::vector<CookieInfo>)> callback) {
  impl_->ListCookies(std::move(callback));
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

#ifndef BRIVIBA_COOKIE_MANAGER_H_
#define BRIVIBA_COOKIE_MANAGER_H_

#include <filesystem>
#include <memory>
#include <string>

#ifdef __OBJC__
@class WKWebsiteDataStore;
#endif

namespace briviba {

class CookieManager {
 public:
  explicit CookieManager(std::filesystem::path database_path);
  ~CookieManager();

  CookieManager(const CookieManager&) = delete;
  CookieManager& operator=(const CookieManager&) = delete;

  static std::filesystem::path DefaultDatabasePath();

#ifdef __OBJC__
  WKWebsiteDataStore* NormalWebsiteDataStore() const;
  WKWebsiteDataStore* SecureWebsiteDataStore() const;
  WKWebsiteDataStore* WebsiteDataStoreForTopLevelSite(const std::string& top_level_site);
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_COOKIE_MANAGER_H_

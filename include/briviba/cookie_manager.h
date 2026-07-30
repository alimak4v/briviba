#ifndef BRIVIBA_COOKIE_MANAGER_H_
#define BRIVIBA_COOKIE_MANAGER_H_

#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#ifdef __OBJC__
@class WKWebsiteDataStore;
#endif

namespace briviba {

class CookieManager {
 public:
  struct CookieInfo {
    std::string name;
    std::string value;
    std::string domain;
    std::string path;
    std::string expires;
    bool secure = false;
    bool http_only = false;
  };

  explicit CookieManager(std::filesystem::path database_path);
  ~CookieManager();

  CookieManager(const CookieManager&) = delete;
  CookieManager& operator=(const CookieManager&) = delete;

  static std::filesystem::path DefaultDatabasePath();
  void WhenReady(std::function<void()> callback);
  void ClearAllCookiesAndSiteState(std::function<void()> callback);
  void ClearAllCaches(std::function<void()> callback);
  void ClearCookiesAndSiteStateForDomain(const std::string& domain, std::function<void()> callback);
  void ClearCachesForDomain(const std::string& domain, std::function<void()> callback);
  void ListCookies(std::function<void(std::vector<CookieInfo>)> callback);

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

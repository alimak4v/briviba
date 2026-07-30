#include "briviba/cookie_manager.h"

#include "briviba/app_paths.h"

#import <WebKit/WebKit.h>

#include <filesystem>
#include <memory>
#include <string>

namespace briviba {

class CookieManager::Impl {
 public:
  explicit Impl(std::filesystem::path database_path) {
    (void)database_path;
    normal_data_store_ = [WKWebsiteDataStore defaultDataStore];
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

 private:
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

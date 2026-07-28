#include "briviba/cookie_manager.h"

#import <WebKit/WebKit.h>

namespace briviba {

class CookieManager::Impl {
 public:
  Impl() { normal_data_store_ = [WKWebsiteDataStore defaultDataStore]; }

  WKWebsiteDataStore* NormalWebsiteDataStore() const { return normal_data_store_; }

 private:
  WKWebsiteDataStore* normal_data_store_ = nil;
};

CookieManager::CookieManager() : impl_(std::make_unique<Impl>()) {}

CookieManager::~CookieManager() = default;

WKWebsiteDataStore* CookieManager::NormalWebsiteDataStore() const {
  return impl_->NormalWebsiteDataStore();
}

}  // namespace briviba

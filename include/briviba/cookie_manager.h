#ifndef BRIVIBA_COOKIE_MANAGER_H_
#define BRIVIBA_COOKIE_MANAGER_H_

#include <memory>

#ifdef __OBJC__
@class WKWebsiteDataStore;
#endif

namespace briviba {

class CookieManager {
 public:
  CookieManager();
  ~CookieManager();

  CookieManager(const CookieManager&) = delete;
  CookieManager& operator=(const CookieManager&) = delete;

#ifdef __OBJC__
  WKWebsiteDataStore* NormalWebsiteDataStore() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_COOKIE_MANAGER_H_

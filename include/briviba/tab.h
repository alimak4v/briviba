#ifndef BRIVIBA_TAB_H_
#define BRIVIBA_TAB_H_

#include <functional>
#include <memory>
#include <string>

#ifdef __OBJC__
@class NSView;
@class WKWebsiteDataStore;
#endif

namespace briviba {

class Tab {
 public:
  struct PageColor {
    double red = 1.0;
    double green = 1.0;
    double blue = 1.0;
    double alpha = 1.0;
  };

  using NavigationStateCallback =
      std::function<void(bool can_go_back, bool can_go_forward, const std::string& url)>;
  using PageColorCallback = std::function<void(PageColor color)>;

#ifdef __OBJC__
  explicit Tab(WKWebsiteDataStore* website_data_store);
#endif
  ~Tab();

  Tab(const Tab&) = delete;
  Tab& operator=(const Tab&) = delete;

  bool LoadUrl(const std::string& text);
  void GoBack();
  void GoForward();
  void Reload();
  void SetNavigationStateCallback(NavigationStateCallback callback);
  void SetPageColorCallback(PageColorCallback callback);

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_TAB_H_

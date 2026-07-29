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

class DownloadManager;

class Tab {
 public:
  struct PageColor {
    double red = 1.0;
    double green = 1.0;
    double blue = 1.0;
    double alpha = 1.0;
  };

  using NavigationStateCallback =
      std::function<void(bool can_go_back, bool can_go_forward, const std::string& url,
                         const std::string& title)>;
  using PageColorCallback = std::function<void(PageColor color)>;

#ifdef __OBJC__
  Tab(WKWebsiteDataStore* website_data_store, DownloadManager& download_manager);
#endif
  ~Tab();

  Tab(const Tab&) = delete;
  Tab& operator=(const Tab&) = delete;

  bool LoadUrl(const std::string& text);
  std::string CurrentUrl() const;
  void Unload();
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

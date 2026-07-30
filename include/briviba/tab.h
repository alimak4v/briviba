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
                         const std::string& title, const std::string& favicon_url)>;
  using PageColorCallback = std::function<void(PageColor color)>;
  using OpenUrlInNewTabCallback = std::function<void(const std::string& url)>;

#ifdef __OBJC__
  Tab(WKWebsiteDataStore* website_data_store, DownloadManager& download_manager);
#endif
  ~Tab();

  Tab(const Tab&) = delete;
  Tab& operator=(const Tab&) = delete;

  bool LoadUrl(const std::string& text);
  void SetRestoredUrl(const std::string& url);
  std::string CurrentUrl() const;
  bool ShouldStayLoaded() const;
  void MarkPageActivity();
  void ResetPageActivity();
  void Unload();
  void GoBack();
  void GoForward();
  void Reload();
  void SetSearchEngine(const std::string& engine_id);
  void SetNavigationStateCallback(NavigationStateCallback callback);
  void SetPageColorCallback(PageColorCallback callback);
  void SetOpenUrlInNewTabCallback(OpenUrlInNewTabCallback callback);

#ifdef __OBJC__
  NSView* NativeView() const;
  NSView* LoadedNativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_TAB_H_

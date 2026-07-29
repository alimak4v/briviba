#ifndef BRIVIBA_TAB_MANAGER_H_
#define BRIVIBA_TAB_MANAGER_H_

#include <cstddef>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "briviba/tab.h"

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class CookieManager;
class DownloadManager;

class TabManager {
 public:
  enum class BrowsingMode { kNormal, kSecure };

  struct TabState {
    std::string url;
    std::string title;
    std::string favicon_url;
  };

  using NavigationStateCallback = Tab::NavigationStateCallback;
  using PageColorCallback = Tab::PageColorCallback;
  using TabStateCallback =
      std::function<void(const std::vector<TabState>& tabs, size_t active_index)>;

  TabManager(CookieManager& cookie_manager, DownloadManager& download_manager);
  ~TabManager();

  TabManager(const TabManager&) = delete;
  TabManager& operator=(const TabManager&) = delete;

  void CreateInitialTab();
  void CreateTab();
  void SelectTab(size_t index);
  void CloseTab(size_t index);
  bool LoadUrl(const std::string& text);
  std::string CurrentUrl() const;
  void GoBack();
  void GoForward();
  void Reload();
  void SetBrowsingMode(BrowsingMode mode);
  void SetNavigationStateCallback(NavigationStateCallback callback);
  void SetPageColorCallback(PageColorCallback callback);
  void SetTabStateCallback(TabStateCallback callback);

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_TAB_MANAGER_H_

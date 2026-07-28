#ifndef BRIVIBA_TAB_MANAGER_H_
#define BRIVIBA_TAB_MANAGER_H_

#include <memory>
#include <string>

#include "briviba/tab.h"

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class TabManager {
 public:
  using NavigationStateCallback = Tab::NavigationStateCallback;
  using PageColorCallback = Tab::PageColorCallback;

  TabManager();
  ~TabManager();

  TabManager(const TabManager&) = delete;
  TabManager& operator=(const TabManager&) = delete;

  void CreateInitialTab();
  void CreateTab();
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

#endif  // BRIVIBA_TAB_MANAGER_H_

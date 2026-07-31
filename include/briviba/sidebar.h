#ifndef BRIVIBA_SIDEBAR_H_
#define BRIVIBA_SIDEBAR_H_

#include <functional>
#include <memory>
#include <cstddef>
#include <string>
#include <vector>

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class Sidebar {
 public:
  enum class DockPosition { kLeft, kTop };

  struct TabState {
    std::string url;
    std::string title;
    std::string favicon_url;
  };

  using Action = std::function<void()>;
  using SelectTabAction = std::function<void(size_t index)>;
  using CloseTabAction = std::function<void(size_t index)>;
  using TabAction = std::function<void(size_t index)>;
  using OpenFilesAction = std::function<void(const std::vector<std::string>& file_urls)>;

  Sidebar();
  ~Sidebar();

  Sidebar(const Sidebar&) = delete;
  Sidebar& operator=(const Sidebar&) = delete;

  void SetNewTabAction(Action action);
  void SetOpenFilesAction(OpenFilesAction action);
  void SetSettingsAction(Action action);
  void SetSelectTabAction(SelectTabAction action);
  void SetCloseTabAction(CloseTabAction action);
  void SetBackTabAction(TabAction action);
  void SetForwardTabAction(TabAction action);
  void SetReloadTabAction(TabAction action);
  void SetTranslateVideoAction(Action action);
  void SetEditTabAddressAction(TabAction action);
  void SetClearTabCookiesAction(TabAction action);
  void SetClearTabCachesAction(TabAction action);
  void SetDockPosition(DockPosition position);
  void SetTabState(const std::vector<TabState>& tabs, size_t active_index);
  void SetFullscreenAppearance(bool fullscreen);
  void SetTranslateVideoVisible(bool visible);

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_SIDEBAR_H_

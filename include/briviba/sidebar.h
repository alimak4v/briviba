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
  struct TabState {
    std::string url;
    std::string title;
    std::string favicon_url;
  };

  using Action = std::function<void()>;
  using SelectTabAction = std::function<void(size_t index)>;
  using CloseTabAction = std::function<void(size_t index)>;
  using TabAction = std::function<void(size_t index)>;

  Sidebar();
  ~Sidebar();

  Sidebar(const Sidebar&) = delete;
  Sidebar& operator=(const Sidebar&) = delete;

  void SetNewTabAction(Action action);
  void SetSettingsAction(Action action);
  void SetSelectTabAction(SelectTabAction action);
  void SetCloseTabAction(CloseTabAction action);
  void SetReloadTabAction(TabAction action);
  void SetEditTabAddressAction(TabAction action);
  void SetTabState(const std::vector<TabState>& tabs, size_t active_index);
  void SetFullscreenAppearance(bool fullscreen);

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_SIDEBAR_H_

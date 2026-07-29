#ifndef BRIVIBA_SIDEBAR_H_
#define BRIVIBA_SIDEBAR_H_

#include <functional>
#include <memory>
#include <cstddef>

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class Sidebar {
 public:
  using Action = std::function<void()>;
  using SelectTabAction = std::function<void(size_t index)>;

  Sidebar();
  ~Sidebar();

  Sidebar(const Sidebar&) = delete;
  Sidebar& operator=(const Sidebar&) = delete;

  void SetNewTabAction(Action action);
  void SetSettingsAction(Action action);
  void SetSelectTabAction(SelectTabAction action);
  void SetTabState(size_t tab_count, size_t active_index);

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_SIDEBAR_H_

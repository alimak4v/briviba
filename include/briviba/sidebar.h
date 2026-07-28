#ifndef BRIVIBA_SIDEBAR_H_
#define BRIVIBA_SIDEBAR_H_

#include <functional>
#include <memory>

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class Sidebar {
 public:
  using Action = std::function<void()>;

  Sidebar();
  ~Sidebar();

  Sidebar(const Sidebar&) = delete;
  Sidebar& operator=(const Sidebar&) = delete;

  void SetNewTabAction(Action action);
  void SetSettingsAction(Action action);

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_SIDEBAR_H_

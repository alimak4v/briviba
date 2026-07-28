#ifndef BRIVIBA_TAB_H_
#define BRIVIBA_TAB_H_

#include <memory>

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class Tab {
 public:
  Tab();
  ~Tab();

  Tab(const Tab&) = delete;
  Tab& operator=(const Tab&) = delete;

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_TAB_H_

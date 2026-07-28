#ifndef BRIVIBA_TOOLBAR_H_
#define BRIVIBA_TOOLBAR_H_

#include <memory>

#ifdef __OBJC__
@class NSView;
#endif

namespace briviba {

class Toolbar {
 public:
  Toolbar();
  ~Toolbar();

  Toolbar(const Toolbar&) = delete;
  Toolbar& operator=(const Toolbar&) = delete;

#ifdef __OBJC__
  NSView* NativeView() const;
#endif

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace briviba

#endif  // BRIVIBA_TOOLBAR_H_

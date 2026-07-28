#include "briviba/tab.h"

#import <WebKit/WebKit.h>

namespace briviba {

class Tab::Impl {
 public:
  Impl() {
    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    web_view_ = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    [web_view_ setAllowsBackForwardNavigationGestures:YES];
    [web_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
  }

  NSView* NativeView() const { return web_view_; }

 private:
  WKWebView* web_view_ = nil;
};

Tab::Tab() : impl_(std::make_unique<Impl>()) {}

Tab::~Tab() = default;

NSView* Tab::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

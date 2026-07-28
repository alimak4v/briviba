#include "briviba/tab.h"

#import <WebKit/WebKit.h>

#include <cctype>
#include <cstdio>
#include <string>
#include <utility>

@interface BrivibaNavigationDelegate : NSObject <WKNavigationDelegate> {
 @public
  briviba::Tab::NavigationStateCallback navigation_state_callback;
  briviba::Tab::PageColorCallback page_color_callback;
}
- (void)emitNavigationStateForWebView:(WKWebView*)web_view;
- (void)emitPageColorForWebView:(WKWebView*)web_view;
@end

@implementation BrivibaNavigationDelegate

- (void)webView:(WKWebView*)webView didCommitNavigation:(WKNavigation*)navigation {
  (void)navigation;
  [self emitNavigationStateForWebView:webView];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
  (void)navigation;
  [self emitNavigationStateForWebView:webView];
  [self emitPageColorForWebView:webView];
}

- (void)emitNavigationStateForWebView:(WKWebView*)web_view {
  if (!navigation_state_callback) {
    return;
  }

  NSURL* url = [web_view URL];
  NSString* absolute_string = url == nil ? @"" : [url absoluteString];
  const char* utf8 = [absolute_string UTF8String];
  navigation_state_callback([web_view canGoBack], [web_view canGoForward],
                            utf8 == nullptr ? std::string() : std::string(utf8));
}

- (void)emitPageColorForWebView:(WKWebView*)web_view {
  if (!page_color_callback) {
    return;
  }

  NSString* script =
      @"(() => {"
       "const target = document.body || document.documentElement;"
       "const style = window.getComputedStyle(target);"
       "return style.backgroundColor || 'rgb(255, 255, 255)';"
       "})()";
  [web_view evaluateJavaScript:script
             completionHandler:^(id result, NSError* error) {
               if (error != nil || ![result isKindOfClass:[NSString class]]) {
                 return;
               }

               NSString* color_string = (NSString*)result;
               const char* utf8 = [color_string UTF8String];
               if (utf8 == nullptr) {
                 return;
               }

               int red = 255;
               int green = 255;
               int blue = 255;
               double alpha = 1.0;
               const int rgba_count =
                   std::sscanf(utf8, "rgba(%d, %d, %d, %lf)", &red, &green, &blue, &alpha);
               const int rgb_count = std::sscanf(utf8, "rgb(%d, %d, %d)", &red, &green, &blue);
               if (rgba_count < 3 && rgb_count != 3) {
                 return;
               }

               briviba::Tab::PageColor color;
               color.red = static_cast<double>(red) / 255.0;
               color.green = static_cast<double>(green) / 255.0;
               color.blue = static_cast<double>(blue) / 255.0;
               color.alpha = alpha;
               page_color_callback(color);
             }];
}

@end

namespace briviba {
namespace {

std::string TrimAsciiWhitespace(const std::string& text) {
  size_t begin = 0;
  while (begin < text.size() && std::isspace(static_cast<unsigned char>(text[begin])) != 0) {
    ++begin;
  }

  size_t end = text.size();
  while (end > begin && std::isspace(static_cast<unsigned char>(text[end - 1])) != 0) {
    --end;
  }

  return text.substr(begin, end - begin);
}

bool HasUrlScheme(const std::string& text) {
  for (const char character : text) {
    if (character == ':') {
      return true;
    }
    if (!std::isalpha(static_cast<unsigned char>(character)) &&
        !std::isdigit(static_cast<unsigned char>(character)) && character != '+' &&
        character != '-' && character != '.') {
      return false;
    }
  }
  return false;
}

}  // namespace

class Tab::Impl {
 public:
  Impl() {
    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    web_view_ = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    navigation_delegate_ = [[BrivibaNavigationDelegate alloc] init];
    [web_view_ setNavigationDelegate:navigation_delegate_];
    [web_view_ setAllowsBackForwardNavigationGestures:YES];
    [web_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
  }

  bool LoadUrl(const std::string& text) {
    std::string trimmed = TrimAsciiWhitespace(text);
    if (trimmed.empty()) {
      return false;
    }

    const std::string url_text = HasUrlScheme(trimmed) ? trimmed : "https://" + trimmed;
    NSString* url_string = [NSString stringWithUTF8String:url_text.c_str()];
    NSURL* url = [NSURL URLWithString:url_string];
    if (url == nil || [url scheme] == nil) {
      return false;
    }

    [web_view_ loadRequest:[NSURLRequest requestWithURL:url]];
    EmitNavigationState();
    return true;
  }

  void GoBack() {
    if ([web_view_ canGoBack]) {
      [web_view_ goBack];
    }
    EmitNavigationState();
  }

  void GoForward() {
    if ([web_view_ canGoForward]) {
      [web_view_ goForward];
    }
    EmitNavigationState();
  }

  void Reload() {
    [web_view_ reload];
    EmitNavigationState();
  }

  void SetNavigationStateCallback(NavigationStateCallback callback) {
    navigation_delegate_->navigation_state_callback = std::move(callback);
    EmitNavigationState();
  }

  void SetPageColorCallback(PageColorCallback callback) {
    navigation_delegate_->page_color_callback = std::move(callback);
  }

  NSView* NativeView() const { return web_view_; }

 private:
  void EmitNavigationState() { [navigation_delegate_ emitNavigationStateForWebView:web_view_]; }

  BrivibaNavigationDelegate* navigation_delegate_ = nil;
  WKWebView* web_view_ = nil;
};

Tab::Tab() : impl_(std::make_unique<Impl>()) {}

Tab::~Tab() = default;

bool Tab::LoadUrl(const std::string& text) {
  return impl_->LoadUrl(text);
}

void Tab::GoBack() {
  impl_->GoBack();
}

void Tab::GoForward() {
  impl_->GoForward();
}

void Tab::Reload() {
  impl_->Reload();
}

void Tab::SetNavigationStateCallback(NavigationStateCallback callback) {
  impl_->SetNavigationStateCallback(std::move(callback));
}

void Tab::SetPageColorCallback(PageColorCallback callback) {
  impl_->SetPageColorCallback(std::move(callback));
}

NSView* Tab::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

#include "briviba/tab.h"

#include "briviba/download_manager.h"

#import <WebKit/WebKit.h>

#include <cctype>
#include <cstdio>
#include <string>
#include <utility>

@interface BrivibaNavigationDelegate : NSObject <WKNavigationDelegate> {
 @public
  briviba::Tab::NavigationStateCallback navigation_state_callback;
  briviba::Tab::PageColorCallback page_color_callback;
  briviba::Tab::NavigationRetargetCallback navigation_retarget_callback;
  briviba::DownloadManager* download_manager;
}
- (void)emitNavigationStateForWebView:(WKWebView*)web_view;
- (void)emitFaviconNavigationStateForWebView:(WKWebView*)web_view;
- (void)emitPageColorForWebView:(WKWebView*)web_view;
@end

@implementation BrivibaNavigationDelegate

- (void)webView:(WKWebView*)webView
    decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  (void)webView;
  WKFrameInfo* target_frame = [navigationAction targetFrame];
  if (navigation_retarget_callback && (target_frame == nil || [target_frame isMainFrame])) {
    NSURL* url = [[navigationAction request] URL];
    NSString* absolute_string = url == nil ? @"" : [url absoluteString];
    const char* utf8 = [absolute_string UTF8String];
    if (utf8 != nullptr && navigation_retarget_callback(std::string(utf8))) {
      decisionHandler(WKNavigationActionPolicyCancel);
      return;
    }
  }
  decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView*)webView didCommitNavigation:(WKNavigation*)navigation {
  (void)navigation;
  [self emitNavigationStateForWebView:webView];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
  (void)navigation;
  [self emitNavigationStateForWebView:webView];
  [self emitFaviconNavigationStateForWebView:webView];
  [self emitPageColorForWebView:webView];
}

- (void)webView:(WKWebView*)webView
    navigationAction:(WKNavigationAction*)navigationAction
    didBecomeDownload:(WKDownload*)download {
  (void)webView;
  (void)navigationAction;
  if (download_manager != nullptr) {
    download_manager->ManageDownload(download);
  }
}

- (void)webView:(WKWebView*)webView
    navigationResponse:(WKNavigationResponse*)navigationResponse
     didBecomeDownload:(WKDownload*)download {
  (void)webView;
  (void)navigationResponse;
  if (download_manager != nullptr) {
    download_manager->ManageDownload(download);
  }
}

- (void)emitNavigationStateForWebView:(WKWebView*)web_view {
  if (!navigation_state_callback) {
    return;
  }

  NSURL* url = [web_view URL];
  NSString* absolute_string = url == nil ? @"" : [url absoluteString];
  NSString* title = [web_view title] == nil ? @"" : [web_view title];
  const char* utf8 = [absolute_string UTF8String];
  const char* title_utf8 = [title UTF8String];
  navigation_state_callback([web_view canGoBack], [web_view canGoForward],
                            utf8 == nullptr ? std::string() : std::string(utf8),
                            title_utf8 == nullptr ? std::string() : std::string(title_utf8),
                            std::string());
}

- (void)emitFaviconNavigationStateForWebView:(WKWebView*)web_view {
  if (!navigation_state_callback) {
    return;
  }

  NSString* script =
      @"(() => {"
       "const links = Array.from(document.querySelectorAll('link[rel]'));"
       "const icon = links.find((link) => /(^|\\s)(icon|shortcut icon|apple-touch-icon)(\\s|$)/i"
       ".test(link.rel) && link.href);"
       "return icon ? new URL(icon.href, location.href).href : '';"
       "})()";
  [web_view evaluateJavaScript:script
             completionHandler:^(id result, NSError* error) {
               if (error != nil || ![result isKindOfClass:[NSString class]]) {
                 return;
               }

               NSURL* url = [web_view URL];
               NSString* absolute_string = url == nil ? @"" : [url absoluteString];
               NSString* title = [web_view title] == nil ? @"" : [web_view title];
               NSString* favicon_url = (NSString*)result;
               const char* utf8 = [absolute_string UTF8String];
               const char* title_utf8 = [title UTF8String];
               const char* favicon_utf8 = [favicon_url UTF8String];
               navigation_state_callback(
                   [web_view canGoBack], [web_view canGoForward],
                   utf8 == nullptr ? std::string() : std::string(utf8),
                   title_utf8 == nullptr ? std::string() : std::string(title_utf8),
                   favicon_utf8 == nullptr ? std::string() : std::string(favicon_utf8));
             }];
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

bool LooksLikeSearchQuery(const std::string& text) {
  for (const char character : text) {
    if (std::isspace(static_cast<unsigned char>(character)) != 0) {
      return true;
    }
  }
  return text.find('.') == std::string::npos && !HasUrlScheme(text);
}

NSString* SearchUrlFormat(const std::string& engine_id) {
  if (engine_id == "google") {
    return @"https://www.google.com/search?q=%@";
  }
  if (engine_id == "bing") {
    return @"https://www.bing.com/search?q=%@";
  }
  if (engine_id == "yandex") {
    return @"https://yandex.ru/search/?text=%@";
  }
  return @"https://duckduckgo.com/?q=%@";
}

std::string UrlTextFromInput(const std::string& input, const std::string& search_engine_id) {
  if (!LooksLikeSearchQuery(input)) {
    return HasUrlScheme(input) ? input : "https://" + input;
  }

  NSString* query = [NSString stringWithUTF8String:input.c_str()];
  NSString* encoded_query =
      [query stringByAddingPercentEncodingWithAllowedCharacters:
                 [NSCharacterSet URLQueryAllowedCharacterSet]];
  NSString* url = [NSString stringWithFormat:SearchUrlFormat(search_engine_id), encoded_query];
  const char* utf8 = [url UTF8String];
  return utf8 == nullptr ? std::string("https://duckduckgo.com") : std::string(utf8);
}

NSString* SafariLikeUserAgent() {
  return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "KHTML, like Gecko) Version/18.0 Safari/605.1.15";
}

void ConfigureWebView(WKWebViewConfiguration* configuration) {
  if (@available(macOS 12.3, *)) {
    [[configuration preferences] setElementFullscreenEnabled:YES];
  }
  [configuration setMediaTypesRequiringUserActionForPlayback:WKAudiovisualMediaTypeNone];
}

}  // namespace

class Tab::Impl {
 public:
  Impl(WKWebsiteDataStore* website_data_store, DownloadManager& download_manager)
      : website_data_store_(website_data_store), download_manager_(download_manager) {}

  bool LoadUrl(const std::string& text) {
    EnsureLoaded();
    std::string trimmed = TrimAsciiWhitespace(text);
    if (trimmed.empty()) {
      return false;
    }

    const std::string url_text = UrlTextFromInput(trimmed, search_engine_id_);
    NSString* url_string = [NSString stringWithUTF8String:url_text.c_str()];
    NSURL* url = [NSURL URLWithString:url_string];
    if (url == nil || [url scheme] == nil) {
      return false;
    }

    current_url_ = url_text;
    if ([url isFileURL]) {
      NSURL* read_access_url = [url URLByDeletingLastPathComponent];
      [web_view_ loadFileURL:url allowingReadAccessToURL:read_access_url];
      EmitNavigationState();
      return true;
    }
    [web_view_ loadRequest:[NSURLRequest requestWithURL:url]];
    EmitNavigationState();
    return true;
  }

  void SetRestoredUrl(const std::string& url) {
    current_url_ = url;
    if (web_view_ != nil && !current_url_.empty()) {
      NSString* url_string = [NSString stringWithUTF8String:current_url_.c_str()];
      NSURL* ns_url = [NSURL URLWithString:url_string];
      if (ns_url != nil) {
        [web_view_ loadRequest:[NSURLRequest requestWithURL:ns_url]];
      }
    }
  }

  std::string CurrentUrl() const {
    if (web_view_ == nil) {
      return current_url_;
    }
    NSURL* url = [web_view_ URL];
    NSString* absolute_string = url == nil ? @"" : [url absoluteString];
    const char* utf8 = [absolute_string UTF8String];
    return utf8 == nullptr ? std::string() : std::string(utf8);
  }

  void Unload() {
    current_url_ = CurrentUrl();
    [web_view_ setNavigationDelegate:nil];
    [web_view_ removeFromSuperview];
    navigation_delegate_ = nil;
    web_view_ = nil;
  }

  void GoBack() {
    EnsureLoaded();
    if ([web_view_ canGoBack]) {
      [web_view_ goBack];
    }
    EmitNavigationState();
  }

  void GoForward() {
    EnsureLoaded();
    if ([web_view_ canGoForward]) {
      [web_view_ goForward];
    }
    EmitNavigationState();
  }

  void Reload() {
    EnsureLoaded();
    [web_view_ reload];
    EmitNavigationState();
  }

  void SetSearchEngine(const std::string& engine_id) { search_engine_id_ = engine_id; }

  void SetNavigationStateCallback(NavigationStateCallback callback) {
    navigation_state_callback_ = std::move(callback);
    if (navigation_delegate_ != nil) {
      navigation_delegate_->navigation_state_callback = navigation_state_callback_;
    }
    EmitNavigationState();
  }

  void SetPageColorCallback(PageColorCallback callback) {
    page_color_callback_ = std::move(callback);
    if (navigation_delegate_ != nil) {
      navigation_delegate_->page_color_callback = page_color_callback_;
    }
  }

  void SetNavigationRetargetCallback(NavigationRetargetCallback callback) {
    navigation_retarget_callback_ = std::move(callback);
    if (navigation_delegate_ != nil) {
      navigation_delegate_->navigation_retarget_callback = navigation_retarget_callback_;
    }
  }

  NSView* NativeView() {
    EnsureLoaded();
    return web_view_;
  }

  NSView* LoadedNativeView() const { return web_view_; }

 private:
  void EnsureLoaded() {
    if (web_view_ != nil) {
      return;
    }

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    ConfigureWebView(configuration);
    if (website_data_store_ != nil) {
      [configuration setWebsiteDataStore:website_data_store_];
    }
    web_view_ = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    [web_view_ setCustomUserAgent:SafariLikeUserAgent()];
    navigation_delegate_ = [[BrivibaNavigationDelegate alloc] init];
    navigation_delegate_->download_manager = &download_manager_;
    navigation_delegate_->navigation_state_callback = navigation_state_callback_;
    navigation_delegate_->page_color_callback = page_color_callback_;
    navigation_delegate_->navigation_retarget_callback = navigation_retarget_callback_;
    [web_view_ setNavigationDelegate:navigation_delegate_];
    [web_view_ setAllowsBackForwardNavigationGestures:YES];
    [web_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    if (!current_url_.empty()) {
      NSString* url_string = [NSString stringWithUTF8String:current_url_.c_str()];
      NSURL* url = [NSURL URLWithString:url_string];
      if (url != nil) {
        if ([url isFileURL]) {
          [web_view_ loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
        } else {
          [web_view_ loadRequest:[NSURLRequest requestWithURL:url]];
        }
      }
    }
  }

  void EmitNavigationState() {
    if (navigation_delegate_ != nil && web_view_ != nil) {
      [navigation_delegate_ emitNavigationStateForWebView:web_view_];
    }
  }

  WKWebsiteDataStore* website_data_store_ = nil;
  DownloadManager& download_manager_;
  NavigationStateCallback navigation_state_callback_;
  PageColorCallback page_color_callback_;
  NavigationRetargetCallback navigation_retarget_callback_;
  std::string search_engine_id_ = "duckduckgo";
  std::string current_url_;
  BrivibaNavigationDelegate* navigation_delegate_ = nil;
  WKWebView* web_view_ = nil;
};

Tab::Tab(WKWebsiteDataStore* website_data_store, DownloadManager& download_manager)
    : impl_(std::make_unique<Impl>(website_data_store, download_manager)) {}

Tab::~Tab() = default;

bool Tab::LoadUrl(const std::string& text) {
  return impl_->LoadUrl(text);
}

void Tab::SetRestoredUrl(const std::string& url) {
  impl_->SetRestoredUrl(url);
}

std::string Tab::CurrentUrl() const {
  return impl_->CurrentUrl();
}

void Tab::Unload() {
  impl_->Unload();
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

void Tab::SetSearchEngine(const std::string& engine_id) {
  impl_->SetSearchEngine(engine_id);
}

void Tab::SetNavigationStateCallback(NavigationStateCallback callback) {
  impl_->SetNavigationStateCallback(std::move(callback));
}

void Tab::SetPageColorCallback(PageColorCallback callback) {
  impl_->SetPageColorCallback(std::move(callback));
}

void Tab::SetNavigationRetargetCallback(NavigationRetargetCallback callback) {
  impl_->SetNavigationRetargetCallback(std::move(callback));
}

NSView* Tab::NativeView() const {
  return const_cast<Impl*>(impl_.get())->NativeView();
}

NSView* Tab::LoadedNativeView() const {
  return impl_->LoadedNativeView();
}

}  // namespace briviba

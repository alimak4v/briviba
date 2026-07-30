#include "briviba/tab.h"

#include "briviba/download_manager.h"

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include <chrono>
#include <cctype>
#include <cstdio>
#include <string>
#include <utility>

@interface BrivibaWebView : WKWebView
@end

@implementation BrivibaWebView

- (NSMenu*)menuForEvent:(NSEvent*)event {
  NSMenu* default_menu = [super menuForEvent:event];
  if (default_menu == nil) {
    return nil;
  }

  BOOL link_menu = NO;
  for (NSMenuItem* item in [default_menu itemArray]) {
    if ([[item title] isEqualToString:@"Open Link"]) {
      link_menu = YES;
      break;
    }
  }
  if (!link_menu) {
    return default_menu;
  }

  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Link"];
  for (NSMenuItem* item in [default_menu itemArray]) {
    NSString* title = [item title];
    BOOL keep = [title isEqualToString:@"Open Link"] ||
                [title isEqualToString:@"Open Link in New Window"] ||
                [title isEqualToString:@"Copy Link"] ||
                [title hasPrefix:@"Share"];
    if (!keep) {
      continue;
    }

    NSMenuItem* copied_item = [item copy];
    if ([title isEqualToString:@"Open Link in New Window"]) {
      [copied_item setTitle:@"Open Link in New Tab"];
    }
    [menu addItem:copied_item];
  }
  return [menu numberOfItems] == 0 ? default_menu : menu;
}

@end

@interface BrivibaNavigationDelegate : NSObject <WKNavigationDelegate, WKUIDelegate> {
 @public
  briviba::Tab* tab;
  briviba::Tab::NavigationStateCallback navigation_state_callback;
  briviba::Tab::PageColorCallback page_color_callback;
  briviba::Tab::OpenUrlInNewTabCallback open_url_in_new_tab_callback;
  briviba::DownloadManager* download_manager;
}
- (void)emitNavigationStateForWebView:(WKWebView*)web_view;
- (void)emitFaviconNavigationStateForWebView:(WKWebView*)web_view;
- (void)emitPageColorForWebView:(WKWebView*)web_view;
@end

@implementation BrivibaNavigationDelegate

- (WKWebView*)webView:(WKWebView*)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration*)configuration
               forNavigationAction:(WKNavigationAction*)navigationAction
                     windowFeatures:(WKWindowFeatures*)windowFeatures {
  (void)webView;
  (void)configuration;
  (void)windowFeatures;
  if (!open_url_in_new_tab_callback) {
    return nil;
  }

  NSURL* url = [[navigationAction request] URL];
  NSString* absolute_string = url == nil ? @"" : [url absoluteString];
  const char* utf8 = [absolute_string UTF8String];
  if (utf8 != nullptr && std::string(utf8).size() > 0) {
    open_url_in_new_tab_callback(std::string(utf8));
  }
  return nil;
}

- (void)webView:(WKWebView*)webView didCommitNavigation:(WKNavigation*)navigation {
  (void)navigation;
  if (tab != nullptr) {
    tab->ResetPageActivity();
  }
  [self emitNavigationStateForWebView:webView];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
  (void)navigation;
  if (tab != nullptr) {
    tab->ResetPageActivity();
  }
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

@interface BrivibaActivityHandler : NSObject <WKScriptMessageHandler> {
 @public
  briviba::Tab* tab;
}
@end

@implementation BrivibaActivityHandler

- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
  (void)userContentController;
  (void)message;
  if (tab != nullptr) {
    tab->MarkPageActivity();
  }
}

@end

namespace briviba {
namespace {

constexpr std::chrono::seconds kRecentActivityWindow(180);

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

double MonotonicSeconds() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

NSString* PageActivityScriptSource() {
  return
      @"(() => {"
       "if (window.__brivibaActivityInstalled) return;"
       "window.__brivibaActivityInstalled = true;"
       "let lastPost = 0;"
       "let mutationCount = 0;"
       "let animationFrameCount = 0;"
       "const post = (kind) => {"
       "  const now = Date.now();"
       "  if (now - lastPost < 2000) return;"
       "  lastPost = now;"
       "  try { window.webkit.messageHandlers.brivibaActivity.postMessage(kind); } catch (_) {}"
       "};"
       "const mediaActive = () => {"
       "  try {"
       "    return Array.from(document.querySelectorAll('audio,video')).some((element) =>"
       "      !element.paused && !element.ended && element.readyState > 1);"
       "  } catch (_) { return false; }"
       "};"
       "document.addEventListener('play', () => post('media'), true);"
       "document.addEventListener('playing', () => post('media'), true);"
       "document.addEventListener('timeupdate', () => { if (mediaActive()) post('media'); }, true);"
       "setInterval(() => { if (mediaActive()) post('media'); }, 5000);"
       "try {"
       "  const observer = new MutationObserver((mutations) => { mutationCount += mutations.length; });"
       "  const startObserver = () => observer.observe(document.documentElement || document, {"
       "    childList: true, subtree: true, characterData: true, attributes: true"
       "  });"
       "  if (document.documentElement) startObserver();"
       "  else document.addEventListener('DOMContentLoaded', startObserver, { once: true });"
       "  setInterval(() => {"
       "    if (mutationCount >= 80) post('page-update');"
       "    mutationCount = 0;"
       "  }, 5000);"
       "} catch (_) {}"
       "try {"
       "  const nativeRequestAnimationFrame = window.requestAnimationFrame;"
       "  if (nativeRequestAnimationFrame && !nativeRequestAnimationFrame.__brivibaWrapped) {"
       "    const wrappedRequestAnimationFrame = function(callback) {"
       "      animationFrameCount += 1;"
       "      return nativeRequestAnimationFrame.call(window, callback);"
       "    };"
       "    wrappedRequestAnimationFrame.__brivibaWrapped = true;"
       "    window.requestAnimationFrame = wrappedRequestAnimationFrame;"
       "    setInterval(() => {"
       "      if (animationFrameCount >= 90 && document.querySelector('canvas')) post('animation');"
       "      animationFrameCount = 0;"
       "    }, 5000);"
       "  }"
       "} catch (_) {}"
       "try {"
       "  const NativeWebSocket = window.WebSocket;"
       "  if (NativeWebSocket && !NativeWebSocket.__brivibaWrapped) {"
       "    const WrappedWebSocket = function(...args) {"
       "      const socket = new NativeWebSocket(...args);"
       "      socket.addEventListener('message', () => post('websocket'));"
       "      return socket;"
       "    };"
       "    Object.setPrototypeOf(WrappedWebSocket, NativeWebSocket);"
       "    WrappedWebSocket.prototype = NativeWebSocket.prototype;"
       "    WrappedWebSocket.__brivibaWrapped = true;"
       "    window.WebSocket = WrappedWebSocket;"
       "  }"
       "} catch (_) {}"
       "})();";
}

}  // namespace

class Tab::Impl {
 public:
  Impl(Tab* owner, WKWebsiteDataStore* website_data_store, DownloadManager& download_manager)
      : owner_(owner), website_data_store_(website_data_store), download_manager_(download_manager) {}

  ~Impl() { DetachActivityHandler(); }

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

  bool ShouldStayLoaded() const {
    if (web_view_ == nil) {
      return false;
    }
    if ([web_view_ isLoading]) {
      return true;
    }
    return MonotonicSeconds() - last_page_activity_seconds_ <= kRecentActivityWindow.count();
  }

  void MarkPageActivity() { last_page_activity_seconds_ = MonotonicSeconds(); }

  void ResetPageActivity() { last_page_activity_seconds_ = 0.0; }

  void Unload() {
    current_url_ = CurrentUrl();
    [web_view_ setNavigationDelegate:nil];
    [web_view_ setUIDelegate:nil];
    if (navigation_delegate_ != nil) {
      navigation_delegate_->tab = nullptr;
    }
    DetachActivityHandler();
    [web_view_ removeFromSuperview];
    navigation_delegate_ = nil;
    web_view_ = nil;
  }

  void ExitFullscreen() {
    if (web_view_ == nil) {
      return;
    }

    NSString* script =
        @"(() => {"
         "try {"
         "  const doc = document;"
         "  const exitDocFullscreen = doc.exitFullscreen || doc.webkitExitFullscreen;"
         "  if (doc.fullscreenElement && exitDocFullscreen) exitDocFullscreen.call(doc);"
         "  if (doc.webkitFullscreenElement && exitDocFullscreen) exitDocFullscreen.call(doc);"
         "  for (const video of Array.from(doc.querySelectorAll('video'))) {"
         "    try {"
         "      if (video.webkitPresentationMode === 'fullscreen' && video.webkitExitFullscreen) {"
         "        video.webkitExitFullscreen();"
         "      }"
         "      if (video.webkitDisplayingFullscreen && video.webkitExitFullscreen) {"
         "        video.webkitExitFullscreen();"
         "      }"
         "    } catch (_) {}"
         "  }"
         "} catch (_) {}"
         "})();";
    [web_view_ evaluateJavaScript:script completionHandler:nil];
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

  void SetOpenUrlInNewTabCallback(OpenUrlInNewTabCallback callback) {
    open_url_in_new_tab_callback_ = std::move(callback);
    if (navigation_delegate_ != nil) {
      navigation_delegate_->open_url_in_new_tab_callback = open_url_in_new_tab_callback_;
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
    WKUserContentController* user_content_controller = [[WKUserContentController alloc] init];
    WKUserScript* activity_script =
        [[WKUserScript alloc] initWithSource:PageActivityScriptSource()
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
    [user_content_controller addUserScript:activity_script];
    activity_handler_ = [[BrivibaActivityHandler alloc] init];
    activity_handler_->tab = owner_;
    [user_content_controller addScriptMessageHandler:activity_handler_ name:@"brivibaActivity"];
    [configuration setUserContentController:user_content_controller];
    if (website_data_store_ != nil) {
      [configuration setWebsiteDataStore:website_data_store_];
    }
    web_view_ = [[BrivibaWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    [web_view_ setCustomUserAgent:SafariLikeUserAgent()];
    navigation_delegate_ = [[BrivibaNavigationDelegate alloc] init];
    navigation_delegate_->tab = owner_;
    navigation_delegate_->download_manager = &download_manager_;
    navigation_delegate_->navigation_state_callback = navigation_state_callback_;
    navigation_delegate_->page_color_callback = page_color_callback_;
    navigation_delegate_->open_url_in_new_tab_callback = open_url_in_new_tab_callback_;
    [web_view_ setNavigationDelegate:navigation_delegate_];
    [web_view_ setUIDelegate:navigation_delegate_];
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

  void DetachActivityHandler() {
    if (web_view_ != nil && activity_handler_ != nil) {
      [[web_view_ configuration].userContentController removeScriptMessageHandlerForName:@"brivibaActivity"];
      activity_handler_->tab = nullptr;
      activity_handler_ = nil;
    }
  }

  Tab* owner_;
  WKWebsiteDataStore* website_data_store_ = nil;
  DownloadManager& download_manager_;
  NavigationStateCallback navigation_state_callback_;
  PageColorCallback page_color_callback_;
  OpenUrlInNewTabCallback open_url_in_new_tab_callback_;
  std::string search_engine_id_ = "duckduckgo";
  std::string current_url_;
  BrivibaNavigationDelegate* navigation_delegate_ = nil;
  BrivibaActivityHandler* activity_handler_ = nil;
  WKWebView* web_view_ = nil;
  double last_page_activity_seconds_ = 0.0;
};

Tab::Tab(WKWebsiteDataStore* website_data_store, DownloadManager& download_manager)
    : impl_(std::make_unique<Impl>(this, website_data_store, download_manager)) {}

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

bool Tab::ShouldStayLoaded() const {
  return impl_->ShouldStayLoaded();
}

void Tab::MarkPageActivity() {
  impl_->MarkPageActivity();
}

void Tab::ResetPageActivity() {
  impl_->ResetPageActivity();
}

void Tab::Unload() {
  impl_->Unload();
}

void Tab::ExitFullscreen() {
  impl_->ExitFullscreen();
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

void Tab::SetOpenUrlInNewTabCallback(OpenUrlInNewTabCallback callback) {
  impl_->SetOpenUrlInNewTabCallback(std::move(callback));
}

NSView* Tab::NativeView() const {
  return const_cast<Impl*>(impl_.get())->NativeView();
}

NSView* Tab::LoadedNativeView() const {
  return impl_->LoadedNativeView();
}

}  // namespace briviba

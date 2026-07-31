#include "briviba/browser_window.h"

#include "briviba/bookmark_manager.h"
#include "briviba/cookie_manager.h"
#include "briviba/download_manager.h"
#include "briviba/history_manager.h"
#include "briviba/settings_manager.h"
#include "briviba/sidebar.h"
#include "briviba/tab_manager.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>
#include <functional>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

@interface BrivibaWindowControlBridge : NSObject <NSWindowDelegate> {
 @public
  std::function<void()> close_action;
  std::function<void()> minimize_action;
  std::function<void()> fullscreen_action;
  std::function<void()> fullscreen_enter_action;
  std::function<void()> fullscreen_exit_action;
  std::function<void()> window_will_close_action;
}
- (void)closeWindow:(id)sender;
- (void)minimizeWindow:(id)sender;
- (void)toggleFullscreen:(id)sender;
@end

@implementation BrivibaWindowControlBridge

- (void)closeWindow:(id)sender {
  (void)sender;
  if (close_action) {
    close_action();
  }
}

- (void)minimizeWindow:(id)sender {
  (void)sender;
  if (minimize_action) {
    minimize_action();
  }
}

- (void)toggleFullscreen:(id)sender {
  (void)sender;
  if (fullscreen_action) {
    fullscreen_action();
  }
}

- (void)windowWillEnterFullScreen:(NSNotification*)notification {
  (void)notification;
  if (fullscreen_enter_action) {
    fullscreen_enter_action();
  }
}

- (void)windowDidExitFullScreen:(NSNotification*)notification {
  (void)notification;
  if (fullscreen_exit_action) {
    fullscreen_exit_action();
  }
}

- (void)windowWillClose:(NSNotification*)notification {
  (void)notification;
  if (window_will_close_action) {
    window_will_close_action();
  }
}

@end

@interface BrivibaSettingsBridge : NSObject <NSWindowDelegate> {
 @public
  std::function<void(bool)> set_start_secure_action;
  std::function<void(const std::string&)> set_search_engine_action;
  std::function<void(briviba::SettingsManager::SidebarDockPosition)> set_tab_dock_position_action;
  std::function<void()> clear_all_cookies_action;
  std::function<void()> clear_all_caches_action;
  std::function<void()> show_cookies_action;
  std::function<void()> settings_closed_action;
}
- (void)toggleStartSecure:(id)sender;
- (void)changeSearchEngine:(id)sender;
- (void)changeTabDockPosition:(id)sender;
- (void)clearAllCookies:(id)sender;
- (void)clearAllCaches:(id)sender;
- (void)showCookies:(id)sender;
@end

@implementation BrivibaSettingsBridge

- (void)toggleStartSecure:(id)sender {
  if (!set_start_secure_action || ![sender respondsToSelector:@selector(state)]) {
    return;
  }
  set_start_secure_action([sender state] == NSControlStateValueOn);
}

- (void)changeSearchEngine:(id)sender {
  if (!set_search_engine_action || ![sender respondsToSelector:@selector(selectedItem)]) {
    return;
  }

  NSMenuItem* selected_item = [sender selectedItem];
  id represented_object = [selected_item representedObject];
  if (![represented_object isKindOfClass:[NSString class]]) {
    return;
  }
  const char* utf8 = [(NSString*)represented_object UTF8String];
  set_search_engine_action(utf8 == nullptr ? std::string() : std::string(utf8));
}

- (void)changeTabDockPosition:(id)sender {
  if (!set_tab_dock_position_action || ![sender respondsToSelector:@selector(selectedSegment)]) {
    return;
  }

  NSInteger selected_segment = [sender selectedSegment];
  set_tab_dock_position_action(selected_segment == 1
                                   ? briviba::SettingsManager::SidebarDockPosition::kTop
                                   : briviba::SettingsManager::SidebarDockPosition::kLeft);
}

- (void)clearAllCookies:(id)sender {
  (void)sender;
  if (clear_all_cookies_action) {
    clear_all_cookies_action();
  }
}

- (void)clearAllCaches:(id)sender {
  (void)sender;
  if (clear_all_caches_action) {
    clear_all_caches_action();
  }
}

- (void)showCookies:(id)sender {
  (void)sender;
  if (show_cookies_action) {
    show_cookies_action();
  }
}

- (void)windowWillClose:(NSNotification*)notification {
  (void)notification;
  if (settings_closed_action) {
    settings_closed_action();
  }
}

@end

namespace briviba {
namespace {

constexpr CGFloat kInitialWidth = 1180.0;
constexpr CGFloat kInitialHeight = 760.0;
constexpr CGFloat kVisibleFrameScale = 0.88;
constexpr CGFloat kSidebarLeading = 0.0;
constexpr CGFloat kSidebarTop = 0.0;
constexpr CGFloat kSidebarBottom = 0.0;
constexpr CGFloat kWebViewLeading = 96.0;
constexpr CGFloat kWebViewTop = 0.0;
constexpr CGFloat kWebViewTrailing = 0.0;
constexpr CGFloat kWebViewBottom = 0.0;
constexpr CGFloat kTopDockHeight = 72.0;
constexpr CGFloat kFullscreenSidebarTop = -kWebViewTop;
constexpr double kColorEpsilon = 0.002;

NSRect InitialWindowFrame() {
  NSScreen* screen = [NSScreen mainScreen];
  const NSRect visible_frame = screen == nil ? NSMakeRect(0.0, 0.0, 1280.0, 800.0)
                                             : [screen visibleFrame];
  const CGFloat width = std::min(kInitialWidth, visible_frame.size.width * kVisibleFrameScale);
  const CGFloat height = std::min(kInitialHeight, visible_frame.size.height * kVisibleFrameScale);
  const CGFloat x = visible_frame.origin.x + (visible_frame.size.width - width) / 2.0;
  const CGFloat y = visible_frame.origin.y + (visible_frame.size.height - height) / 2.0;
  return NSMakeRect(x, y, width, height);
}

NSWindowStyleMask WindowStyleMask() {
  return NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
         NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
}

NSButton* TrafficLightButton(NSColor* color, NSString* accessibility_label, SEL action,
                             id target) {
  NSButton* button = [NSButton buttonWithTitle:@"" target:target action:action];
  [button setBordered:NO];
  [button setBezelStyle:NSBezelStyleRegularSquare];
  [button setFocusRingType:NSFocusRingTypeNone];
  [button setAccessibilityLabel:accessibility_label];
  [button setTranslatesAutoresizingMaskIntoConstraints:NO];
  [button setWantsLayer:YES];
  [[button layer] setCornerRadius:6.0];
  [[button layer] setBackgroundColor:[color CGColor]];
  [[button layer] setBorderColor:[[NSColor colorWithWhite:0.0 alpha:0.10] CGColor]];
  [[button layer] setBorderWidth:0.5];
  [[button widthAnchor] constraintEqualToConstant:12.0].active = YES;
  [[button heightAnchor] constraintEqualToConstant:12.0].active = YES;
  return button;
}

NSStackView* TrafficLightStack(id target) {
  NSStackView* stack = [[NSStackView alloc] init];
  [stack setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
  [stack setAlignment:NSLayoutAttributeCenterY];
  [stack setDistribution:NSStackViewDistributionGravityAreas];
  [stack setSpacing:10.0];
  [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
  [stack addArrangedSubview:TrafficLightButton(
                                [NSColor colorWithSRGBRed:1.0 green:0.34 blue:0.32 alpha:1.0],
                                @"Close window", @selector(closeWindow:), target)];
  [stack addArrangedSubview:TrafficLightButton(
                                [NSColor colorWithSRGBRed:1.0 green:0.78 blue:0.16 alpha:1.0],
                                @"Minimize window", @selector(minimizeWindow:), target)];
  [stack addArrangedSubview:TrafficLightButton(
                                [NSColor colorWithSRGBRed:0.20 green:0.78 blue:0.35 alpha:1.0],
                                @"Fullscreen window", @selector(toggleFullscreen:), target)];
  return stack;
}

std::string StringFromNSString(NSString* value) {
  const char* utf8 = [value UTF8String];
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

std::string SearchEngineHomeUrl(const std::string& engine_id) {
  if (engine_id == "google") {
    return "https://www.google.com";
  }
  if (engine_id == "bing") {
    return "https://www.bing.com";
  }
  if (engine_id == "yandex") {
    return "https://yandex.ru";
  }
  return "https://duckduckgo.com";
}

std::string HostFromUrl(const std::string& url) {
  NSString* url_string = [NSString stringWithUTF8String:url.c_str()];
  NSURL* parsed_url = [NSURL URLWithString:url_string];
  NSString* host = [[parsed_url host] lowercaseString];
  return host == nil ? std::string() : StringFromNSString(host);
}

bool ShouldShowVideoTranslateButton(const std::string& url) {
  NSString* url_string = [NSString stringWithUTF8String:url.c_str()];
  NSURL* parsed_url = [NSURL URLWithString:url_string];
  NSString* host = [[parsed_url host] lowercaseString];
  NSString* path = [[parsed_url path] lowercaseString];
  if (host == nil) {
    return false;
  }
  const std::string host_text = StringFromNSString(host);
  const bool supported_host = host_text.ends_with("youtube.com") ||
                             host_text.ends_with("youtu.be") ||
                             host_text.ends_with("vimeo.com") ||
                             host_text.ends_with("vk.com") ||
                             host_text.ends_with("vkvideo.ru") ||
                             host_text.ends_with("dzen.ru") ||
                             host_text.ends_with("rutube.ru") ||
                             host_text.ends_with("ok.ru") ||
                             host_text.ends_with("coursera.org");
  if (!supported_host) {
    return false;
  }
  if (path == nil) {
    return true;
  }
  const std::string path_text = StringFromNSString(path);
  return path_text.find("/watch") != std::string::npos ||
         path_text.find("/video") != std::string::npos ||
         path_text.find("/videos") != std::string::npos ||
         path_text.find("/clip") != std::string::npos ||
         path_text.find("/clips") != std::string::npos ||
         path_text.find("/shorts") != std::string::npos;
}

bool LooksLikeVideoTranslationScript(const std::string& script) {
  return script.find("// ==UserScript==") != std::string::npos &&
         script.find("VOT") != std::string::npos &&
         script.find("voice-over-translation") != std::string::npos;
}

NSString* VideoTranslationShimSource() {
  return
      @"(() => {"
       "if (window.__brivibaVideoTranslationShimInstalled) return;"
       "window.__brivibaVideoTranslationShimInstalled = true;"
       "window.unsafeWindow = window.unsafeWindow || window;"
       "window.GM_info = window.GM_info || {"
       "  script: { name: 'Briviba Video Translation', version: 'local', author: 'Briviba' }"
       "};"
       "const storagePrefix = '__briviba_vot__';"
       "const readValue = (name, fallback) => {"
       "  try {"
       "    const raw = window.localStorage.getItem(storagePrefix + name);"
       "    return raw === null ? fallback : JSON.parse(raw);"
       "  } catch (_) {"
       "    return fallback;"
       "  }"
       "};"
       "const writeValue = (name, value) => {"
       "  try { window.localStorage.setItem(storagePrefix + name, JSON.stringify(value)); } catch (_) {}"
       "};"
       "const deleteValue = (name) => {"
       "  try { window.localStorage.removeItem(storagePrefix + name); } catch (_) {}"
       "};"
       "const listValues = () => {"
       "  try {"
       "    return Object.keys(window.localStorage)"
       "      .filter((key) => key.startsWith(storagePrefix))"
       "      .map((key) => key.slice(storagePrefix.length));"
       "  } catch (_) {"
       "    return [];"
       "  }"
       "};"
       "window.GM_addStyle = window.GM_addStyle || ((css) => {"
       "  const style = document.createElement('style');"
       "  style.textContent = css;"
       "  (document.head || document.documentElement).appendChild(style);"
       "  return style;"
       "});"
       "window.GM_getValue = window.GM_getValue || ((name, fallback) => readValue(name, fallback));"
       "window.GM_setValue = window.GM_setValue || ((name, value) => writeValue(name, value));"
       "window.GM_deleteValue = window.GM_deleteValue || ((name) => deleteValue(name));"
       "window.GM_listValues = window.GM_listValues || (() => listValues());"
       "window.GM_notification = window.GM_notification || ((details) => {"
       "  try { console.log(details); } catch (_) {}"
       "});"
        "const gmRequestStore = window.__brivibaGmRequestStore || new Map();"
        "window.__brivibaGmRequestStore = gmRequestStore;"
        "window.__brivibaGmRequestSeq = window.__brivibaGmRequestSeq || 0;"
        "const encodeArrayBuffer = (buffer) => {"
        "  try {"
        "    const bytes = new Uint8Array(buffer);"
        "    let binary = '';"
        "    const chunk = 0x8000;"
        "    for (let i = 0; i < bytes.length; i += chunk) {"
        "      const slice = bytes.subarray(i, i + chunk);"
        "      binary += String.fromCharCode(...slice);"
        "    }"
        "    return btoa(binary);"
        "  } catch (_) {"
        "    return null;"
        "  }"
        "};"
        "const encodeArrayBufferView = (view) => {"
        "  try {"
        "    const bytes = new Uint8Array(view.buffer, view.byteOffset || 0, view.byteLength || 0);"
        "    return encodeArrayBuffer(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));"
        "  } catch (_) {"
        "    return null;"
        "  }"
        "};"
        "const decodeBase64ToArrayBuffer = (base64) => {"
        "  const binary = atob(base64);"
        "  const bytes = new Uint8Array(binary.length);"
        "  for (let i = 0; i < binary.length; i += 1) {"
        "    bytes[i] = binary.charCodeAt(i);"
        "  }"
        "  return bytes.buffer;"
        "};"
        "const finishWithLoadEnd = (options, details) => {"
        "  if (typeof options.onloadend === 'function') {"
        "    try { options.onloadend(details); } catch (_) {}"
        "  }"
        "};"
        "window.__brivibaHandleGmXhrResponse = window.__brivibaHandleGmXhrResponse || ((result) => {"
        "  if (!result || typeof result.id !== 'string') return;"
        "  const request = gmRequestStore.get(result.id);"
        "  if (!request) return;"
        "  gmRequestStore.delete(result.id);"
        "  const options = request.options;"
        "  if (result.aborted) {"
        "    const abortResult = { aborted: true };"
        "    if (typeof options.onabort === 'function') options.onabort(abortResult);"
        "    finishWithLoadEnd(options, abortResult);"
        "    return;"
        "  }"
        "  if (result.timedOut) {"
        "    const timeoutResult = { statusText: 'Timeout', timedOut: true };"
        "    if (typeof options.ontimeout === 'function') options.ontimeout(timeoutResult);"
        "    finishWithLoadEnd(options, timeoutResult);"
        "    return;"
        "  }"
        "  if (result.error) {"
        "    const errorResult = { error: String(result.error), statusText: String(result.error) };"
        "    if (typeof options.onerror === 'function') options.onerror(errorResult);"
        "    finishWithLoadEnd(options, errorResult);"
        "    return;"
        "  }"
        "  const responseType = request.responseType;"
        "  let payload = result.response || '';"
        "  if (result.responseBase64 && (responseType === 'arraybuffer' || responseType === 'blob')) {"
        "    const arrayBuffer = decodeBase64ToArrayBuffer(result.responseBase64);"
        "    payload = responseType === 'blob' ? new Blob([arrayBuffer]) : arrayBuffer;"
        "  }"
        "  const loadResult = {"
        "    response: payload,"
        "    responseText: typeof payload === 'string' ? payload : '',"
        "    responseHeaders: result.responseHeaders || '',"
        "    status: Number(result.status || 0),"
        "    statusText: result.statusText || '',"
        "    finalUrl: result.finalUrl || options.url || ''"
        "  };"
        "  if (typeof options.onload === 'function') options.onload(loadResult);"
        "  finishWithLoadEnd(options, loadResult);"
        "});"
        "window.GM_xmlhttpRequest = window.GM_xmlhttpRequest || ((options) => {"
        "  const hasNativeBridge = !!(window.webkit && window.webkit.messageHandlers &&"
        "    window.webkit.messageHandlers.brivibaGmXhr);"
        "  const responseType = options.responseType || 'text';"
        "  const timeoutMs = Number(options.timeout || 0);"
        "  if (hasNativeBridge) {"
        "    const requestId = `gm_${Date.now()}_${window.__brivibaGmRequestSeq += 1}`;"
        "    const postNative = (requestBody) => {"
        "      try {"
        "        window.webkit.messageHandlers.brivibaGmXhr.postMessage({"
        "          op: 'start',"
        "          id: requestId,"
        "          url: options.url || '',"
        "          method: options.method || 'GET',"
          "          headers: options.headers || {},"
          "          responseType: responseType,"
          "          timeoutMs: Number.isFinite(timeoutMs) ? timeoutMs : 0,"
          "          data: requestBody"
          "        });"
        "      } catch (error) {"
        "        gmRequestStore.delete(requestId);"
        "        const errorResult = { error: String(error), statusText: String(error) };"
        "        if (typeof options.onerror === 'function') options.onerror(errorResult);"
        "        finishWithLoadEnd(options, errorResult);"
        "      }"
        "    };"
        "    gmRequestStore.set(requestId, { options, responseType });"
        "    const requestBody = options.data;"
        "    if (requestBody instanceof ArrayBuffer) {"
        "      const encoded = encodeArrayBuffer(requestBody);"
        "      postNative(encoded == null ? null : { __brivibaBase64: encoded });"
        "    } else if (ArrayBuffer.isView(requestBody)) {"
        "      const encoded = encodeArrayBufferView(requestBody);"
        "      postNative(encoded == null ? null : { __brivibaBase64: encoded });"
        "    } else if (typeof Blob !== 'undefined' && requestBody instanceof Blob) {"
        "      requestBody.arrayBuffer()"
        "        .then((buffer) => {"
        "          const encoded = encodeArrayBuffer(buffer);"
        "          postNative(encoded == null ? null : { __brivibaBase64: encoded });"
        "        })"
        "        .catch((error) => {"
        "          gmRequestStore.delete(requestId);"
        "          const errorResult = { error: String(error), statusText: String(error) };"
        "          if (typeof options.onerror === 'function') options.onerror(errorResult);"
        "          finishWithLoadEnd(options, errorResult);"
        "        });"
        "    } else if (typeof URLSearchParams !== 'undefined' && requestBody instanceof URLSearchParams) {"
        "      postNative(String(requestBody));"
        "    } else if (requestBody != null && typeof requestBody !== 'string') {"
        "      try {"
        "        postNative(JSON.stringify(requestBody));"
        "      } catch (_) {"
        "        postNative(String(requestBody));"
        "      }"
        "    } else {"
        "      postNative(requestBody == null ? null : requestBody);"
        "    }"
        "    return {"
        "      abort: () => {"
        "        gmRequestStore.delete(requestId);"
        "        try {"
        "          window.webkit.messageHandlers.brivibaGmXhr.postMessage({ op: 'abort', id: requestId });"
        "        } catch (_) {}"
        "      }"
        "    };"
        "  }"
      "  const controller = new AbortController();"
        "  const timeoutId = Number.isFinite(timeoutMs) && timeoutMs > 0"
        "    ? setTimeout(() => controller.abort('timeout'), timeoutMs)"
        "    : null;"
      "  const headers = new Headers(options.headers || {});"
      "  fetch(options.url, {"
      "    method: options.method || 'GET',"
      "    headers,"
      "    body: options.data,"
      "    signal: controller.signal,"
      "    credentials: 'include',"
      "  }).then(async (response) => {"
      "    let payload = null;"
      "    if (responseType === 'blob') {"
      "      payload = await response.blob();"
      "    } else if (responseType === 'arraybuffer') {"
      "      payload = await response.arrayBuffer();"
      "    } else {"
      "      payload = await response.text();"
      "    }"
      "    const responseHeaders = Array.from(response.headers.entries())"
      "      .map(([key, value]) => `${key}: ${value}`).join('\\n');"
      "    const loadResult = {"
      "      response: payload,"
      "      responseText: typeof payload === 'string' ? payload : '',"
      "      responseHeaders,"
      "      status: response.status,"
      "      statusText: response.statusText,"
      "      finalUrl: response.url,"
      "    };"
      "    if (typeof options.onload === 'function') options.onload(loadResult);"
      "    finishWithLoadEnd(options, loadResult);"
      "  }).catch((error) => {"
      "    if (controller.signal.aborted) {"
      "      const timeoutAbort = error === 'timeout';"
      "      if (timeoutAbort) {"
      "        const timeoutResult = { statusText: 'Timeout', timedOut: true };"
      "        if (typeof options.ontimeout === 'function') options.ontimeout(timeoutResult);"
      "        finishWithLoadEnd(options, timeoutResult);"
      "      } else {"
      "        if (typeof options.onabort === 'function') options.onabort(error);"
      "        finishWithLoadEnd(options, { aborted: true });"
      "      }"
      "      return;"
      "    }"
      "    if (typeof options.onerror === 'function') {"
      "      const errorResult = { error: String(error), statusText: String(error) };"
      "      options.onerror(errorResult);"
      "      finishWithLoadEnd(options, errorResult);"
      "    }"
      "  }).finally(() => {"
      "    if (timeoutId !== null) clearTimeout(timeoutId);"
      "  });"
      "  return { abort: () => controller.abort() };"
      "});"
       "})();";
}

NSString* VideoTranslationSourceUrl() {
  return @"https://gist.githubusercontent.com/RimuruDev/c9b2d31562a50afa5d8f6e2e21ef4698/raw/Tempermonkey.js";
}

}  // namespace

class BrowserWindow::Impl {
 public:
  Impl() {
    [NSWindow setAllowsAutomaticWindowTabbing:NO];

    window_ = [[NSWindow alloc] initWithContentRect:InitialWindowFrame()
                                          styleMask:WindowStyleMask()
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [window_ setTitle:@"Briviba"];
    [window_ setTitleVisibility:NSWindowTitleHidden];
    [window_ setTitlebarAppearsTransparent:YES];
    [window_ setMovableByWindowBackground:YES];
    [window_ setOpaque:NO];
    [window_ setBackgroundColor:[NSColor clearColor]];
    [window_ setReleasedWhenClosed:NO];
    [window_ setMinSize:NSMakeSize(860.0, 560.0)];
    [[window_ standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[window_ standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[window_ standardWindowButton:NSWindowZoomButton] setHidden:YES];
    [window_ setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    window_control_bridge_ = [[BrivibaWindowControlBridge alloc] init];
    window_control_bridge_->close_action = [this] { CloseWindow(); };
    window_control_bridge_->minimize_action = [this] { MinimizeWindow(); };
    window_control_bridge_->fullscreen_action = [this] { ToggleCustomFullscreen(); };
    window_control_bridge_->fullscreen_enter_action = [this] { EnterNativeFullscreenChrome(); };
    window_control_bridge_->fullscreen_exit_action = [this] { ExitNativeFullscreenChrome(); };
    window_control_bridge_->window_will_close_action = [this] { PersistSessionSnapshot(); };
    [window_ setDelegate:window_control_bridge_];
    settings_bridge_ = [[BrivibaSettingsBridge alloc] init];
    settings_bridge_->set_start_secure_action = [this](bool value) {
      settings_manager_.SetStartWithSecureMode(value);
    };
    settings_bridge_->set_search_engine_action = [this](const std::string& engine_id) {
      settings_manager_.SetDefaultSearchEngine(engine_id);
      tab_manager_.SetSearchEngine(settings_manager_.DefaultSearchEngine());
    };
    settings_bridge_->set_tab_dock_position_action =
        [this](SettingsManager::SidebarDockPosition position) {
          settings_manager_.SetTabDockPosition(position);
          ApplySidebarDockPosition();
        };
    settings_bridge_->clear_all_cookies_action = [this] { ClearAllCookiesAndSiteState(); };
    settings_bridge_->clear_all_caches_action = [this] { ClearAllCaches(); };
    settings_bridge_->show_cookies_action = [this] { RefreshCookieListText(); };
    settings_bridge_->settings_closed_action = [this] { settings_window_ = nil; };

    content_view_ = [[NSView alloc] initWithFrame:[[window_ contentView] bounds]];
    [content_view_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content_view_ setWantsLayer:YES];
    [[content_view_ layer] setBackgroundColor:[[NSColor clearColor] CGColor]];
    [window_ setContentView:content_view_];
    chrome_background_ = [[NSView alloc] initWithFrame:NSZeroRect];
    [chrome_background_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [chrome_background_ setWantsLayer:YES];
    [[chrome_background_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:1.0] CGColor]];

    sidebar_.SetNewTabAction([this] { CreateNewTab(); });
    sidebar_.SetOpenFilesAction([this](const std::vector<std::string>& file_urls) {
      OpenFileUrls(file_urls);
    });
    sidebar_.SetSettingsAction([this] { ShowSettingsWindow(); });
    sidebar_.SetSelectTabAction([this](size_t index) { tab_manager_.SelectTab(index); });
    sidebar_.SetCloseTabAction([this](size_t index) { tab_manager_.CloseTab(index); });
    sidebar_.SetBackTabAction([this](size_t index) { GoBackTab(index); });
    sidebar_.SetForwardTabAction([this](size_t index) { GoForwardTab(index); });
    sidebar_.SetReloadTabAction([this](size_t index) { ReloadTab(index); });
    sidebar_.SetTranslateVideoAction([this] { OpenVideoTranslation(); });
    sidebar_.SetEditTabAddressAction([this](size_t index) { ShowAddressEditor(index); });
    sidebar_.SetClearTabCookiesAction([this](size_t index) {
      ClearCookiesAndSiteStateForTab(index);
    });
    sidebar_.SetClearTabCachesAction([this](size_t index) { ClearCachesForTab(index); });
    tab_manager_.SetNavigationStateCallback(
        [this](bool can_go_back, bool can_go_forward, const std::string& url,
               const std::string& title, const std::string& favicon_url) {
          (void)favicon_url;
          (void)can_go_back;
          (void)can_go_forward;
          (void)title;
          sidebar_.SetTranslateVideoVisible(ShouldShowVideoTranslateButton(url));
          if (!secure_mode_) {
            history_manager_.RecordVisit(url);
          }
        });
    tab_manager_.SetPageColorCallback([this](Tab::PageColor color) { ApplyPageColor(color); });
    tab_manager_.SetTabStateCallback([this](const std::vector<TabManager::TabState>& tabs,
                                            size_t active_index) {
      std::vector<Sidebar::TabState> sidebar_tabs;
      std::vector<std::string> session_urls;
      sidebar_tabs.reserve(tabs.size());
      session_urls.reserve(tabs.size());
      for (const auto& tab : tabs) {
        sidebar_tabs.push_back(Sidebar::TabState{tab.url, tab.title, tab.favicon_url});
        session_urls.push_back(tab.url);
      }
      sidebar_.SetTabState(sidebar_tabs, active_index);
      if (!secure_mode_) {
        settings_manager_.SetSessionState(session_urls, active_index);
      }
    });
    if (settings_manager_.StartWithSecureMode()) {
      secure_mode_ = true;
      tab_manager_.SetBrowsingMode(TabManager::BrowsingMode::kSecure);
    }
    tab_manager_.SetSearchEngine(settings_manager_.DefaultSearchEngine());
    traffic_light_stack_ = TrafficLightStack(window_control_bridge_);

    [content_view_ addSubview:chrome_background_];
    [content_view_ addSubview:tab_manager_.NativeView()];
    [content_view_ addSubview:sidebar_.NativeView()];
    [content_view_ addSubview:traffic_light_stack_];
    sidebar_top_constraint_ =
        [[sidebar_.NativeView() topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                          constant:kSidebarTop];
    left_layout_constraints_ = @[
      [[chrome_background_ leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                         constant:kWebViewLeading],
      [[chrome_background_ topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]],
      [[chrome_background_ trailingAnchor] constraintEqualToAnchor:[content_view_ trailingAnchor]],
      [[chrome_background_ heightAnchor] constraintEqualToConstant:kWebViewTop],
      [[tab_manager_.NativeView() leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                                constant:kWebViewLeading],
      [[tab_manager_.NativeView() topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                            constant:kWebViewTop],
      [[tab_manager_.NativeView() trailingAnchor] constraintEqualToAnchor:[content_view_ trailingAnchor]
                                                                 constant:-kWebViewTrailing],
      [[tab_manager_.NativeView() bottomAnchor] constraintEqualToAnchor:[content_view_ bottomAnchor]
                                                               constant:-kWebViewBottom],
      [[sidebar_.NativeView() leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                            constant:kSidebarLeading],
      sidebar_top_constraint_,
      [[sidebar_.NativeView() bottomAnchor] constraintEqualToAnchor:[content_view_ bottomAnchor]
                                                           constant:-kSidebarBottom],
      [[traffic_light_stack_ centerXAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                           constant:kSidebarLeading +
                                                                    kWebViewLeading / 2.0],
      [[traffic_light_stack_ topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                       constant:23.0],
    ];
    top_layout_constraints_ = @[
      [[chrome_background_ leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]],
      [[chrome_background_ topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]],
      [[chrome_background_ trailingAnchor] constraintEqualToAnchor:[content_view_ trailingAnchor]],
      [[chrome_background_ heightAnchor] constraintEqualToConstant:kWebViewTop],
      [[tab_manager_.NativeView() leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]],
      [[tab_manager_.NativeView() topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                            constant:kTopDockHeight],
      [[tab_manager_.NativeView() trailingAnchor] constraintEqualToAnchor:[content_view_ trailingAnchor]
                                                                 constant:-kWebViewTrailing],
      [[tab_manager_.NativeView() bottomAnchor] constraintEqualToAnchor:[content_view_ bottomAnchor]
                                                               constant:-kWebViewBottom],
      [[sidebar_.NativeView() leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                            constant:kSidebarLeading],
      sidebar_top_constraint_,
      [[sidebar_.NativeView() trailingAnchor] constraintEqualToAnchor:[content_view_ trailingAnchor]
                                                             constant:-kSidebarBottom],
      [[sidebar_.NativeView() heightAnchor] constraintEqualToConstant:kTopDockHeight],
      [[traffic_light_stack_ centerXAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                           constant:kSidebarLeading +
                                                                    kWebViewLeading / 2.0],
      [[traffic_light_stack_ topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                       constant:23.0],
    ];
    [NSLayoutConstraint activateConstraints:left_layout_constraints_];
    ApplySidebarDockPosition();
    cookie_manager_.WhenReady([this] { LoadInitialSession(); });
  }

  ~Impl() {
    PersistSessionSnapshot();
    [window_ close];
  }

  void Show() {
    [window_ makeKeyAndOrderFront:nil];
  }

  void NewTab() { CreateNewTab(); }

 private:
  void CreateNewTab() {
    tab_manager_.CreateTab();
    tab_manager_.LoadUrl(DefaultStartUrl());
  }

  void OpenFileUrls(const std::vector<std::string>& file_urls) {
    for (const std::string& file_url : file_urls) {
      if (file_url.empty()) {
        continue;
      }
      tab_manager_.CreateTab();
      tab_manager_.LoadUrl(file_url);
    }
  }

  void LoadInitialSession() {
    if (initial_session_loaded_) {
      return;
    }
    initial_session_loaded_ = true;
    const bool restored_session =
        !secure_mode_ && tab_manager_.RestoreTabs(settings_manager_.SessionTabUrls(),
                                                  settings_manager_.SessionActiveTabIndex());
    if (!restored_session) {
      tab_manager_.CreateInitialTab();
      tab_manager_.LoadUrl(DefaultStartUrl());
    }
  }

  std::string DefaultStartUrl() const {
    return SearchEngineHomeUrl(settings_manager_.DefaultSearchEngine());
  }

  void GoBackTab(size_t index) {
    tab_manager_.SelectTab(index);
    tab_manager_.GoBack();
  }

  void GoForwardTab(size_t index) {
    tab_manager_.SelectTab(index);
    tab_manager_.GoForward();
  }

  void ReloadTab(size_t index) {
    tab_manager_.SelectTab(index);
    tab_manager_.Reload();
  }

  void ShowAddressEditor(size_t index) {
    tab_manager_.SelectTab(index);

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Edit Address"];
    [alert setInformativeText:@"Enter a URL or search query for this tab."];
    [alert addButtonWithTitle:@"Open"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField* address_field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 26.0)];
    [address_field setStringValue:[NSString stringWithUTF8String:tab_manager_.CurrentUrl().c_str()]];
    [address_field setUsesSingleLineMode:YES];
    [address_field setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [alert setAccessoryView:address_field];

    NSWindow* alert_window = [alert window];
    [alert_window setInitialFirstResponder:address_field];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
      return;
    }

    tab_manager_.LoadUrl(StringFromNSString([address_field stringValue]));
  }

  bool ConfirmDestructiveAction(NSString* title, NSString* detail) {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:title];
    [alert setInformativeText:detail];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    [[alert buttons][0] setKeyEquivalent:@""];
    return [alert runModal] == NSAlertFirstButtonReturn;
  }

  void ShowStorageDone(NSString* message) {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
  }

  void ClearAllCookiesAndSiteState() {
    if (!ConfirmDestructiveAction(@"Delete all cookies and site state?",
                                  @"This signs sites out and resets cookie banners, local storage, "
                                  @"IndexedDB, and related site state.")) {
      return;
    }
    cookie_manager_.ClearAllCookiesAndSiteState([this] {
      ShowStorageDone(@"All cookies and site state were deleted.");
      RefreshCookieListText();
    });
  }

  void ClearAllCaches() {
    if (!ConfirmDestructiveAction(@"Delete all caches?",
                                  @"This clears WebKit disk cache, memory cache, offline cache, "
                                  @"and service worker registrations.")) {
      return;
    }
    cookie_manager_.ClearAllCaches([this] { ShowStorageDone(@"All caches were deleted."); });
  }

  void ClearCookiesAndSiteStateForTab(size_t index) {
    const std::string domain = HostFromUrl(tab_manager_.UrlForTab(index));
    if (domain.empty()) {
      return;
    }
    NSString* domain_string = [NSString stringWithUTF8String:domain.c_str()];
    NSString* detail =
        [NSString stringWithFormat:@"This deletes cookies and site state for %@.", domain_string];
    if (!ConfirmDestructiveAction(@"Delete cookies for this domain?", detail)) {
      return;
    }
    cookie_manager_.ClearCookiesAndSiteStateForDomain(domain, [this, domain] {
      NSString* domain_string = [NSString stringWithUTF8String:domain.c_str()];
      ShowStorageDone([NSString stringWithFormat:@"Cookies and site state were deleted for %@.",
                                                 domain_string]);
      RefreshCookieListText();
    });
  }

  void ClearCachesForTab(size_t index) {
    const std::string domain = HostFromUrl(tab_manager_.UrlForTab(index));
    if (domain.empty()) {
      return;
    }
    NSString* domain_string = [NSString stringWithUTF8String:domain.c_str()];
    NSString* detail = [NSString stringWithFormat:@"This deletes WebKit caches for %@.",
                                                  domain_string];
    if (!ConfirmDestructiveAction(@"Delete caches for this domain?", detail)) {
      return;
    }
    cookie_manager_.ClearCachesForDomain(domain, [this, domain] {
      NSString* domain_string = [NSString stringWithUTF8String:domain.c_str()];
      ShowStorageDone([NSString stringWithFormat:@"Caches were deleted for %@.", domain_string]);
    });
  }

  void ToggleBrowsingMode() {
    secure_mode_ = !secure_mode_;
    tab_manager_.SetBrowsingMode(secure_mode_ ? TabManager::BrowsingMode::kSecure
                                              : TabManager::BrowsingMode::kNormal);
  }

  void OpenVideoTranslation() {
    if (!ShouldShowVideoTranslateButton(tab_manager_.CurrentUrl())) {
      return;
    }
    if (video_translation_loading_) {
      return;
    }
    if (!video_translation_script_cache_.empty()) {
      InjectVideoTranslationScript(video_translation_script_cache_);
      return;
    }

    video_translation_loading_ = true;
    NSURL* script_url = [NSURL URLWithString:VideoTranslationSourceUrl()];
    NSURLSessionDataTask* task =
        [[NSURLSession sharedSession] dataTaskWithURL:script_url
                                   completionHandler:[this](NSData* data, NSURLResponse* response,
                                                            NSError* error) {
                                     (void)response;
                                     std::string loaded_script;
                                     if (error == nil && [data length] > 0) {
                                       NSString* script = [[NSString alloc] initWithData:data
                                                                                 encoding:NSUTF8StringEncoding];
                                       if (script != nil) {
                                         const char* utf8 = [script UTF8String];
                                         if (utf8 != nullptr) {
                                           std::string candidate_script(utf8);
                                           if (LooksLikeVideoTranslationScript(candidate_script)) {
                                             loaded_script = std::move(candidate_script);
                                           }
                                         }
                                       }
                                     }
                                     dispatch_async(dispatch_get_main_queue(), [this, loaded_script] {
                                       video_translation_loading_ = false;
                                       if (loaded_script.empty()) {
                                         video_translation_script_cache_.clear();
                                         ShowStorageDone(@"Could not load the video translation module.");
                                         return;
                                       }
                                       video_translation_script_cache_ = loaded_script;
                                       InjectVideoTranslationScript(video_translation_script_cache_);
                                     });
                                   }];
    [task resume];
  }

  void InjectVideoTranslationScript(const std::string& script) {
    if (script.empty()) {
      return;
    }

    NSString* shim = VideoTranslationShimSource();
    NSString* source = [NSString stringWithUTF8String:script.c_str()];
    NSMutableString* wrapped_script = [NSMutableString string];
    [wrapped_script appendString:shim];
    [wrapped_script appendString:@"\n(() => {"];
    [wrapped_script appendString:@"if (window.__brivibaVideoTranslationInstalled) return;"];
    [wrapped_script appendString:@"\n"];
    [wrapped_script appendString:@"try {"];
    [wrapped_script appendString:source];
    [wrapped_script appendString:@"\nwindow.__brivibaVideoTranslationInstalled = true;"];
    [wrapped_script appendString:@"} catch (error) { console.error(error); }"];
    [wrapped_script appendString:@"\n})();"];
    tab_manager_.EvaluateJavaScriptOnActiveTab(StringFromNSString(wrapped_script));
  }

  void AddCurrentBookmark() { bookmark_manager_.AddBookmark(tab_manager_.CurrentUrl()); }

  void CloseWindow() {
    PersistSessionSnapshot();
    [window_ close];
  }

  void PersistSessionSnapshot() {
    if (secure_mode_) {
      return;
    }
    settings_manager_.SetSessionState(tab_manager_.SessionUrls(), tab_manager_.ActiveIndex());
  }

  void MinimizeWindow() {
    [window_ miniaturize:nil];
  }

  void ToggleCustomFullscreen() {
    [window_ toggleFullScreen:nil];
  }

  void ApplySidebarDockPosition() {
    const bool top_mode =
        settings_manager_.TabDockPosition() == SettingsManager::SidebarDockPosition::kTop;
    [NSLayoutConstraint deactivateConstraints:left_layout_constraints_];
    [NSLayoutConstraint deactivateConstraints:top_layout_constraints_];
    sidebar_.SetDockPosition(top_mode ? Sidebar::DockPosition::kTop : Sidebar::DockPosition::kLeft);
    [NSLayoutConstraint activateConstraints:top_mode ? top_layout_constraints_
                                                     : left_layout_constraints_];
    [[content_view_ superview] layoutSubtreeIfNeeded];
  }

  void EnterNativeFullscreenChrome() {
    [traffic_light_stack_ setHidden:YES];
    [[window_ standardWindowButton:NSWindowCloseButton] setHidden:NO];
    [[window_ standardWindowButton:NSWindowMiniaturizeButton] setHidden:NO];
    [[window_ standardWindowButton:NSWindowZoomButton] setHidden:NO];
    [sidebar_top_constraint_ setConstant:kFullscreenSidebarTop];
    [[content_view_ superview] layoutSubtreeIfNeeded];
    sidebar_.SetFullscreenAppearance(true);
  }

  void ExitNativeFullscreenChrome() {
    [[window_ standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[window_ standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[window_ standardWindowButton:NSWindowZoomButton] setHidden:YES];
    [traffic_light_stack_ setHidden:NO];
    [sidebar_top_constraint_ setConstant:kSidebarTop];
    [[content_view_ superview] layoutSubtreeIfNeeded];
    sidebar_.SetFullscreenAppearance(false);
  }

  void ShowSettingsWindow() {
    if (settings_window_ != nil) {
      [settings_window_ makeKeyAndOrderFront:nil];
      RefreshCookieListText();
      return;
    }

    settings_window_ = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0, 620.0, 500.0)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [settings_window_ setTitle:@"Settings"];
    [settings_window_ setReleasedWhenClosed:NO];
    [settings_window_ setDelegate:settings_bridge_];
    [settings_window_ center];

    NSView* settings_view = [[NSView alloc] initWithFrame:NSZeroRect];
    [settings_view setWantsLayer:YES];
    [[settings_view layer] setBackgroundColor:[[NSColor windowBackgroundColor] CGColor]];
    [settings_window_ setContentView:settings_view];

    NSTabView* tab_view = [[NSTabView alloc] initWithFrame:NSZeroRect];
    [tab_view setTranslatesAutoresizingMaskIntoConstraints:NO];
    [settings_view addSubview:tab_view];

    NSTabViewItem* general_item = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    [general_item setLabel:@"General"];
    NSView* general_view = [[NSView alloc] initWithFrame:NSZeroRect];
    [general_item setView:general_view];
    [tab_view addTabViewItem:general_item];

    NSTabViewItem* cookies_item = [[NSTabViewItem alloc] initWithIdentifier:@"cookies"];
    [cookies_item setLabel:@"Cookies"];
    NSView* cookies_view = [[NSView alloc] initWithFrame:NSZeroRect];
    [cookies_item setView:cookies_view];
    [tab_view addTabViewItem:cookies_item];

    NSTextField* title_label = [NSTextField labelWithString:@"Briviba Settings"];
    [title_label setFont:[NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold]];
    [title_label setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSTextField* search_label = [NSTextField labelWithString:@"Search"];
    [search_label setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
    [search_label setTextColor:[NSColor secondaryLabelColor]];
    [search_label setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSPopUpButton* search_engine_popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
    [search_engine_popup setTarget:settings_bridge_];
    [search_engine_popup setAction:@selector(changeSearchEngine:)];
    [search_engine_popup setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSDictionary<NSString*, NSString*>* search_engines = @{
      @"DuckDuckGo" : @"duckduckgo",
      @"Google" : @"google",
      @"Bing" : @"bing",
      @"Yandex" : @"yandex",
    };
    for (NSString* title in @[ @"DuckDuckGo", @"Google", @"Bing", @"Yandex" ]) {
      [search_engine_popup addItemWithTitle:title];
      [[search_engine_popup lastItem] setRepresentedObject:search_engines[title]];
    }

    NSString* selected_search_engine =
        [NSString stringWithUTF8String:settings_manager_.DefaultSearchEngine().c_str()];
    for (NSMenuItem* item in [search_engine_popup itemArray]) {
      if ([[item representedObject] isEqualToString:selected_search_engine]) {
        [search_engine_popup selectItem:item];
        break;
      }
    }

    NSTextField* privacy_label = [NSTextField labelWithString:@"Privacy"];
    [privacy_label setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
    [privacy_label setTextColor:[NSColor secondaryLabelColor]];
    [privacy_label setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSTextField* tabs_label = [NSTextField labelWithString:@"Tabs"];
    [tabs_label setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
    [tabs_label setTextColor:[NSColor secondaryLabelColor]];
    [tabs_label setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSSegmentedControl* tab_dock_control = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    [tab_dock_control setSegmentCount:2];
    [tab_dock_control setLabel:@"Left" forSegment:0];
    [tab_dock_control setLabel:@"Top" forSegment:1];
    [tab_dock_control setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    [tab_dock_control setTarget:settings_bridge_];
    [tab_dock_control setAction:@selector(changeTabDockPosition:)];
    [tab_dock_control setTranslatesAutoresizingMaskIntoConstraints:NO];
    [tab_dock_control setSelectedSegment:
                          settings_manager_.TabDockPosition() ==
                                  SettingsManager::SidebarDockPosition::kTop
                              ? 1
                              : 0];

    NSButton* start_secure_checkbox =
        [NSButton checkboxWithTitle:@"Start new sessions in Secure Mode"
                             target:settings_bridge_
                             action:@selector(toggleStartSecure:)];
    [start_secure_checkbox setState:settings_manager_.StartWithSecureMode()
                                        ? NSControlStateValueOn
                                        : NSControlStateValueOff];
    [start_secure_checkbox setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSTextField* start_secure_help = [NSTextField
        labelWithString:@"Secure Mode uses non-persistent WebKit storage for newly opened tabs."];
    [start_secure_help setFont:[NSFont systemFontOfSize:12.0]];
    [start_secure_help setTextColor:[NSColor secondaryLabelColor]];
    [start_secure_help setLineBreakMode:NSLineBreakByWordWrapping];
    [start_secure_help setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSTextField* storage_label = [NSTextField labelWithString:@"Storage"];
    [storage_label setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
    [storage_label setTextColor:[NSColor secondaryLabelColor]];
    [storage_label setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSButton* clear_cookies_button =
        [NSButton buttonWithTitle:@"Delete Cookies & Site State"
                           target:settings_bridge_
                           action:@selector(clearAllCookies:)];
    [clear_cookies_button setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSButton* clear_caches_button = [NSButton buttonWithTitle:@"Delete Caches"
                                                       target:settings_bridge_
                                                       action:@selector(clearAllCaches:)];
    [clear_caches_button setTranslatesAutoresizingMaskIntoConstraints:NO];

    [general_view addSubview:title_label];
    [general_view addSubview:search_label];
    [general_view addSubview:search_engine_popup];
    [general_view addSubview:privacy_label];
    [general_view addSubview:tabs_label];
    [general_view addSubview:tab_dock_control];
    [general_view addSubview:start_secure_checkbox];
    [general_view addSubview:start_secure_help];
    [general_view addSubview:storage_label];
    [general_view addSubview:clear_cookies_button];
    [general_view addSubview:clear_caches_button];

    NSTextField* cookies_title = [NSTextField labelWithString:@"Cookies"];
    [cookies_title setFont:[NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold]];
    [cookies_title setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSButton* refresh_cookies_button =
        [NSButton buttonWithTitle:@"Refresh"
                           target:settings_bridge_
                           action:@selector(showCookies:)];
    [refresh_cookies_button setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSScrollView* cookie_scroll_view = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [cookie_scroll_view setHasVerticalScroller:YES];
    [cookie_scroll_view setAutohidesScrollers:YES];
    [cookie_scroll_view setTranslatesAutoresizingMaskIntoConstraints:NO];

    cookie_list_text_view_ = [[NSTextView alloc] initWithFrame:NSZeroRect];
    [cookie_list_text_view_ setEditable:NO];
    [cookie_list_text_view_ setFont:[NSFont monospacedSystemFontOfSize:12.0
                                                                 weight:NSFontWeightRegular]];
    [cookie_list_text_view_ setString:@"Loading cookies..."];
    [cookie_scroll_view setDocumentView:cookie_list_text_view_];

    [cookies_view addSubview:cookies_title];
    [cookies_view addSubview:refresh_cookies_button];
    [cookies_view addSubview:cookie_scroll_view];

    [NSLayoutConstraint activateConstraints:@[
      [[tab_view leadingAnchor] constraintEqualToAnchor:[settings_view leadingAnchor]
                                               constant:12.0],
      [[tab_view topAnchor] constraintEqualToAnchor:[settings_view topAnchor] constant:12.0],
      [[tab_view trailingAnchor] constraintEqualToAnchor:[settings_view trailingAnchor]
                                                constant:-12.0],
      [[tab_view bottomAnchor] constraintEqualToAnchor:[settings_view bottomAnchor]
                                              constant:-12.0],

      [[title_label leadingAnchor] constraintEqualToAnchor:[general_view leadingAnchor]
                                                  constant:24.0],
      [[title_label topAnchor] constraintEqualToAnchor:[general_view topAnchor] constant:22.0],
      [[search_label leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[search_label topAnchor] constraintEqualToAnchor:[title_label bottomAnchor]
                                                constant:28.0],
      [[search_engine_popup leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[search_engine_popup topAnchor] constraintEqualToAnchor:[search_label bottomAnchor]
                                                      constant:10.0],
      [[search_engine_popup widthAnchor] constraintEqualToConstant:220.0],
      [[privacy_label leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[privacy_label topAnchor] constraintEqualToAnchor:[search_engine_popup bottomAnchor]
                                                constant:28.0],
      [[tabs_label leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[tabs_label topAnchor] constraintEqualToAnchor:[privacy_label bottomAnchor]
                                               constant:24.0],
      [[tab_dock_control leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[tab_dock_control topAnchor] constraintEqualToAnchor:[tabs_label bottomAnchor]
                                                   constant:10.0],
      [[start_secure_checkbox leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[start_secure_checkbox topAnchor] constraintEqualToAnchor:[tab_dock_control bottomAnchor]
                                                        constant:12.0],
      [[start_secure_help leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[start_secure_help topAnchor] constraintEqualToAnchor:[start_secure_checkbox bottomAnchor]
                                                   constant:8.0],
      [[start_secure_help trailingAnchor] constraintEqualToAnchor:[general_view trailingAnchor]
                                                         constant:-24.0],
      [[storage_label leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[storage_label topAnchor] constraintEqualToAnchor:[start_secure_help bottomAnchor]
                                               constant:24.0],
      [[clear_cookies_button leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[clear_cookies_button topAnchor] constraintEqualToAnchor:[storage_label bottomAnchor]
                                                      constant:12.0],
      [[clear_caches_button leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[clear_caches_button topAnchor] constraintEqualToAnchor:[clear_cookies_button bottomAnchor]
                                                     constant:10.0],

      [[cookies_title leadingAnchor] constraintEqualToAnchor:[cookies_view leadingAnchor]
                                                    constant:18.0],
      [[cookies_title topAnchor] constraintEqualToAnchor:[cookies_view topAnchor] constant:18.0],
      [[refresh_cookies_button trailingAnchor] constraintEqualToAnchor:[cookies_view trailingAnchor]
                                                              constant:-18.0],
      [[refresh_cookies_button centerYAnchor] constraintEqualToAnchor:[cookies_title centerYAnchor]],
      [[cookie_scroll_view leadingAnchor] constraintEqualToAnchor:[cookies_view leadingAnchor]
                                                         constant:18.0],
      [[cookie_scroll_view topAnchor] constraintEqualToAnchor:[cookies_title bottomAnchor]
                                                    constant:14.0],
      [[cookie_scroll_view trailingAnchor] constraintEqualToAnchor:[cookies_view trailingAnchor]
                                                          constant:-18.0],
      [[cookie_scroll_view bottomAnchor] constraintEqualToAnchor:[cookies_view bottomAnchor]
                                                       constant:-18.0],
    ]];

    [settings_window_ makeKeyAndOrderFront:nil];
    RefreshCookieListText();
  }

  std::string CookieListText(const std::vector<CookieManager::CookieInfo>& cookies) const {
    std::ostringstream output;
    output << "Cookies: " << cookies.size() << "\n\n";
    for (const auto& cookie : cookies) {
      output << cookie.container << " / " << cookie.domain << "\n"
             << "  " << cookie.name << "=<hidden, " << cookie.value.size() << " chars>\n"
             << "  path: " << cookie.path << "\n";
      if (!cookie.expires.empty()) {
        output << "  expires: " << cookie.expires << "\n";
      }
      output << "  secure: " << (cookie.secure ? "yes" : "no")
             << ", httpOnly: " << (cookie.http_only ? "yes" : "no") << "\n\n";
    }
    return output.str();
  }

  void RefreshCookieListText() {
    if (cookie_list_text_view_ == nil) {
      return;
    }
    [cookie_list_text_view_ setString:@"Loading cookies..."];
    cookie_manager_.ListCookies([this](std::vector<CookieManager::CookieInfo> cookies) {
      std::sort(cookies.begin(), cookies.end(), [](const auto& left, const auto& right) {
        return std::tie(left.container, left.domain, left.name, left.path) <
               std::tie(right.container, right.domain, right.name, right.path);
      });
      [cookie_list_text_view_ setString:[NSString stringWithUTF8String:CookieListText(cookies).c_str()]];
    });
  }

  void ApplyPageColor(Tab::PageColor color) {
    if (std::abs(last_page_color_.red - color.red) < kColorEpsilon &&
        std::abs(last_page_color_.green - color.green) < kColorEpsilon &&
        std::abs(last_page_color_.blue - color.blue) < kColorEpsilon &&
        std::abs(last_page_color_.alpha - color.alpha) < kColorEpsilon) {
      return;
    }

    last_page_color_ = color;
    const bool transparent = color.alpha < 0.05;
    NSColor* page_color = [NSColor colorWithSRGBRed:transparent ? 1.0 : color.red
                                             green:transparent ? 1.0 : color.green
                                              blue:transparent ? 1.0 : color.blue
                                             alpha:1.0];
    [[chrome_background_ layer] setBackgroundColor:[page_color CGColor]];
  }

  BookmarkManager bookmark_manager_{BookmarkManager::DefaultDatabasePath()};
  HistoryManager history_manager_{HistoryManager::DefaultDatabasePath()};
  SettingsManager settings_manager_{SettingsManager::DefaultDatabasePath()};
  CookieManager cookie_manager_{CookieManager::DefaultDatabasePath()};
  DownloadManager download_manager_{DownloadManager::DefaultDatabasePath()};
  Sidebar sidebar_;
  TabManager tab_manager_{cookie_manager_, download_manager_};
  NSWindow* window_ = nil;
  NSView* content_view_ = nil;
  NSView* chrome_background_ = nil;
  NSLayoutConstraint* sidebar_top_constraint_ = nil;
  NSArray<NSLayoutConstraint*>* left_layout_constraints_ = nil;
  NSArray<NSLayoutConstraint*>* top_layout_constraints_ = nil;
  NSStackView* traffic_light_stack_ = nil;
  BrivibaWindowControlBridge* window_control_bridge_ = nil;
  BrivibaSettingsBridge* settings_bridge_ = nil;
  NSWindow* settings_window_ = nil;
  NSTextView* cookie_list_text_view_ = nil;
  Tab::PageColor last_page_color_;
  bool initial_session_loaded_ = false;
  bool secure_mode_ = false;
  bool video_translation_loading_ = false;
  std::string video_translation_script_cache_;
};

BrowserWindow::BrowserWindow() : impl_(std::make_unique<Impl>()) {}

BrowserWindow::~BrowserWindow() = default;

void BrowserWindow::Show() {
  impl_->Show();
}

void BrowserWindow::CreateNewTab() {
  impl_->NewTab();
}

}  // namespace briviba

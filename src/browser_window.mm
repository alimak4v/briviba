#include "briviba/browser_window.h"

#include "briviba/bookmark_manager.h"
#include "briviba/cookie_manager.h"
#include "briviba/download_manager.h"
#include "briviba/history_manager.h"
#include "briviba/sidebar.h"
#include "briviba/tab_manager.h"
#include "briviba/toolbar.h"

#import <AppKit/AppKit.h>

#include <algorithm>

namespace briviba {
namespace {

constexpr CGFloat kInitialWidth = 1180.0;
constexpr CGFloat kInitialHeight = 760.0;
constexpr CGFloat kVisibleFrameScale = 0.88;
constexpr CGFloat kSidebarLeading = 16.0;
constexpr CGFloat kSidebarTop = 58.0;
constexpr CGFloat kSidebarBottom = 18.0;
constexpr CGFloat kToolbarLeading = 136.0;
constexpr CGFloat kToolbarTop = 18.0;
constexpr CGFloat kToolbarTrailing = 24.0;
constexpr CGFloat kWebViewLeading = 96.0;
constexpr CGFloat kWebViewTop = 76.0;
constexpr CGFloat kWebViewTrailing = 16.0;
constexpr CGFloat kWebViewBottom = 18.0;

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

}  // namespace

class BrowserWindow::Impl {
 public:
  Impl() {
    window_ = [[NSWindow alloc] initWithContentRect:InitialWindowFrame()
                                          styleMask:WindowStyleMask()
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [window_ setTitle:@"Briviba"];
    [window_ setTitlebarAppearsTransparent:YES];
    [window_ setMovableByWindowBackground:YES];
    [window_ setReleasedWhenClosed:NO];
    [window_ setMinSize:NSMakeSize(860.0, 560.0)];

    content_view_ = [[NSView alloc] initWithFrame:[[window_ contentView] bounds]];
    [content_view_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content_view_ setWantsLayer:YES];
    [[content_view_ layer] setBackgroundColor:[[NSColor windowBackgroundColor] CGColor]];
    [window_ setContentView:content_view_];

    sidebar_.SetNewTabAction([this] { tab_manager_.CreateTab(); });
    toolbar_.SetBackAction([this] { tab_manager_.GoBack(); });
    toolbar_.SetForwardAction([this] { tab_manager_.GoForward(); });
    toolbar_.SetReloadAction([this] { tab_manager_.Reload(); });
    toolbar_.SetBookmarkAction([this] { AddCurrentBookmark(); });
    toolbar_.SetMenuAction([this] { ToggleBrowsingMode(); });
    toolbar_.SetAddressSubmitAction([this](const std::string& text) {
      if (tab_manager_.LoadUrl(text)) {
        toolbar_.SetAddressText(text);
      }
    });
    tab_manager_.SetNavigationStateCallback(
        [this](bool can_go_back, bool can_go_forward, const std::string& url) {
          toolbar_.SetNavigationState(can_go_back, can_go_forward);
          toolbar_.SetAddressText(url);
          if (!secure_mode_) {
            history_manager_.RecordVisit(url);
          }
        });
    tab_manager_.SetPageColorCallback([this](Tab::PageColor color) { ApplyPageColor(color); });
    tab_manager_.CreateInitialTab();

    [content_view_ addSubview:tab_manager_.NativeView()];
    [content_view_ addSubview:sidebar_.NativeView()];
    [content_view_ addSubview:toolbar_.NativeView()];
    [NSLayoutConstraint activateConstraints:@[
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
      [[sidebar_.NativeView() topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                        constant:kSidebarTop],
      [[sidebar_.NativeView() bottomAnchor] constraintEqualToAnchor:[content_view_ bottomAnchor]
                                                           constant:-kSidebarBottom],
      [[toolbar_.NativeView() leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                            constant:kToolbarLeading],
      [[toolbar_.NativeView() topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                        constant:kToolbarTop],
      [[toolbar_.NativeView() trailingAnchor] constraintEqualToAnchor:[content_view_ trailingAnchor]
                                                             constant:-kToolbarTrailing],
    ]];
  }

  ~Impl() { [window_ close]; }

  void Show() { [window_ makeKeyAndOrderFront:nil]; }

 private:
  void ToggleBrowsingMode() {
    secure_mode_ = !secure_mode_;
    tab_manager_.SetBrowsingMode(secure_mode_ ? TabManager::BrowsingMode::kSecure
                                              : TabManager::BrowsingMode::kNormal);
  }

  void AddCurrentBookmark() { bookmark_manager_.AddBookmark(tab_manager_.CurrentUrl()); }

  void ApplyPageColor(Tab::PageColor color) {
    NSColor* page_color = [NSColor colorWithSRGBRed:color.red
                                             green:color.green
                                              blue:color.blue
                                             alpha:0.22 * color.alpha];
    [[content_view_ layer] setBackgroundColor:[page_color CGColor]];
  }

  BookmarkManager bookmark_manager_{BookmarkManager::DefaultDatabasePath()};
  HistoryManager history_manager_{HistoryManager::DefaultDatabasePath()};
  CookieManager cookie_manager_{CookieManager::DefaultDatabasePath()};
  DownloadManager download_manager_{DownloadManager::DefaultDatabasePath()};
  Sidebar sidebar_;
  TabManager tab_manager_{cookie_manager_, download_manager_};
  Toolbar toolbar_;
  NSWindow* window_ = nil;
  NSView* content_view_ = nil;
  bool secure_mode_ = false;
};

BrowserWindow::BrowserWindow() : impl_(std::make_unique<Impl>()) {}

BrowserWindow::~BrowserWindow() = default;

void BrowserWindow::Show() {
  impl_->Show();
}

}  // namespace briviba

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
#include <vector>

@interface BrivibaWindowControlBridge : NSObject <NSWindowDelegate> {
 @public
  std::function<void()> close_action;
  std::function<void()> minimize_action;
  std::function<void()> fullscreen_action;
  std::function<void()> fullscreen_enter_action;
  std::function<void()> fullscreen_exit_action;
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

@end

@interface BrivibaSettingsBridge : NSObject <NSWindowDelegate> {
 @public
  std::function<void(bool)> set_start_secure_action;
  std::function<void()> settings_closed_action;
}
- (void)toggleStartSecure:(id)sender;
@end

@implementation BrivibaSettingsBridge

- (void)toggleStartSecure:(id)sender {
  if (!set_start_secure_action || ![sender respondsToSelector:@selector(state)]) {
    return;
  }
  set_start_secure_action([sender state] == NSControlStateValueOn);
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
constexpr CGFloat kFullscreenSidebarTop = -kWebViewTop;
constexpr double kColorEpsilon = 0.002;
constexpr const char* kDefaultStartUrl = "https://duckduckgo.com";

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
    [window_ setDelegate:window_control_bridge_];
    settings_bridge_ = [[BrivibaSettingsBridge alloc] init];
    settings_bridge_->set_start_secure_action = [this](bool value) {
      settings_manager_.SetStartWithSecureMode(value);
    };
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
    sidebar_.SetSettingsAction([this] { ShowSettingsWindow(); });
    sidebar_.SetSelectTabAction([this](size_t index) { tab_manager_.SelectTab(index); });
    sidebar_.SetCloseTabAction([this](size_t index) { tab_manager_.CloseTab(index); });
    sidebar_.SetReloadTabAction([this](size_t index) { ReloadTab(index); });
    sidebar_.SetEditTabAddressAction([this](size_t index) { ShowAddressEditor(index); });
    tab_manager_.SetNavigationStateCallback(
        [this](bool can_go_back, bool can_go_forward, const std::string& url,
               const std::string& title, const std::string& favicon_url) {
          (void)favicon_url;
          (void)can_go_back;
          (void)can_go_forward;
          (void)title;
          if (!secure_mode_) {
            history_manager_.RecordVisit(url);
          }
        });
    tab_manager_.SetPageColorCallback([this](Tab::PageColor color) { ApplyPageColor(color); });
    tab_manager_.SetTabStateCallback([this](const std::vector<TabManager::TabState>& tabs,
                                            size_t active_index) {
      std::vector<Sidebar::TabState> sidebar_tabs;
      sidebar_tabs.reserve(tabs.size());
      for (const auto& tab : tabs) {
        sidebar_tabs.push_back(Sidebar::TabState{tab.url, tab.title, tab.favicon_url});
      }
      sidebar_.SetTabState(sidebar_tabs, active_index);
    });
    if (settings_manager_.StartWithSecureMode()) {
      secure_mode_ = true;
      tab_manager_.SetBrowsingMode(TabManager::BrowsingMode::kSecure);
    }
    tab_manager_.CreateInitialTab();
    traffic_light_stack_ = TrafficLightStack(window_control_bridge_);

    [content_view_ addSubview:chrome_background_];
    [content_view_ addSubview:tab_manager_.NativeView()];
    [content_view_ addSubview:sidebar_.NativeView()];
    [content_view_ addSubview:traffic_light_stack_];
    sidebar_top_constraint_ =
        [[sidebar_.NativeView() topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                          constant:kSidebarTop];
    [NSLayoutConstraint activateConstraints:@[
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
    ]];
    tab_manager_.LoadUrl(kDefaultStartUrl);
  }

  ~Impl() { [window_ close]; }

  void Show() {
    [window_ makeKeyAndOrderFront:nil];
  }

 private:
  void CreateNewTab() {
    tab_manager_.CreateTab();
    tab_manager_.LoadUrl(kDefaultStartUrl);
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

  void ToggleBrowsingMode() {
    secure_mode_ = !secure_mode_;
    tab_manager_.SetBrowsingMode(secure_mode_ ? TabManager::BrowsingMode::kSecure
                                              : TabManager::BrowsingMode::kNormal);
  }

  void AddCurrentBookmark() { bookmark_manager_.AddBookmark(tab_manager_.CurrentUrl()); }

  void CloseWindow() {
    [window_ close];
  }

  void MinimizeWindow() {
    [window_ miniaturize:nil];
  }

  void ToggleCustomFullscreen() {
    [window_ toggleFullScreen:nil];
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
      return;
    }

    settings_window_ = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0, 420.0, 220.0)
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

    NSTextField* title_label = [NSTextField labelWithString:@"Briviba Settings"];
    [title_label setFont:[NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold]];
    [title_label setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSTextField* privacy_label = [NSTextField labelWithString:@"Privacy"];
    [privacy_label setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
    [privacy_label setTextColor:[NSColor secondaryLabelColor]];
    [privacy_label setTranslatesAutoresizingMaskIntoConstraints:NO];

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

    [settings_view addSubview:title_label];
    [settings_view addSubview:privacy_label];
    [settings_view addSubview:start_secure_checkbox];
    [settings_view addSubview:start_secure_help];

    [NSLayoutConstraint activateConstraints:@[
      [[title_label leadingAnchor] constraintEqualToAnchor:[settings_view leadingAnchor]
                                                  constant:24.0],
      [[title_label topAnchor] constraintEqualToAnchor:[settings_view topAnchor] constant:22.0],
      [[privacy_label leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[privacy_label topAnchor] constraintEqualToAnchor:[title_label bottomAnchor]
                                                constant:28.0],
      [[start_secure_checkbox leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[start_secure_checkbox topAnchor] constraintEqualToAnchor:[privacy_label bottomAnchor]
                                                        constant:12.0],
      [[start_secure_help leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
      [[start_secure_help topAnchor] constraintEqualToAnchor:[start_secure_checkbox bottomAnchor]
                                                   constant:8.0],
      [[start_secure_help trailingAnchor] constraintEqualToAnchor:[settings_view trailingAnchor]
                                                         constant:-24.0],
    ]];

    [settings_window_ makeKeyAndOrderFront:nil];
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
  NSStackView* traffic_light_stack_ = nil;
  BrivibaWindowControlBridge* window_control_bridge_ = nil;
  BrivibaSettingsBridge* settings_bridge_ = nil;
  NSWindow* settings_window_ = nil;
  Tab::PageColor last_page_color_;
  bool secure_mode_ = false;
};

BrowserWindow::BrowserWindow() : impl_(std::make_unique<Impl>()) {}

BrowserWindow::~BrowserWindow() = default;

void BrowserWindow::Show() {
  impl_->Show();
}

}  // namespace briviba

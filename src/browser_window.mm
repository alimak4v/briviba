#include "briviba/browser_window.h"

#include "briviba/sidebar.h"

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

    [content_view_ addSubview:sidebar_.NativeView()];
    [NSLayoutConstraint activateConstraints:@[
      [[sidebar_.NativeView() leadingAnchor] constraintEqualToAnchor:[content_view_ leadingAnchor]
                                                            constant:kSidebarLeading],
      [[sidebar_.NativeView() topAnchor] constraintEqualToAnchor:[content_view_ topAnchor]
                                                        constant:kSidebarTop],
      [[sidebar_.NativeView() bottomAnchor] constraintEqualToAnchor:[content_view_ bottomAnchor]
                                                           constant:-kSidebarBottom],
    ]];
  }

  ~Impl() { [window_ close]; }

  void Show() { [window_ makeKeyAndOrderFront:nil]; }

 private:
  Sidebar sidebar_;
  NSWindow* window_ = nil;
  NSView* content_view_ = nil;
};

BrowserWindow::BrowserWindow() : impl_(std::make_unique<Impl>()) {}

BrowserWindow::~BrowserWindow() = default;

void BrowserWindow::Show() {
  impl_->Show();
}

}  // namespace briviba

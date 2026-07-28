#include "briviba/browser_window.h"

#import <AppKit/AppKit.h>

#include <algorithm>

namespace briviba {
namespace {

constexpr CGFloat kInitialWidth = 1180.0;
constexpr CGFloat kInitialHeight = 760.0;
constexpr CGFloat kVisibleFrameScale = 0.88;

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

    NSView* content_view = [[NSView alloc] initWithFrame:[[window_ contentView] bounds]];
    [content_view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content_view setWantsLayer:YES];
    [[content_view layer] setBackgroundColor:[[NSColor windowBackgroundColor] CGColor]];
    [window_ setContentView:content_view];
  }

  ~Impl() { [window_ close]; }

  void Show() { [window_ makeKeyAndOrderFront:nil]; }

 private:
  NSWindow* window_ = nil;
};

BrowserWindow::BrowserWindow() : impl_(std::make_unique<Impl>()) {}

BrowserWindow::~BrowserWindow() = default;

void BrowserWindow::Show() {
  impl_->Show();
}

}  // namespace briviba

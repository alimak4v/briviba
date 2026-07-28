#include "briviba/sidebar.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

namespace briviba {
namespace {

constexpr CGFloat kSidebarWidth = 64.0;
constexpr CGFloat kSidebarCornerRadius = 18.0;
constexpr CGFloat kIconButtonSize = 38.0;
constexpr CGFloat kStackSpacing = 12.0;

NSButton* IconButton(NSString* symbol_name, NSString* accessibility_label) {
  NSImage* image = [NSImage imageWithSystemSymbolName:symbol_name
                             accessibilityDescription:accessibility_label];
  NSButton* button = [NSButton buttonWithImage:image target:nil action:nil];
  [button setBordered:NO];
  [button setBezelStyle:NSBezelStyleRegularSquare];
  [button setImagePosition:NSImageOnly];
  [button setFocusRingType:NSFocusRingTypeNone];
  [button setAccessibilityLabel:accessibility_label];
  [button setTranslatesAutoresizingMaskIntoConstraints:NO];
  [[button widthAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  [[button heightAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  return button;
}

NSStackView* VerticalStack() {
  NSStackView* stack = [[NSStackView alloc] init];
  [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
  [stack setAlignment:NSLayoutAttributeCenterX];
  [stack setDistribution:NSStackViewDistributionGravityAreas];
  [stack setSpacing:kStackSpacing];
  [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
  return stack;
}

}  // namespace

class Sidebar::Impl {
 public:
  Impl() {
    view_ = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [view_ setMaterial:NSVisualEffectMaterialSidebar];
    [view_ setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [view_ setState:NSVisualEffectStateActive];
    [view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [view_ setWantsLayer:YES];
    [[view_ layer] setCornerRadius:kSidebarCornerRadius];
    [[view_ layer] setMasksToBounds:YES];

    NSStackView* top_stack = VerticalStack();
    [top_stack addArrangedSubview:IconButton(@"square.stack.3d.up", @"Tabs")];
    [top_stack addArrangedSubview:IconButton(@"plus", @"New tab")];

    NSStackView* bottom_stack = VerticalStack();
    [bottom_stack addArrangedSubview:IconButton(@"gearshape", @"Settings")];

    [view_ addSubview:top_stack];
    [view_ addSubview:bottom_stack];

    [NSLayoutConstraint activateConstraints:@[
      [[view_ widthAnchor] constraintEqualToConstant:kSidebarWidth],
      [[top_stack topAnchor] constraintEqualToAnchor:[view_ topAnchor] constant:24.0],
      [[top_stack centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
      [[bottom_stack bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor] constant:-20.0],
      [[bottom_stack centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
    ]];
  }

  NSView* NativeView() const { return view_; }

 private:
  NSVisualEffectView* view_ = nil;
};

Sidebar::Sidebar() : impl_(std::make_unique<Impl>()) {}

Sidebar::~Sidebar() = default;

NSView* Sidebar::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

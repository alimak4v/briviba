#include "briviba/sidebar.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <utility>

@interface BrivibaSidebarActionBridge : NSObject {
 @public
  briviba::Sidebar::Action new_tab_action;
  briviba::Sidebar::Action settings_action;
}
- (void)newTab:(id)sender;
- (void)openSettings:(id)sender;
@end

@implementation BrivibaSidebarActionBridge

- (void)newTab:(id)sender {
  (void)sender;
  if (new_tab_action) {
    new_tab_action();
  }
}

- (void)openSettings:(id)sender {
  (void)sender;
  if (settings_action) {
    settings_action();
  }
}

@end

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
    bridge_ = [[BrivibaSidebarActionBridge alloc] init];

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
    new_tab_button_ = IconButton(@"plus", @"New tab");
    [new_tab_button_ setTarget:bridge_];
    [new_tab_button_ setAction:@selector(newTab:)];
    [top_stack addArrangedSubview:new_tab_button_];

    NSStackView* bottom_stack = VerticalStack();
    settings_button_ = IconButton(@"gearshape", @"Settings");
    [settings_button_ setTarget:bridge_];
    [settings_button_ setAction:@selector(openSettings:)];
    [bottom_stack addArrangedSubview:settings_button_];

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

  void SetNewTabAction(Action action) { bridge_->new_tab_action = std::move(action); }

  void SetSettingsAction(Action action) { bridge_->settings_action = std::move(action); }

  NSView* NativeView() const { return view_; }

 private:
  BrivibaSidebarActionBridge* bridge_ = nil;
  NSButton* new_tab_button_ = nil;
  NSButton* settings_button_ = nil;
  NSVisualEffectView* view_ = nil;
};

Sidebar::Sidebar() : impl_(std::make_unique<Impl>()) {}

Sidebar::~Sidebar() = default;

void Sidebar::SetNewTabAction(Action action) {
  impl_->SetNewTabAction(std::move(action));
}

void Sidebar::SetSettingsAction(Action action) {
  impl_->SetSettingsAction(std::move(action));
}

NSView* Sidebar::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

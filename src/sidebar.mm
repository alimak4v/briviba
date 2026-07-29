#include "briviba/sidebar.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <cstddef>
#include <utility>

@interface BrivibaSidebarActionBridge : NSObject {
 @public
  briviba::Sidebar::Action new_tab_action;
  briviba::Sidebar::Action settings_action;
  briviba::Sidebar::SelectTabAction select_tab_action;
}
- (void)newTab:(id)sender;
- (void)openSettings:(id)sender;
- (void)selectTab:(id)sender;
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

- (void)selectTab:(id)sender {
  if (!select_tab_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  select_tab_action(static_cast<size_t>([sender tag]));
}

@end

namespace briviba {
namespace {

constexpr CGFloat kSidebarWidth = 86.0;
constexpr CGFloat kSidebarCornerRadius = 0.0;
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
  [button setWantsLayer:YES];
  [[button layer] setCornerRadius:kIconButtonSize / 2.0];
  [[button widthAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  [[button heightAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  return button;
}

NSButton* TabButton(size_t index, bool active, id target) {
  NSString* symbol_name = active ? @"circle.inset.filled" : @"circle";
  NSString* label = [NSString stringWithFormat:@"Tab %zu", index + 1];
  NSButton* button = IconButton(symbol_name, label);
  [button setTarget:target];
  [button setAction:@selector(selectTab:)];
  [button setTag:static_cast<NSInteger>(index)];
  [button setContentTintColor:[NSColor colorWithWhite:0.1 alpha:active ? 0.94 : 0.42]];
  if (active) {
    [[button layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.58] CGColor]];
    [[button layer] setBorderColor:[[NSColor colorWithWhite:0.0 alpha:0.10] CGColor]];
    [[button layer] setBorderWidth:1.0];
  }
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

    top_stack_ = VerticalStack();
    [top_stack_ addArrangedSubview:IconButton(@"square.stack.3d.up", @"Tabs")];
    tab_stack_ = VerticalStack();
    [top_stack_ addArrangedSubview:tab_stack_];
    new_tab_button_ = IconButton(@"plus", @"New tab");
    [new_tab_button_ setTarget:bridge_];
    [new_tab_button_ setAction:@selector(newTab:)];
    [top_stack_ addArrangedSubview:new_tab_button_];

    NSStackView* bottom_stack = VerticalStack();
    settings_button_ = IconButton(@"gearshape", @"Settings");
    [settings_button_ setTarget:bridge_];
    [settings_button_ setAction:@selector(openSettings:)];
    [bottom_stack addArrangedSubview:settings_button_];

    [view_ addSubview:top_stack_];
    [view_ addSubview:bottom_stack];

    [NSLayoutConstraint activateConstraints:@[
      [[view_ widthAnchor] constraintEqualToConstant:kSidebarWidth],
      [[top_stack_ topAnchor] constraintEqualToAnchor:[view_ topAnchor] constant:86.0],
      [[top_stack_ centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
      [[bottom_stack bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor] constant:-20.0],
      [[bottom_stack centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
    ]];
  }

  void SetNewTabAction(Action action) { bridge_->new_tab_action = std::move(action); }

  void SetSettingsAction(Action action) { bridge_->settings_action = std::move(action); }

  void SetSelectTabAction(SelectTabAction action) { bridge_->select_tab_action = std::move(action); }

  void SetTabState(size_t tab_count, size_t active_index) {
    for (NSView* subview in [[tab_stack_ arrangedSubviews] copy]) {
      [tab_stack_ removeArrangedSubview:subview];
      [subview removeFromSuperview];
    }

    for (size_t index = 0; index < tab_count; ++index) {
      [tab_stack_ addArrangedSubview:TabButton(index, index == active_index, bridge_)];
    }
  }

  NSView* NativeView() const { return view_; }

 private:
  BrivibaSidebarActionBridge* bridge_ = nil;
  NSStackView* top_stack_ = nil;
  NSStackView* tab_stack_ = nil;
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

void Sidebar::SetSelectTabAction(SelectTabAction action) {
  impl_->SetSelectTabAction(std::move(action));
}

void Sidebar::SetTabState(size_t tab_count, size_t active_index) {
  impl_->SetTabState(tab_count, active_index);
}

NSView* Sidebar::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

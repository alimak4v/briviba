#include "briviba/sidebar.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
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

constexpr CGFloat kSidebarWidth = 96.0;
constexpr CGFloat kDockWidth = 64.0;
constexpr CGFloat kDockTop = 58.0;
constexpr CGFloat kDockBottom = 18.0;
constexpr CGFloat kSidebarCornerRadius = 15.0;
constexpr CGFloat kIconButtonSize = 34.0;
constexpr CGFloat kStackSpacing = 12.0;
constexpr size_t kReferenceTabSlots = 4;

NSColor* DockIconTintColor() {
  return [NSColor colorWithWhite:0.04 alpha:0.86];
}

NSButton* IconButton(NSString* symbol_name, NSString* accessibility_label) {
  NSImage* image = [NSImage imageWithSystemSymbolName:symbol_name
                             accessibilityDescription:accessibility_label];
  NSButton* button = [NSButton buttonWithImage:image target:nil action:nil];
  [button setBordered:NO];
  [button setBezelStyle:NSBezelStyleRegularSquare];
  [button setImagePosition:NSImageOnly];
  [button setContentTintColor:DockIconTintColor()];
  [button setFocusRingType:NSFocusRingTypeNone];
  [button setAccessibilityLabel:accessibility_label];
  [button setTranslatesAutoresizingMaskIntoConstraints:NO];
  [button setWantsLayer:YES];
  [[button layer] setCornerRadius:kIconButtonSize / 2.0];
  [[button widthAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  [[button heightAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  return button;
}

NSButton* BaseTabButton(size_t index, bool enabled, bool active, id target) {
  NSButton* button = [NSButton buttonWithTitle:@"" target:enabled ? target : nil action:nil];
  [button setBordered:NO];
  [button setBezelStyle:NSBezelStyleRegularSquare];
  [button setFocusRingType:NSFocusRingTypeNone];
  [button setTranslatesAutoresizingMaskIntoConstraints:NO];
  [button setWantsLayer:YES];
  [[button layer] setCornerRadius:kIconButtonSize / 2.0];
  [[button layer] setMasksToBounds:YES];
  if (active) {
    [[button layer] setShadowColor:[[NSColor blackColor] CGColor]];
    [[button layer] setShadowOpacity:0.12F];
    [[button layer] setShadowRadius:8.0];
    [[button layer] setShadowOffset:CGSizeMake(0.0, -2.0)];
  }
  [[button widthAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  [[button heightAnchor] constraintEqualToConstant:kIconButtonSize].active = YES;
  [button setTag:static_cast<NSInteger>(index)];
  [button setEnabled:enabled];
  if (enabled) {
    [button setTarget:target];
    [button setAction:@selector(selectTab:)];
  }
  return button;
}

NSButton* RedPlayTabButton(size_t index, bool enabled, bool active, id target) {
  NSButton* button = BaseTabButton(index, enabled, active, target);
  NSImage* image = [NSImage imageWithSystemSymbolName:@"play.fill"
                             accessibilityDescription:@"Tab"];
  [button setImage:image];
  [button setImagePosition:NSImageOnly];
  [button setContentTintColor:[NSColor whiteColor]];
  [[button layer] setBackgroundColor:[[NSColor colorWithSRGBRed:1.0
                                                          green:0.04
                                                           blue:0.04
                                                          alpha:1.0] CGColor]];
  [[button layer] setCornerRadius:7.0];
  [[button layer] setBorderColor:[[NSColor colorWithWhite:1.0 alpha:0.42] CGColor]];
  [[button layer] setBorderWidth:1.0];
  return button;
}

NSButton* LetterTabButton(size_t index, NSString* title, bool enabled, bool active, id target) {
  NSButton* button = BaseTabButton(index, enabled, active, target);
  [button setTitle:title];
  NSFont* font = [NSFont fontWithName:@"Times New Roman" size:20.0];
  [button setFont:font == nil ? [NSFont systemFontOfSize:20.0 weight:NSFontWeightSemibold] : font];
  [button setContentTintColor:DockIconTintColor()];
  [[button layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:active ? 0.88 : 0.70]
                                          CGColor]];
  [[button layer] setBorderColor:[[NSColor colorWithWhite:1.0 alpha:0.55] CGColor]];
  [[button layer] setBorderWidth:1.0];
  return button;
}

NSButton* NumericTabButton(size_t index, bool enabled, bool active, id target) {
  NSString* title = [NSString stringWithFormat:@"%zu", index + 1];
  return LetterTabButton(index, title, enabled, active, target);
}

NSButton* TabButton(size_t index, bool enabled, bool active, id target) {
  if (index == 0) {
    return RedPlayTabButton(index, enabled, active, target);
  }
  if (index == 1) {
    return LetterTabButton(index, @"W", enabled, active, target);
  }
  if (index == 2) {
    return LetterTabButton(index, @"X", enabled, active, target);
  }
  if (index == 3) {
    return LetterTabButton(index, @"G", enabled, active, target);
  }
  return NumericTabButton(index, enabled, active, target);
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

    view_ = [[NSView alloc] initWithFrame:NSZeroRect];
    [view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [view_ setWantsLayer:YES];
    [[view_ layer] setBackgroundColor:[[NSColor colorWithSRGBRed:0.90
                                                           green:0.95
                                                            blue:1.0
                                                           alpha:0.34] CGColor]];

    dock_view_ = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [dock_view_ setMaterial:NSVisualEffectMaterialSidebar];
    [dock_view_ setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [dock_view_ setState:NSVisualEffectStateActive];
    [dock_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [dock_view_ setWantsLayer:YES];
    [[dock_view_ layer] setCornerRadius:kSidebarCornerRadius];
    [[dock_view_ layer] setMasksToBounds:YES];
    [[dock_view_ layer] setBorderColor:[[NSColor colorWithWhite:1.0 alpha:0.48] CGColor]];
    [[dock_view_ layer] setBorderWidth:1.0];
    [[dock_view_ layer] setShadowColor:[[NSColor blackColor] CGColor]];
    [[dock_view_ layer] setShadowOpacity:0.10F];
    [[dock_view_ layer] setShadowRadius:18.0];
    [[dock_view_ layer] setShadowOffset:CGSizeMake(0.0, -4.0)];

    top_stack_ = VerticalStack();
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
    [bottom_stack addArrangedSubview:IconButton(@"arrow.down.to.line", @"Downloads")];

    [view_ addSubview:dock_view_];
    [dock_view_ addSubview:top_stack_];
    [dock_view_ addSubview:bottom_stack];

    [NSLayoutConstraint activateConstraints:@[
      [[view_ widthAnchor] constraintEqualToConstant:kSidebarWidth],
      [[dock_view_ widthAnchor] constraintEqualToConstant:kDockWidth],
      [[dock_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor] constant:kDockTop],
      [[dock_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor] constant:-kDockBottom],
      [[dock_view_ centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
      [[top_stack_ topAnchor] constraintEqualToAnchor:[dock_view_ topAnchor] constant:18.0],
      [[top_stack_ centerXAnchor] constraintEqualToAnchor:[dock_view_ centerXAnchor]],
      [[bottom_stack bottomAnchor] constraintEqualToAnchor:[dock_view_ bottomAnchor] constant:-16.0],
      [[bottom_stack centerXAnchor] constraintEqualToAnchor:[dock_view_ centerXAnchor]],
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

    const size_t visible_count = std::max(tab_count, kReferenceTabSlots);
    for (size_t index = 0; index < visible_count; ++index) {
      [tab_stack_ addArrangedSubview:TabButton(index, index < tab_count, index == active_index, bridge_)];
    }
  }

  NSView* NativeView() const { return view_; }

 private:
  BrivibaSidebarActionBridge* bridge_ = nil;
  NSVisualEffectView* dock_view_ = nil;
  NSStackView* top_stack_ = nil;
  NSStackView* tab_stack_ = nil;
  NSButton* new_tab_button_ = nil;
  NSButton* settings_button_ = nil;
  NSView* view_ = nil;
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

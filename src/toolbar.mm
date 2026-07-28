#include "briviba/toolbar.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

namespace briviba {
namespace {

constexpr CGFloat kToolbarHeight = 42.0;
constexpr CGFloat kButtonSize = 38.0;
constexpr CGFloat kButtonRadius = kButtonSize / 2.0;
constexpr CGFloat kAddressWidth = 480.0;
constexpr CGFloat kAddressHeight = 38.0;
constexpr CGFloat kControlSpacing = 10.0;

NSColor* ControlFillColor() {
  return [NSColor colorWithWhite:1.0 alpha:0.72];
}

NSButton* CircularButton(NSString* symbol_name, NSString* accessibility_label) {
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
  [[button layer] setCornerRadius:kButtonRadius];
  [[button layer] setBackgroundColor:[ControlFillColor() CGColor]];
  [[button widthAnchor] constraintEqualToConstant:kButtonSize].active = YES;
  [[button heightAnchor] constraintEqualToConstant:kButtonSize].active = YES;
  return button;
}

NSSearchField* AddressField() {
  NSSearchField* field = [[NSSearchField alloc] initWithFrame:NSZeroRect];
  [field setPlaceholderString:@"Search or enter address"];
  [field setFocusRingType:NSFocusRingTypeNone];
  [field setBezeled:YES];
  [field setBordered:NO];
  [field setTranslatesAutoresizingMaskIntoConstraints:NO];
  [[field widthAnchor] constraintEqualToConstant:kAddressWidth].active = YES;
  [[field heightAnchor] constraintEqualToConstant:kAddressHeight].active = YES;
  return field;
}

}  // namespace

class Toolbar::Impl {
 public:
  Impl() {
    view_ = [[NSView alloc] initWithFrame:NSZeroRect];
    [view_ setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSButton* back_button = CircularButton(@"chevron.left", @"Back");
    NSButton* forward_button = CircularButton(@"chevron.right", @"Forward");
    NSButton* reload_button = CircularButton(@"arrow.clockwise", @"Reload");
    NSSearchField* address_field = AddressField();
    NSButton* menu_button = CircularButton(@"ellipsis", @"Menu");

    [view_ addSubview:back_button];
    [view_ addSubview:forward_button];
    [view_ addSubview:reload_button];
    [view_ addSubview:address_field];
    [view_ addSubview:menu_button];

    [NSLayoutConstraint activateConstraints:@[
      [[view_ heightAnchor] constraintEqualToConstant:kToolbarHeight],
      [[back_button leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[back_button centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[forward_button leadingAnchor] constraintEqualToAnchor:[back_button trailingAnchor]
                                                     constant:kControlSpacing],
      [[forward_button centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[reload_button leadingAnchor] constraintEqualToAnchor:[forward_button trailingAnchor]
                                                    constant:kControlSpacing],
      [[reload_button centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[address_field centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
      [[address_field centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[menu_button trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[menu_button centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
    ]];
  }

  NSView* NativeView() const { return view_; }

 private:
  NSView* view_ = nil;
};

Toolbar::Toolbar() : impl_(std::make_unique<Impl>()) {}

Toolbar::~Toolbar() = default;

NSView* Toolbar::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

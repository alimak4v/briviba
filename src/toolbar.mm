#include "briviba/toolbar.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <functional>
#include <string>
#include <utility>

@interface BrivibaToolbarActionBridge : NSObject {
 @public
  briviba::Toolbar::Action back_action;
  briviba::Toolbar::Action forward_action;
  briviba::Toolbar::Action reload_action;
  briviba::Toolbar::Action bookmark_action;
  briviba::Toolbar::Action menu_action;
  briviba::Toolbar::Action settings_action;
  briviba::Toolbar::AddressSubmitAction address_submit_action;
}
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)reload:(id)sender;
- (void)addBookmark:(id)sender;
- (void)openMenu:(id)sender;
- (void)toggleSecureMode:(id)sender;
- (void)openSettings:(id)sender;
- (void)submitAddress:(id)sender;
@end

@implementation BrivibaToolbarActionBridge

- (void)goBack:(id)sender {
  (void)sender;
  if (back_action) {
    back_action();
  }
}

- (void)goForward:(id)sender {
  (void)sender;
  if (forward_action) {
    forward_action();
  }
}

- (void)reload:(id)sender {
  (void)sender;
  if (reload_action) {
    reload_action();
  }
}

- (void)addBookmark:(id)sender {
  (void)sender;
  if (bookmark_action) {
    bookmark_action();
  }
}

- (void)openMenu:(id)sender {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Briviba"];
  NSMenuItem* bookmark_item = [[NSMenuItem alloc] initWithTitle:@"Add Bookmark"
                                                         action:@selector(addBookmark:)
                                                  keyEquivalent:@""];
  [bookmark_item setTarget:self];
  [bookmark_item setEnabled:bookmark_action != nullptr];
  [menu addItem:bookmark_item];

  NSMenuItem* secure_item = [[NSMenuItem alloc] initWithTitle:@"Toggle Secure Mode"
                                                       action:@selector(toggleSecureMode:)
                                                keyEquivalent:@""];
  [secure_item setTarget:self];
  [secure_item setEnabled:menu_action != nullptr];
  [menu addItem:secure_item];

  NSMenuItem* settings_item = [[NSMenuItem alloc] initWithTitle:@"Toggle Start Secure"
                                                         action:@selector(openSettings:)
                                                  keyEquivalent:@""];
  [settings_item setTarget:self];
  [settings_item setEnabled:settings_action != nullptr];
  [menu addItem:settings_item];

  if ([sender isKindOfClass:[NSView class]]) {
    [NSMenu popUpContextMenu:menu withEvent:[NSApp currentEvent] forView:(NSView*)sender];
  }
}

- (void)openSettings:(id)sender {
  (void)sender;
  if (settings_action) {
    settings_action();
  }
}

- (void)toggleSecureMode:(id)sender {
  (void)sender;
  if (menu_action) {
    menu_action();
  }
}

- (void)submitAddress:(id)sender {
  if (!address_submit_action || ![sender respondsToSelector:@selector(stringValue)]) {
    return;
  }

  NSString* value = [sender stringValue];
  const char* utf8 = [value UTF8String];
  address_submit_action(utf8 == nullptr ? std::string() : std::string(utf8));
}

@end

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
    bridge_ = [[BrivibaToolbarActionBridge alloc] init];

    view_ = [[NSView alloc] initWithFrame:NSZeroRect];
    [view_ setTranslatesAutoresizingMaskIntoConstraints:NO];

    back_button_ = CircularButton(@"chevron.left", @"Back");
    forward_button_ = CircularButton(@"chevron.right", @"Forward");
    reload_button_ = CircularButton(@"arrow.clockwise", @"Reload");
    address_field_ = AddressField();
    menu_button_ = CircularButton(@"ellipsis", @"Menu");

    [back_button_ setTarget:bridge_];
    [back_button_ setAction:@selector(goBack:)];
    [forward_button_ setTarget:bridge_];
    [forward_button_ setAction:@selector(goForward:)];
    [reload_button_ setTarget:bridge_];
    [reload_button_ setAction:@selector(reload:)];
    [address_field_ setTarget:bridge_];
    [address_field_ setAction:@selector(submitAddress:)];

    [back_button_ setEnabled:NO];
    [forward_button_ setEnabled:NO];

    [view_ addSubview:back_button_];
    [view_ addSubview:forward_button_];
    [view_ addSubview:reload_button_];
    [view_ addSubview:address_field_];
    [menu_button_ setTarget:bridge_];
    [menu_button_ setAction:@selector(openMenu:)];

    [view_ addSubview:menu_button_];

    [NSLayoutConstraint activateConstraints:@[
      [[view_ heightAnchor] constraintEqualToConstant:kToolbarHeight],
      [[back_button_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[back_button_ centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[forward_button_ leadingAnchor] constraintEqualToAnchor:[back_button_ trailingAnchor]
                                                      constant:kControlSpacing],
      [[forward_button_ centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[reload_button_ leadingAnchor] constraintEqualToAnchor:[forward_button_ trailingAnchor]
                                                     constant:kControlSpacing],
      [[reload_button_ centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[address_field_ centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
      [[address_field_ centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
      [[menu_button_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[menu_button_ centerYAnchor] constraintEqualToAnchor:[view_ centerYAnchor]],
    ]];
  }

  void SetBackAction(Action action) { bridge_->back_action = std::move(action); }

  void SetForwardAction(Action action) { bridge_->forward_action = std::move(action); }

  void SetReloadAction(Action action) { bridge_->reload_action = std::move(action); }

  void SetBookmarkAction(Action action) { bridge_->bookmark_action = std::move(action); }

  void SetMenuAction(Action action) { bridge_->menu_action = std::move(action); }

  void SetSettingsAction(Action action) { bridge_->settings_action = std::move(action); }

  void SetAddressSubmitAction(AddressSubmitAction action) {
    bridge_->address_submit_action = std::move(action);
  }

  void SetAddressText(const std::string& text) {
    [address_field_ setStringValue:[NSString stringWithUTF8String:text.c_str()]];
  }

  void SetNavigationState(bool can_go_back, bool can_go_forward) {
    [back_button_ setEnabled:can_go_back];
    [forward_button_ setEnabled:can_go_forward];
  }

  NSView* NativeView() const { return view_; }

 private:
  BrivibaToolbarActionBridge* bridge_ = nil;
  NSButton* back_button_ = nil;
  NSButton* forward_button_ = nil;
  NSButton* reload_button_ = nil;
  NSButton* menu_button_ = nil;
  NSSearchField* address_field_ = nil;
  NSView* view_ = nil;
};

Toolbar::Toolbar() : impl_(std::make_unique<Impl>()) {}

Toolbar::~Toolbar() = default;

void Toolbar::SetBackAction(Action action) {
  impl_->SetBackAction(std::move(action));
}

void Toolbar::SetForwardAction(Action action) {
  impl_->SetForwardAction(std::move(action));
}

void Toolbar::SetReloadAction(Action action) {
  impl_->SetReloadAction(std::move(action));
}

void Toolbar::SetBookmarkAction(Action action) {
  impl_->SetBookmarkAction(std::move(action));
}

void Toolbar::SetMenuAction(Action action) {
  impl_->SetMenuAction(std::move(action));
}

void Toolbar::SetSettingsAction(Action action) {
  impl_->SetSettingsAction(std::move(action));
}

void Toolbar::SetAddressSubmitAction(AddressSubmitAction action) {
  impl_->SetAddressSubmitAction(std::move(action));
}

void Toolbar::SetAddressText(const std::string& text) {
  impl_->SetAddressText(text);
}

void Toolbar::SetNavigationState(bool can_go_back, bool can_go_forward) {
  impl_->SetNavigationState(can_go_back, can_go_forward);
}

NSView* Toolbar::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

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

  NSMenuItem* settings_item = [[NSMenuItem alloc] initWithTitle:@"Settings..."
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

@interface BrivibaCircularButton : NSButton
@end

@implementation BrivibaCircularButton

- (NSSize)intrinsicContentSize {
  return NSMakeSize(36.0, 36.0);
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect bounds = [self bounds];
  const CGFloat diameter = MIN(bounds.size.width, bounds.size.height);
  NSRect circle_rect =
      NSMakeRect(NSMidX(bounds) - diameter / 2.0, NSMidY(bounds) - diameter / 2.0, diameter,
                 diameter);

  NSBezierPath* circle = [NSBezierPath bezierPathWithOvalInRect:circle_rect];
  [[NSColor colorWithWhite:1.0 alpha:[self isEnabled] ? 0.82 : 0.58] setFill];
  [circle fill];
  [[NSColor colorWithWhite:0.0 alpha:0.10] setStroke];
  [circle setLineWidth:1.0];
  [circle stroke];

  NSImage* image = [self image];
  if (image != nil) {
    NSRect image_rect = NSInsetRect(circle_rect, 10.0, 10.0);
    [image drawInRect:image_rect
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:[self isEnabled] ? 0.92 : 0.36
       respectFlipped:YES
                hints:nil];
    return;
  }

  NSString* title = [self title];
  if ([title length] == 0) {
    return;
  }

  NSDictionary* attributes = @{
    NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold],
    NSForegroundColorAttributeName : [NSColor colorWithWhite:0.14 alpha:0.94]
  };
  NSSize text_size = [title sizeWithAttributes:attributes];
  [title drawAtPoint:NSMakePoint(NSMidX(circle_rect) - text_size.width / 2.0,
                                 NSMidY(circle_rect) - text_size.height / 2.0)
      withAttributes:attributes];
}

@end

@interface BrivibaAddressField : NSTextField {
 @private
  NSString* display_text_;
  NSString* editing_text_;
}
- (void)setDisplayText:(NSString*)displayText editingText:(NSString*)editingText;
@end

@implementation BrivibaAddressField

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    display_text_ = @"";
    editing_text_ = @"";
    [self setEditable:NO];
  }
  return self;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect bounds = [self bounds];
  NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:18.0 yRadius:18.0];
  [[NSColor colorWithWhite:1.0 alpha:0.78] setFill];
  [path fill];
  [[NSColor colorWithWhite:0.0 alpha:0.10] setStroke];
  [path setLineWidth:1.0];
  [path stroke];

  if ([self isEditable] || [self currentEditor] != nil) {
    return;
  }

  NSString* text = [[self stringValue] length] == 0 ? [self placeholderString] : [self stringValue];
  if ([text length] == 0) {
    return;
  }

  NSMutableParagraphStyle* paragraph_style = [[NSMutableParagraphStyle alloc] init];
  [paragraph_style setAlignment:NSTextAlignmentCenter];
  NSFont* font = [self font] == nil ? [NSFont systemFontOfSize:14.0] : [self font];
  NSColor* text_color = [self textColor] == nil ? [NSColor labelColor] : [self textColor];
  NSDictionary* attributes = @{
    NSFontAttributeName : font,
    NSForegroundColorAttributeName : text_color,
    NSParagraphStyleAttributeName : paragraph_style
  };
  NSSize text_size = [text sizeWithAttributes:attributes];
  NSRect text_rect =
      NSMakeRect(12.0, NSMidY(bounds) - text_size.height / 2.0 - 0.5,
                 bounds.size.width - 24.0, text_size.height);
  [text drawInRect:text_rect withAttributes:attributes];
}

- (void)mouseDown:(NSEvent*)event {
  (void)event;
  [self setEditable:YES];
  [self setStringValue:editing_text_ == nil ? @"" : editing_text_];
  [self setNeedsDisplay:YES];
  [[self window] makeFirstResponder:self];
  [self selectText:nil];
}

- (void)textDidEndEditing:(NSNotification*)notification {
  (void)notification;
  [self setEditable:NO];
  [self setStringValue:display_text_ == nil ? @"" : display_text_];
  [self setNeedsDisplay:YES];
}

- (void)setDisplayText:(NSString*)displayText editingText:(NSString*)editingText {
  display_text_ = [displayText copy];
  editing_text_ = [editingText copy];
  if (![self isEditable]) {
    [self setStringValue:display_text_ == nil ? @"" : display_text_];
  }
  [self setNeedsDisplay:YES];
}

@end

namespace briviba {
namespace {

constexpr CGFloat kToolbarHeight = 40.0;
constexpr CGFloat kButtonSize = 36.0;
constexpr CGFloat kAddressWidth = 540.0;
constexpr CGFloat kAddressHeight = 36.0;
constexpr CGFloat kControlSpacing = 10.0;
constexpr CGFloat kAddressCenterOffset = -54.0;

NSButton* CircularButton(NSString* symbol_name, NSString* accessibility_label) {
  NSImage* image = [NSImage imageWithSystemSymbolName:symbol_name
                             accessibilityDescription:accessibility_label];
  NSButton* button = [[BrivibaCircularButton alloc] initWithFrame:NSZeroRect];
  [button setImage:image];
  [button setBordered:NO];
  [button setBezelStyle:NSBezelStyleRegularSquare];
  [button setButtonType:NSButtonTypeMomentaryChange];
  [button setImagePosition:NSImageOnly];
  [button setContentTintColor:[NSColor colorWithWhite:0.16 alpha:0.92]];
  [button setFocusRingType:NSFocusRingTypeNone];
  [button setAccessibilityLabel:accessibility_label];
  [button setTranslatesAutoresizingMaskIntoConstraints:NO];
  [[button widthAnchor] constraintEqualToConstant:kButtonSize].active = YES;
  [[button heightAnchor] constraintEqualToConstant:kButtonSize].active = YES;
  return button;
}

std::string StringFromNSString(NSString* value) {
  const char* utf8 = [value UTF8String];
  return utf8 == nullptr ? std::string() : std::string(utf8);
}

std::string HostFromUrl(const std::string& url) {
  NSString* url_string = [NSString stringWithUTF8String:url.c_str()];
  NSURL* parsed_url = [NSURL URLWithString:url_string];
  NSString* host = [parsed_url host];
  if (host == nil || [host length] == 0) {
    return url;
  }
  return StringFromNSString(host);
}

std::string DisplayTextForPage(const std::string& url, const std::string& title) {
  (void)title;
  return HostFromUrl(url);
}

NSTextField* AddressField() {
  BrivibaAddressField* field = [[BrivibaAddressField alloc] initWithFrame:NSZeroRect];
  [field setPlaceholderString:@"Search DuckDuckGo or enter address"];
  [field setFocusRingType:NSFocusRingTypeNone];
  [field setBezeled:NO];
  [field setBordered:NO];
  [field setDrawsBackground:NO];
  [field setFont:[NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular]];
  [field setTextColor:[NSColor colorWithWhite:0.12 alpha:1.0]];
  [field setAlignment:NSTextAlignmentCenter];
  [field setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [field setUsesSingleLineMode:YES];
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
      [[address_field_ centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]
                                                      constant:kAddressCenterOffset],
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

  void SetPageIdentity(const std::string& url, const std::string& title) {
    current_url_ = url;
    current_title_ = title;
    NSString* display_text =
        [NSString stringWithUTF8String:DisplayTextForPage(current_url_, current_title_).c_str()];
    NSString* editing_text = [NSString stringWithUTF8String:current_url_.c_str()];
    [(BrivibaAddressField*)address_field_ setDisplayText:display_text editingText:editing_text];
  }

  void SetNavigationState(bool can_go_back, bool can_go_forward) {
    [back_button_ setEnabled:can_go_back];
    [forward_button_ setEnabled:can_go_forward];
  }

  NSView* NativeView() const { return view_; }

  NSView* AddressFieldNativeView() const { return address_field_; }

 private:
  BrivibaToolbarActionBridge* bridge_ = nil;
  NSButton* back_button_ = nil;
  NSButton* forward_button_ = nil;
  NSButton* reload_button_ = nil;
  NSButton* menu_button_ = nil;
  NSTextField* address_field_ = nil;
  NSView* view_ = nil;
  std::string current_url_;
  std::string current_title_;
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

void Toolbar::SetPageIdentity(const std::string& url, const std::string& title) {
  impl_->SetPageIdentity(url, title);
}

void Toolbar::SetNavigationState(bool can_go_back, bool can_go_forward) {
  impl_->SetNavigationState(can_go_back, can_go_forward);
}

NSView* Toolbar::NativeView() const {
  return impl_->NativeView();
}

NSView* Toolbar::AddressFieldNativeView() const {
  return impl_->AddressFieldNativeView();
}

}  // namespace briviba

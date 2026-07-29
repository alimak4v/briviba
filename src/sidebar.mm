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
  briviba::Sidebar::CloseTabAction close_tab_action;
}
- (void)newTab:(id)sender;
- (void)openSettings:(id)sender;
- (void)selectTab:(id)sender;
- (void)closeTab:(id)sender;
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

- (void)closeTab:(id)sender {
  if (!close_tab_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  close_tab_action(static_cast<size_t>([sender tag]));
}

@end

@interface BrivibaSidebarTabItemView : NSView
@property(nonatomic, strong) NSButton* closeButton;
@property(nonatomic) BOOL closeEnabled;
@end

@implementation BrivibaSidebarTabItemView {
  NSTrackingArea* tracking_area_;
}

- (void)updateTrackingAreas {
  if (tracking_area_ != nil) {
    [self removeTrackingArea:tracking_area_];
  }

  NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp |
                                  NSTrackingInVisibleRect;
  tracking_area_ = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                options:options
                                                  owner:self
                                               userInfo:nil];
  [self addTrackingArea:tracking_area_];
  [super updateTrackingAreas];
}

- (void)setCloseButton:(NSButton*)closeButton {
  _closeButton = closeButton;
  [self updateCloseButtonVisibility:NO];
}

- (void)mouseEntered:(NSEvent*)event {
  (void)event;
  [self updateCloseButtonVisibility:YES];
}

- (void)mouseExited:(NSEvent*)event {
  (void)event;
  [self updateCloseButtonVisibility:NO];
}

- (void)updateCloseButtonVisibility:(BOOL)visible {
  if (_closeButton == nil) {
    return;
  }
  [_closeButton setHidden:!(_closeEnabled && visible)];
}

@end

namespace briviba {
namespace {

constexpr CGFloat kSidebarWidth = 96.0;
constexpr CGFloat kDockWidth = 64.0;
constexpr CGFloat kDockTop = 50.0;
constexpr CGFloat kDockBottom = 14.0;
constexpr CGFloat kSidebarCornerRadius = 15.0;
constexpr CGFloat kIconButtonSize = 34.0;
constexpr CGFloat kActiveTabButtonSize = 44.0;
constexpr CGFloat kStackSpacing = 10.0;

NSColor* DockIconTintColor() {
  return [NSColor colorWithWhite:0.06 alpha:0.78];
}

NSString* StringFromStdString(const std::string& value) {
  return [NSString stringWithUTF8String:value.c_str()];
}

NSString* HostFromUrl(const std::string& url) {
  NSURL* parsed_url = [NSURL URLWithString:StringFromStdString(url)];
  NSString* host = [[parsed_url host] lowercaseString];
  return host == nil || [host length] == 0 ? StringFromStdString(url) : host;
}

NSString* FallbackTabLabel(const Sidebar::TabState& tab) {
  NSString* source = tab.title.empty() ? HostFromUrl(tab.url) : StringFromStdString(tab.title);
  NSString* trimmed =
      [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return @"?";
  }
  return [[trimmed substringToIndex:1] uppercaseString];
}

NSImage* FallbackTabImage(NSString* label, bool active, bool enabled) {
  constexpr CGFloat kImageSize = 30.0;
  NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(kImageSize, kImageSize)];
  [image lockFocus];

  NSRect rect = NSMakeRect(0.0, 0.0, kImageSize, kImageSize);
  NSBezierPath* circle = [NSBezierPath bezierPathWithOvalInRect:rect];
  [[NSColor colorWithWhite:1.0 alpha:active ? 0.96 : 0.78] setFill];
  [circle fill];
  [[NSColor colorWithWhite:0.0 alpha:0.08] setStroke];
  [circle setLineWidth:1.0];
  [circle stroke];

  NSFont* font = [NSFont fontWithName:@"Times New Roman" size:20.0];
  NSDictionary* attributes = @{
    NSFontAttributeName : font == nil ? [NSFont systemFontOfSize:20.0
                                                          weight:NSFontWeightSemibold]
                                      : font,
    NSForegroundColorAttributeName : [NSColor colorWithWhite:0.10 alpha:enabled ? 0.72 : 0.36]
  };
  NSSize text_size = [label sizeWithAttributes:attributes];
  [label drawAtPoint:NSMakePoint((kImageSize - text_size.width) / 2.0,
                                 (kImageSize - text_size.height) / 2.0 - 1.0)
      withAttributes:attributes];

  [image unlockFocus];
  return image;
}

NSImage* SiteTabImage(const Sidebar::TabState& tab, bool active, bool enabled) {
  if (!tab.favicon_url.empty()) {
    NSURL* favicon_url = [NSURL URLWithString:StringFromStdString(tab.favicon_url)];
    NSImage* favicon = favicon_url == nil ? nil : [[NSImage alloc] initWithContentsOfURL:favicon_url];
    if (favicon != nil) {
      [favicon setSize:NSMakeSize(28.0, 28.0)];
      return favicon;
    }
  }
  return FallbackTabImage(FallbackTabLabel(tab), active, enabled);
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
  const CGFloat size = active ? kActiveTabButtonSize : kIconButtonSize;
  [[button layer] setCornerRadius:active ? 14.0 : size / 2.0];
  [[button layer] setMasksToBounds:NO];
  if (active) {
    [[button layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.76] CGColor]];
    [[button layer] setBorderColor:[[NSColor colorWithWhite:1.0 alpha:0.62] CGColor]];
    [[button layer] setBorderWidth:1.0];
    [[button layer] setShadowColor:[[NSColor blackColor] CGColor]];
    [[button layer] setShadowOpacity:0.10F];
    [[button layer] setShadowRadius:10.0];
    [[button layer] setShadowOffset:CGSizeMake(0.0, -2.0)];
  }
  [[button widthAnchor] constraintEqualToConstant:size].active = YES;
  [[button heightAnchor] constraintEqualToConstant:size].active = YES;
  [button setTag:static_cast<NSInteger>(index)];
  [button setEnabled:enabled];
  if (enabled) {
    [button setTarget:target];
    [button setAction:@selector(selectTab:)];
  }
  return button;
}

NSButton* SiteTabButton(size_t index, const Sidebar::TabState& tab, bool active, id target) {
  NSButton* button = BaseTabButton(index, true, active, target);
  [button setImage:SiteTabImage(tab, active, true)];
  [button setImagePosition:NSImageOnly];
  [button setImageScaling:NSImageScaleProportionallyDown];
  [button setToolTip:tab.title.empty() ? HostFromUrl(tab.url) : StringFromStdString(tab.title)];
  if (!active) {
    [[button layer] setBackgroundColor:[[NSColor clearColor] CGColor]];
    [[button layer] setBorderWidth:0.0];
  }
  return button;
}

NSButton* CloseTabButton(size_t index, id target) {
  NSImage* image = [NSImage imageWithSystemSymbolName:@"xmark"
                             accessibilityDescription:@"Close tab"];
  NSButton* button = [NSButton buttonWithImage:image target:target action:@selector(closeTab:)];
  [button setBordered:NO];
  [button setBezelStyle:NSBezelStyleRegularSquare];
  [button setImagePosition:NSImageOnly];
  [button setImageScaling:NSImageScaleProportionallyDown];
  [button setContentTintColor:[NSColor colorWithWhite:0.18 alpha:0.80]];
  [button setFocusRingType:NSFocusRingTypeNone];
  [button setAccessibilityLabel:@"Close tab"];
  [button setToolTip:@"Close tab"];
  [button setTag:static_cast<NSInteger>(index)];
  [button setTranslatesAutoresizingMaskIntoConstraints:NO];
  [button setWantsLayer:YES];
  [[button layer] setCornerRadius:8.0];
  [[button layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.86] CGColor]];
  [[button layer] setBorderColor:[[NSColor colorWithWhite:0.0 alpha:0.08] CGColor]];
  [[button layer] setBorderWidth:0.5];
  [[button widthAnchor] constraintEqualToConstant:16.0].active = YES;
  [[button heightAnchor] constraintEqualToConstant:16.0].active = YES;
  return button;
}

NSView* SiteTabItem(size_t index, const Sidebar::TabState& tab, bool active, bool close_enabled,
                   id target) {
  BrivibaSidebarTabItemView* item = [[BrivibaSidebarTabItemView alloc] initWithFrame:NSZeroRect];
  [item setCloseEnabled:close_enabled ? YES : NO];
  [item setTranslatesAutoresizingMaskIntoConstraints:NO];
  NSButton* tab_button = SiteTabButton(index, tab, active, target);
  [item addSubview:tab_button];

  NSMutableArray<NSLayoutConstraint*>* constraints = [NSMutableArray arrayWithArray:@[
    [[item widthAnchor] constraintEqualToConstant:48.0],
    [[item heightAnchor] constraintEqualToConstant:48.0],
    [[tab_button centerXAnchor] constraintEqualToAnchor:[item centerXAnchor]],
    [[tab_button centerYAnchor] constraintEqualToAnchor:[item centerYAnchor]],
  ]];

  if (close_enabled) {
    NSButton* close_button = CloseTabButton(index, target);
    [close_button setHidden:YES];
    [item setCloseButton:close_button];
    [item addSubview:close_button];
    [constraints addObjectsFromArray:@[
      [[close_button topAnchor] constraintEqualToAnchor:[item topAnchor] constant:1.0],
      [[close_button trailingAnchor] constraintEqualToAnchor:[item trailingAnchor] constant:-1.0],
    ]];
  }

  [NSLayoutConstraint activateConstraints:constraints];
  return item;
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
    [[view_ layer] setBackgroundColor:[[NSColor clearColor] CGColor]];

    sidebar_blur_view_ = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [sidebar_blur_view_ setMaterial:NSVisualEffectMaterialSidebar];
    [sidebar_blur_view_ setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [sidebar_blur_view_ setState:NSVisualEffectStateActive];
    [sidebar_blur_view_ setAlphaValue:0.58];
    [sidebar_blur_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];

    sidebar_tint_view_ = [[NSView alloc] initWithFrame:NSZeroRect];
    [sidebar_tint_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [sidebar_tint_view_ setWantsLayer:YES];
    [[sidebar_tint_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.50]
                                                       CGColor]];

    sidebar_edge_view_ = [[NSView alloc] initWithFrame:NSZeroRect];
    [sidebar_edge_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [sidebar_edge_view_ setWantsLayer:YES];
    [[sidebar_edge_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.20]
                                                       CGColor]];

    dock_view_ = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    [dock_view_ setMaterial:NSVisualEffectMaterialPopover];
    [dock_view_ setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
    [dock_view_ setState:NSVisualEffectStateActive];
    [dock_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [dock_view_ setWantsLayer:YES];
    [[dock_view_ layer] setCornerRadius:kSidebarCornerRadius];
    [[dock_view_ layer] setMasksToBounds:YES];
    [[dock_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.42] CGColor]];
    [[dock_view_ layer] setBorderColor:[[NSColor colorWithWhite:1.0 alpha:0.58] CGColor]];
    [[dock_view_ layer] setBorderWidth:1.0];
    [[dock_view_ layer] setShadowColor:[[NSColor blackColor] CGColor]];
    [[dock_view_ layer] setShadowOpacity:0.08F];
    [[dock_view_ layer] setShadowRadius:20.0];
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

    [view_ addSubview:sidebar_blur_view_];
    [view_ addSubview:sidebar_tint_view_];
    [view_ addSubview:sidebar_edge_view_];
    [view_ addSubview:dock_view_];
    [dock_view_ addSubview:top_stack_];
    [dock_view_ addSubview:bottom_stack];

    [NSLayoutConstraint activateConstraints:@[
      [[view_ widthAnchor] constraintEqualToConstant:kSidebarWidth],
      [[sidebar_blur_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[sidebar_blur_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_blur_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_blur_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[sidebar_tint_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[sidebar_tint_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_tint_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_tint_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[sidebar_edge_view_ widthAnchor] constraintEqualToConstant:10.0],
      [[sidebar_edge_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_edge_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_edge_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[dock_view_ widthAnchor] constraintEqualToConstant:kDockWidth],
      [[dock_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor] constant:kDockTop],
      [[dock_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor] constant:-kDockBottom],
      [[dock_view_ centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
      [[top_stack_ topAnchor] constraintEqualToAnchor:[dock_view_ topAnchor] constant:18.0],
      [[top_stack_ centerXAnchor] constraintEqualToAnchor:[dock_view_ centerXAnchor]],
      [[bottom_stack bottomAnchor] constraintEqualToAnchor:[dock_view_ bottomAnchor] constant:-16.0],
      [[bottom_stack centerXAnchor] constraintEqualToAnchor:[dock_view_ centerXAnchor]],
    ]];
    ApplyAppearance();
  }

  void SetNewTabAction(Action action) { bridge_->new_tab_action = std::move(action); }

  void SetSettingsAction(Action action) { bridge_->settings_action = std::move(action); }

  void SetSelectTabAction(SelectTabAction action) { bridge_->select_tab_action = std::move(action); }

  void SetCloseTabAction(CloseTabAction action) { bridge_->close_tab_action = std::move(action); }

  void SetTabState(const std::vector<Sidebar::TabState>& tabs, size_t active_index) {
    for (NSView* subview in [[tab_stack_ arrangedSubviews] copy]) {
      [tab_stack_ removeArrangedSubview:subview];
      [subview removeFromSuperview];
    }

    for (size_t index = 0; index < tabs.size(); ++index) {
      [tab_stack_ addArrangedSubview:SiteTabItem(index, tabs[index], index == active_index,
                                                tabs.size() > 1, bridge_)];
    }
  }

  void SetFullscreenAppearance(bool fullscreen) {
    if (fullscreen_ == fullscreen) {
      return;
    }
    fullscreen_ = fullscreen;
    ApplyAppearance();
  }

  NSView* NativeView() const { return view_; }

 private:
  void ApplyAppearance() {
    if (fullscreen_) {
      [sidebar_blur_view_ setHidden:YES];
      [[sidebar_tint_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:1.0]
                                                         CGColor]];
      [[sidebar_edge_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:0.0 alpha:0.08]
                                                         CGColor]];
      [dock_view_ setMaterial:NSVisualEffectMaterialContentBackground];
      [[dock_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:1.0] CGColor]];
      [[dock_view_ layer] setBorderColor:[[NSColor colorWithWhite:0.0 alpha:0.08] CGColor]];
      [[dock_view_ layer] setShadowOpacity:0.04F];
      return;
    }

    [sidebar_blur_view_ setHidden:NO];
    [dock_view_ setMaterial:NSVisualEffectMaterialPopover];
    [[sidebar_tint_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.50]
                                                       CGColor]];
    [[sidebar_edge_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.20]
                                                       CGColor]];
    [[dock_view_ layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.42] CGColor]];
    [[dock_view_ layer] setBorderColor:[[NSColor colorWithWhite:1.0 alpha:0.58] CGColor]];
    [[dock_view_ layer] setShadowOpacity:0.08F];
  }

  BrivibaSidebarActionBridge* bridge_ = nil;
  NSVisualEffectView* sidebar_blur_view_ = nil;
  NSView* sidebar_tint_view_ = nil;
  NSView* sidebar_edge_view_ = nil;
  NSVisualEffectView* dock_view_ = nil;
  NSStackView* top_stack_ = nil;
  NSStackView* tab_stack_ = nil;
  NSButton* new_tab_button_ = nil;
  NSButton* settings_button_ = nil;
  NSView* view_ = nil;
  bool fullscreen_ = false;
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

void Sidebar::SetCloseTabAction(CloseTabAction action) {
  impl_->SetCloseTabAction(std::move(action));
}

void Sidebar::SetTabState(const std::vector<TabState>& tabs, size_t active_index) {
  impl_->SetTabState(tabs, active_index);
}

void Sidebar::SetFullscreenAppearance(bool fullscreen) {
  impl_->SetFullscreenAppearance(fullscreen);
}

NSView* Sidebar::NativeView() const {
  return impl_->NativeView();
}

}  // namespace briviba

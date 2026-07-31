#include "briviba/sidebar.h"

#include "briviba/app_paths.h"

#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cstddef>
#include <cmath>
#include <filesystem>
#include <string>
#include <utility>

@interface BrivibaSidebarActionBridge : NSObject {
 @public
  briviba::Sidebar::Action new_tab_action;
  briviba::Sidebar::OpenFilesAction open_files_action;
  briviba::Sidebar::Action settings_action;
  briviba::Sidebar::SelectTabAction select_tab_action;
  briviba::Sidebar::CloseTabAction close_tab_action;
  briviba::Sidebar::TabAction back_tab_action;
  briviba::Sidebar::TabAction forward_tab_action;
  briviba::Sidebar::TabAction reload_tab_action;
  briviba::Sidebar::TabAction edit_tab_address_action;
  briviba::Sidebar::TabAction clear_tab_cookies_action;
  briviba::Sidebar::TabAction clear_tab_caches_action;
}
- (void)newTab:(id)sender;
- (void)openSettings:(id)sender;
- (void)selectTab:(id)sender;
- (void)closeTab:(id)sender;
- (void)backTab:(id)sender;
- (void)forwardTab:(id)sender;
- (void)reloadTab:(id)sender;
- (void)editTabAddress:(id)sender;
- (void)clearTabCookies:(id)sender;
- (void)clearTabCaches:(id)sender;
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

- (void)backTab:(id)sender {
  if (!back_tab_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  back_tab_action(static_cast<size_t>([sender tag]));
}

- (void)forwardTab:(id)sender {
  if (!forward_tab_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  forward_tab_action(static_cast<size_t>([sender tag]));
}

- (void)reloadTab:(id)sender {
  if (!reload_tab_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  reload_tab_action(static_cast<size_t>([sender tag]));
}

- (void)editTabAddress:(id)sender {
  if (!edit_tab_address_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  edit_tab_address_action(static_cast<size_t>([sender tag]));
}

- (void)clearTabCookies:(id)sender {
  if (!clear_tab_cookies_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  clear_tab_cookies_action(static_cast<size_t>([sender tag]));
}

- (void)clearTabCaches:(id)sender {
  if (!clear_tab_caches_action || ![sender respondsToSelector:@selector(tag)]) {
    return;
  }
  clear_tab_caches_action(static_cast<size_t>([sender tag]));
}

@end

@interface BrivibaDropButton : NSButton {
 @public
  briviba::Sidebar::OpenFilesAction open_files_action;
}
@end

@implementation BrivibaDropButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    [self registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
  }
  return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  if (!open_files_action || [self fileUrlsFromDraggingInfo:sender].count == 0) {
    return NSDragOperationNone;
  }
  [[self layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.82] CGColor]];
  return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  (void)sender;
  [[self layer] setBackgroundColor:[[NSColor clearColor] CGColor]];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  [[self layer] setBackgroundColor:[[NSColor clearColor] CGColor]];
  NSArray<NSURL*>* file_urls = [self fileUrlsFromDraggingInfo:sender];
  if (file_urls.count == 0 || !open_files_action) {
    return NO;
  }

  std::vector<std::string> urls;
  urls.reserve(file_urls.count);
  for (NSURL* url in file_urls) {
    if (![url isFileURL]) {
      continue;
    }
    NSString* absolute_string = [url absoluteString];
    const char* utf8 = [absolute_string UTF8String];
    if (utf8 != nullptr) {
      urls.emplace_back(utf8);
    }
  }
  if (urls.empty()) {
    return NO;
  }
  open_files_action(urls);
  return YES;
}

- (NSArray<NSURL*>*)fileUrlsFromDraggingInfo:(id<NSDraggingInfo>)sender {
  NSPasteboard* pasteboard = [sender draggingPasteboard];
  NSArray<NSURL*>* urls =
      [pasteboard readObjectsForClasses:@[ [NSURL class] ]
                                options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
  if (urls.count > 0) {
    return urls;
  }

  return @[];
}

@end

NSMenu* BrivibaSidebarTabContextMenu(NSInteger tab_index, BOOL close_enabled, id target) {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Tab"];

  NSMenuItem* back_item = [[NSMenuItem alloc] initWithTitle:@"Back"
                                                     action:@selector(backTab:)
                                              keyEquivalent:@""];
  [back_item setTarget:target];
  [back_item setTag:tab_index];
  [menu addItem:back_item];

  NSMenuItem* forward_item = [[NSMenuItem alloc] initWithTitle:@"Forward"
                                                        action:@selector(forwardTab:)
                                                 keyEquivalent:@""];
  [forward_item setTarget:target];
  [forward_item setTag:tab_index];
  [menu addItem:forward_item];

  [menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem* address_item = [[NSMenuItem alloc] initWithTitle:@"Edit Address..."
                                                        action:@selector(editTabAddress:)
                                                 keyEquivalent:@""];
  [address_item setTarget:target];
  [address_item setTag:tab_index];
  [menu addItem:address_item];

  NSMenuItem* reload_item = [[NSMenuItem alloc] initWithTitle:@"Reload"
                                                       action:@selector(reloadTab:)
                                                keyEquivalent:@""];
  [reload_item setTarget:target];
  [reload_item setTag:tab_index];
  [menu addItem:reload_item];

  [menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem* clear_cookies_item =
      [[NSMenuItem alloc] initWithTitle:@"Clear Cookies for Domain"
                                 action:@selector(clearTabCookies:)
                          keyEquivalent:@""];
  [clear_cookies_item setTarget:target];
  [clear_cookies_item setTag:tab_index];
  [menu addItem:clear_cookies_item];

  NSMenuItem* clear_caches_item = [[NSMenuItem alloc] initWithTitle:@"Clear Caches for Domain"
                                                             action:@selector(clearTabCaches:)
                                                      keyEquivalent:@""];
  [clear_caches_item setTarget:target];
  [clear_caches_item setTag:tab_index];
  [menu addItem:clear_caches_item];

  if (close_enabled) {
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* close_item = [[NSMenuItem alloc] initWithTitle:@"Close Tab"
                                                        action:@selector(closeTab:)
                                                 keyEquivalent:@""];
    [close_item setTarget:target];
    [close_item setTag:tab_index];
    [menu addItem:close_item];
  }

  return menu;
}

@interface BrivibaSidebarTabItemView : NSView
@property(nonatomic, strong) NSButton* closeButton;
@property(nonatomic, copy) NSString* hoverTitle;
@property(nonatomic, copy) NSString* hoverDomain;
@property(nonatomic) BOOL closeEnabled;
@property(nonatomic, weak) id actionTarget;
@property(nonatomic) NSInteger tabIndex;
@end

@interface BrivibaHoverPreviewView : NSView
@end

@implementation BrivibaHoverPreviewView

- (NSView*)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

@end

@implementation BrivibaSidebarTabItemView {
  NSTrackingArea* tracking_area_;
  NSView* hover_preview_view_;
}

- (void)dealloc {
  [self hideHoverPreview];
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
  [self showHoverPreview];
}

- (void)mouseExited:(NSEvent*)event {
  (void)event;
  [self updateCloseButtonVisibility:NO];
  [self hideHoverPreview];
}

- (void)rightMouseDown:(NSEvent*)event {
  [self hideHoverPreview];
  [NSMenu popUpContextMenu:BrivibaSidebarTabContextMenu(_tabIndex, _closeEnabled, _actionTarget)
                 withEvent:event
                   forView:self];
}

- (void)updateCloseButtonVisibility:(BOOL)visible {
  if (_closeButton == nil) {
    return;
  }
  [_closeButton setHidden:!(_closeEnabled && visible)];
}

- (void)showHoverPreview {
  if (hover_preview_view_ != nil || [self window] == nil || [[self window] contentView] == nil) {
    return;
  }

  NSString* title = [_hoverTitle stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString* domain = [_hoverDomain stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([title length] == 0) {
    title = [domain length] == 0 ? @"New Tab" : domain;
  }
  if ([domain length] == 0) {
    domain = title;
  }

  constexpr CGFloat panel_width = 214.0;
  constexpr CGFloat panel_min_height = 52.0;
  constexpr CGFloat horizontal_padding = 14.0;
  constexpr CGFloat vertical_padding = 8.0;
  const CGFloat text_width = panel_width - horizontal_padding * 2.0;

  NSFont* title_font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
  NSFont* domain_font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
  NSDictionary* title_attributes = @{NSFontAttributeName : title_font};
  NSRect title_bounds =
      [title boundingRectWithSize:NSMakeSize(text_width, 28.0)
                          options:NSStringDrawingUsesLineFragmentOrigin
                       attributes:title_attributes];
  const CGFloat title_height = std::min<CGFloat>(28.0, std::ceil(NSHeight(title_bounds)));
  const CGFloat panel_height =
      std::max(panel_min_height, vertical_padding * 2.0 + title_height + 16.0);

  NSView* content_view =
      [[BrivibaHoverPreviewView alloc] initWithFrame:NSMakeRect(0.0, 0.0, panel_width, panel_height)];
  [content_view setWantsLayer:YES];
  [[content_view layer] setMasksToBounds:NO];
  [[content_view layer] setBackgroundColor:[[NSColor clearColor] CGColor]];
  [[content_view layer] setShadowColor:[[NSColor blackColor] CGColor]];
  [[content_view layer] setShadowOpacity:0.14F];
  [[content_view layer] setShadowRadius:16.0];
  [[content_view layer] setShadowOffset:CGSizeMake(0.0, -5.0)];
  CGPathRef shadow_path =
      CGPathCreateWithRoundedRect(CGRectMake(0.0, 0.0, panel_width, panel_height), 12.0, 12.0,
                                  nullptr);
  [[content_view layer] setShadowPath:shadow_path];
  CGPathRelease(shadow_path);

  NSView* card_view = [[NSView alloc] initWithFrame:NSZeroRect];
  [card_view setTranslatesAutoresizingMaskIntoConstraints:NO];
  [card_view setWantsLayer:YES];
  [[card_view layer] setCornerRadius:12.0];
  [[card_view layer] setMasksToBounds:YES];
  [[card_view layer] setBackgroundColor:[[NSColor colorWithWhite:1.0 alpha:0.94] CGColor]];
  [[card_view layer] setBorderColor:[[NSColor colorWithWhite:0.0 alpha:0.10] CGColor]];
  [[card_view layer] setBorderWidth:0.8];
  [content_view addSubview:card_view];

  NSTextField* title_label = [NSTextField wrappingLabelWithString:title];
  [title_label setFont:title_font];
  [title_label setTextColor:[NSColor colorWithWhite:0.08 alpha:0.92]];
  [title_label setMaximumNumberOfLines:2];
  [title_label setLineBreakMode:NSLineBreakByTruncatingTail];
  [title_label setTranslatesAutoresizingMaskIntoConstraints:NO];
  [card_view addSubview:title_label];

  NSTextField* domain_label = [NSTextField labelWithString:domain];
  [domain_label setFont:domain_font];
  [domain_label setTextColor:[NSColor colorWithWhite:0.38 alpha:0.90]];
  [domain_label setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [domain_label setTranslatesAutoresizingMaskIntoConstraints:NO];
  [card_view addSubview:domain_label];

  [NSLayoutConstraint activateConstraints:@[
    [[card_view leadingAnchor] constraintEqualToAnchor:[content_view leadingAnchor]],
    [[card_view topAnchor] constraintEqualToAnchor:[content_view topAnchor]],
    [[card_view trailingAnchor] constraintEqualToAnchor:[content_view trailingAnchor]],
    [[card_view bottomAnchor] constraintEqualToAnchor:[content_view bottomAnchor]],
    [[title_label leadingAnchor] constraintEqualToAnchor:[card_view leadingAnchor]
                                                constant:horizontal_padding],
    [[title_label topAnchor] constraintEqualToAnchor:[card_view topAnchor]
                                            constant:vertical_padding],
    [[title_label trailingAnchor] constraintEqualToAnchor:[card_view trailingAnchor]
                                                 constant:-horizontal_padding],
    [[domain_label leadingAnchor] constraintEqualToAnchor:[title_label leadingAnchor]],
    [[domain_label topAnchor] constraintEqualToAnchor:[title_label bottomAnchor] constant:4.0],
    [[domain_label trailingAnchor] constraintEqualToAnchor:[title_label trailingAnchor]],
  ]];

  [content_view setAutoresizingMask:NSViewNotSizable];
  NSRect item_rect_in_window = [self convertRect:[self bounds] toView:nil];
  NSView* root_view = [[self window] contentView];
  NSRect item_rect_in_root = [root_view convertRect:item_rect_in_window fromView:nil];
  CGFloat x = NSMaxX(item_rect_in_root) + 10.0;
  CGFloat y = NSMidY(item_rect_in_root) - panel_height / 2.0;
  NSRect root_bounds = [root_view bounds];
  y = std::max(NSMinY(root_bounds) + 8.0,
               std::min(y, NSMaxY(root_bounds) - panel_height - 8.0));
  [content_view setFrame:NSMakeRect(x, y, panel_width, panel_height)];
  [root_view addSubview:content_view positioned:NSWindowAbove relativeTo:nil];
  hover_preview_view_ = content_view;
}

- (void)hideHoverPreview {
  if (hover_preview_view_ == nil) {
    return;
  }
  [hover_preview_view_ removeFromSuperview];
  hover_preview_view_ = nil;
}

@end

namespace briviba {
namespace {

constexpr CGFloat kSidebarWidth = 96.0;
constexpr CGFloat kDockWidth = 64.0;
constexpr CGFloat kDockTop = 50.0;
constexpr CGFloat kFullscreenDockTop = 10.0;
constexpr CGFloat kDockBottom = 14.0;
constexpr CGFloat kSidebarCornerRadius = 15.0;
constexpr CGFloat kIconButtonSize = 34.0;
constexpr CGFloat kActiveTabButtonSize = 44.0;
constexpr CGFloat kStackSpacing = 10.0;
constexpr CGFloat kDockContentTop = 18.0;
constexpr CGFloat kDockContentBottom = 16.0;
constexpr CGFloat kNewTabGap = 10.0;
constexpr CGFloat kSidebarEdgeWidth = 1.0;

NSColor* DockIconTintColor() {
  return [NSColor colorWithWhite:0.06 alpha:0.78];
}

NSString* StringFromStdString(const std::string& value) {
  return [NSString stringWithUTF8String:value.c_str()];
}

NSString* NSStringFromPath(const std::filesystem::path& path) {
  return [NSString stringWithUTF8String:path.string().c_str()];
}

NSString* HostFromUrl(const std::string& url) {
  NSURL* parsed_url = [NSURL URLWithString:StringFromStdString(url)];
  NSString* host = [[parsed_url host] lowercaseString];
  return host == nil || [host length] == 0 ? StringFromStdString(url) : host;
}

NSString* FallbackTabLabel(const Sidebar::TabState& tab) {
  NSString* source = HostFromUrl(tab.url);
  if ([source length] == 0) {
    source = StringFromStdString(tab.title);
  }
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

NSString* SHA256Hex(NSString* value) {
  NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256([data bytes], static_cast<CC_LONG>([data length]), digest);

  NSMutableString* result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (int index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) {
    [result appendFormat:@"%02x", digest[index]];
  }
  return result;
}

std::filesystem::path FaviconCacheDirectory() {
  return ApplicationSupportFile("FaviconCache");
}

NSURL* FaviconCacheFileUrl(NSString* favicon_url) {
  std::filesystem::create_directories(FaviconCacheDirectory());
  NSString* filename = [SHA256Hex(favicon_url) stringByAppendingString:@".img"];
  std::filesystem::path cache_path = FaviconCacheDirectory() / std::string([filename UTF8String]);
  return [NSURL fileURLWithPath:NSStringFromPath(cache_path)];
}

NSCache<NSString*, NSImage*>* FaviconMemoryCache() {
  static NSCache<NSString*, NSImage*>* cache = [[NSCache alloc] init];
  [cache setCountLimit:256];
  return cache;
}

NSCache<NSString*, NSImage*>* RenderedFaviconMemoryCache() {
  static NSCache<NSString*, NSImage*>* cache = [[NSCache alloc] init];
  [cache setCountLimit:256];
  return cache;
}

NSMutableSet<NSString*>* PendingFaviconFetches() {
  static NSMutableSet<NSString*>* pending_fetches = [NSMutableSet set];
  return pending_fetches;
}

NSMutableDictionary<NSString*, NSHashTable<NSButton*>*>* PendingFaviconButtons() {
  static NSMutableDictionary<NSString*, NSHashTable<NSButton*>*>* pending_buttons =
      [NSMutableDictionary dictionary];
  return pending_buttons;
}

NSImage* RenderFaviconForSidebar(NSImage* source_image, NSString* cache_key) {
  NSString* rendered_key = [@"rendered:" stringByAppendingString:cache_key];
  NSImage* cached_image = [RenderedFaviconMemoryCache() objectForKey:rendered_key];
  if (cached_image != nil) {
    return cached_image;
  }

  constexpr CGFloat kCanvasSize = 30.0;
  constexpr CGFloat kNormalIconSize = 28.0;
  NSSize pixel_size = [source_image size];
  CGImageRef cg_image = [source_image CGImageForProposedRect:nil context:nil hints:nil];
  if (cg_image != nullptr) {
    pixel_size = NSMakeSize(CGImageGetWidth(cg_image), CGImageGetHeight(cg_image));
  }
  const bool low_quality = pixel_size.width < 24.0 || pixel_size.height < 24.0;

  NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(kCanvasSize, kCanvasSize)];
  [image lockFocus];
  [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
  if (low_quality) {
    NSBezierPath* background =
        [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.0, 0.0, kCanvasSize, kCanvasSize)
                                        xRadius:9.0
                                        yRadius:9.0];
    [[NSColor colorWithWhite:1.0 alpha:1.0] setFill];
    [background fill];

    const CGFloat compact_icon_size = 20.0;
    const CGFloat origin = (kCanvasSize - compact_icon_size) / 2.0;
    [source_image drawInRect:NSMakeRect(origin, origin, compact_icon_size, compact_icon_size)
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver
                    fraction:1.0];
  } else {
    const CGFloat origin = (kCanvasSize - kNormalIconSize) / 2.0;
    [source_image drawInRect:NSMakeRect(origin, origin, kNormalIconSize, kNormalIconSize)
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver
                    fraction:1.0];
  }
  [image unlockFocus];
  [RenderedFaviconMemoryCache() setObject:image forKey:rendered_key];
  return image;
}

NSImage* CachedFavicon(NSString* cache_key) {
  NSImage* cached_image = [FaviconMemoryCache() objectForKey:cache_key];
  if (cached_image != nil) {
    return RenderFaviconForSidebar(cached_image, cache_key);
  }

  NSURL* file_url = FaviconCacheFileUrl(cache_key);
  NSImage* disk_image = [[NSImage alloc] initWithContentsOfURL:file_url];
  if (disk_image != nil) {
    [FaviconMemoryCache() setObject:disk_image forKey:cache_key];
    return RenderFaviconForSidebar(disk_image, cache_key);
  }
  return nil;
}

NSURL* FaviconSourceUrl(const Sidebar::TabState& tab) {
  if (!tab.favicon_url.empty()) {
    NSURL* explicit_url = [NSURL URLWithString:StringFromStdString(tab.favicon_url)];
    if (explicit_url != nil) {
      NSString* extension = [explicit_url.pathExtension lowercaseString];
      if (![extension isEqualToString:@"svg"]) {
        return explicit_url;
      }
    }
  }

  NSString* host = HostFromUrl(tab.url);
  if ([host length] == 0 || [host containsString:@"://"] || [host isEqualToString:@"?"]) {
    return nil;
  }
  return [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/favicon.ico", host]];
}

void TrackPendingFaviconButton(NSString* cache_key, NSButton* button) {
  NSHashTable<NSButton*>* buttons = PendingFaviconButtons()[cache_key];
  if (buttons == nil) {
    buttons = [NSHashTable weakObjectsHashTable];
    PendingFaviconButtons()[cache_key] = buttons;
  }
  [buttons addObject:button];
}

void FetchFaviconIfNeeded(NSString* cache_key, NSURL* favicon_url, NSButton* button) {
  if ([cache_key length] == 0 || favicon_url == nil) {
    return;
  }

  if ([PendingFaviconFetches() containsObject:cache_key]) {
    TrackPendingFaviconButton(cache_key, button);
    return;
  }

  TrackPendingFaviconButton(cache_key, button);
  [PendingFaviconFetches() addObject:cache_key];
  NSURLSessionDataTask* task =
      [[NSURLSession sharedSession] dataTaskWithURL:favicon_url
                                  completionHandler:^(NSData* data, NSURLResponse* response,
                                                      NSError* error) {
                                    (void)response;
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                      NSHashTable<NSButton*>* buttons =
                                          PendingFaviconButtons()[cache_key];
                                      [PendingFaviconButtons() removeObjectForKey:cache_key];
                                      [PendingFaviconFetches() removeObject:cache_key];
                                      if (error != nil || data == nil || [data length] == 0) {
                                        return;
                                      }
                                      NSImage* image = [[NSImage alloc] initWithData:data];
                                      if (image == nil) {
                                        return;
                                      }
                                      [data writeToURL:FaviconCacheFileUrl(cache_key) atomically:YES];
                                      [FaviconMemoryCache() setObject:image forKey:cache_key];
                                      NSImage* rendered_image =
                                          RenderFaviconForSidebar(image, cache_key);
                                      for (NSButton* pending_button in buttons) {
                                        [pending_button setImage:rendered_image];
                                      }
                                    });
                                  }];
  [task resume];
}

NSImage* SiteTabImage(const Sidebar::TabState& tab, bool active, bool enabled) {
  NSString* cache_key = HostFromUrl(tab.url);
  if ([cache_key length] > 0) {
    NSImage* domain_favicon = CachedFavicon(cache_key);
    if (domain_favicon != nil) {
      return domain_favicon;
    }
  }
  if (!tab.favicon_url.empty()) {
    NSImage* url_favicon = CachedFavicon(StringFromStdString(tab.favicon_url));
    if (url_favicon != nil) {
      return url_favicon;
    }
  }
  return FallbackTabImage(FallbackTabLabel(tab), active, enabled);
}

NSButton* IconButton(NSString* symbol_name, NSString* accessibility_label) {
  NSImage* image = [NSImage imageWithSystemSymbolName:symbol_name
                             accessibilityDescription:accessibility_label];
  NSButton* button = [[BrivibaDropButton alloc] initWithFrame:NSZeroRect];
  [button setImage:image];
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
  NSURL* favicon_url = FaviconSourceUrl(tab);
  NSString* cache_key = HostFromUrl(tab.url);
  if ([cache_key length] > 0) {
    FetchFaviconIfNeeded(cache_key, favicon_url, button);
  }
  [button setImagePosition:NSImageOnly];
  [button setImageScaling:NSImageScaleProportionallyDown];
  [button setToolTip:nil];
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
  [item setActionTarget:target];
  [item setTabIndex:static_cast<NSInteger>(index)];
  [item setTranslatesAutoresizingMaskIntoConstraints:NO];
  NSButton* tab_button = SiteTabButton(index, tab, active, target);
  NSString* domain = HostFromUrl(tab.url);
  NSString* title = tab.title.empty() ? domain : StringFromStdString(tab.title);
  [item setHoverTitle:title];
  [item setHoverDomain:domain];
  [tab_button setMenu:BrivibaSidebarTabContextMenu(static_cast<NSInteger>(index),
                                                  close_enabled ? YES : NO, target)];
  [item addSubview:tab_button];

  NSMutableArray<NSLayoutConstraint*>* constraints = [NSMutableArray arrayWithArray:@[
    [[item widthAnchor] constraintEqualToConstant:kActiveTabButtonSize],
    [[item heightAnchor] constraintEqualToConstant:kActiveTabButtonSize],
    [[tab_button centerXAnchor] constraintEqualToAnchor:[item centerXAnchor]],
    [[tab_button centerYAnchor] constraintEqualToAnchor:[item centerYAnchor]],
  ]];

  if (close_enabled) {
    NSButton* close_button = CloseTabButton(index, target);
    [close_button setHidden:YES];
    [item setCloseButton:close_button];
    [item addSubview:close_button];
    [constraints addObjectsFromArray:@[
      [[close_button topAnchor] constraintEqualToAnchor:[item topAnchor] constant:-2.0],
      [[close_button trailingAnchor] constraintEqualToAnchor:[item trailingAnchor] constant:2.0],
    ]];
  }

  [NSLayoutConstraint activateConstraints:constraints];
  return item;
}

NSStackView* StackView(NSUserInterfaceLayoutOrientation orientation,
                       NSLayoutAttribute alignment) {
  NSStackView* stack = [[NSStackView alloc] init];
  [stack setOrientation:orientation];
  [stack setAlignment:alignment];
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

    tab_document_view_ = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, kDockWidth, 1.0)];
    [tab_document_view_ setWantsLayer:YES];

    top_stack_ = StackView(NSUserInterfaceLayoutOrientationVertical, NSLayoutAttributeCenterX);
    tab_stack_ = StackView(NSUserInterfaceLayoutOrientationVertical, NSLayoutAttributeCenterX);
    [top_stack_ addArrangedSubview:tab_stack_];

    tab_scroll_view_ = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [tab_scroll_view_ setBorderType:NSNoBorder];
    [tab_scroll_view_ setDrawsBackground:NO];
    [tab_scroll_view_ setHasVerticalScroller:NO];
    [tab_scroll_view_ setHasHorizontalScroller:NO];
    [tab_scroll_view_ setAutohidesScrollers:YES];
    [tab_scroll_view_ setVerticalScrollElasticity:NSScrollElasticityAllowed];
    [tab_scroll_view_ setTranslatesAutoresizingMaskIntoConstraints:NO];
    [tab_scroll_view_ setDocumentView:tab_document_view_];

    new_tab_button_ = IconButton(@"plus", @"New tab");
    [new_tab_button_ setTarget:bridge_];
    [new_tab_button_ setAction:@selector(newTab:)];
    [top_stack_ addArrangedSubview:new_tab_button_];
    [tab_document_view_ addSubview:top_stack_];

    control_stack_ = StackView(NSUserInterfaceLayoutOrientationVertical, NSLayoutAttributeCenterX);
    settings_button_ = IconButton(@"gearshape", @"Settings");
    [settings_button_ setTarget:bridge_];
    [settings_button_ setAction:@selector(openSettings:)];
    [control_stack_ addArrangedSubview:settings_button_];

    [view_ addSubview:sidebar_blur_view_];
    [view_ addSubview:sidebar_tint_view_];
    [view_ addSubview:sidebar_edge_view_];
    [view_ addSubview:dock_view_];
    [dock_view_ addSubview:tab_scroll_view_];
    [dock_view_ addSubview:control_stack_];
    dock_top_constraint_ =
        [[dock_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor] constant:kDockTop];
    vertical_constraints_ = @[
      [[view_ widthAnchor] constraintEqualToConstant:kSidebarWidth],
      [[sidebar_blur_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[sidebar_blur_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_blur_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_blur_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[sidebar_tint_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[sidebar_tint_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_tint_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_tint_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[sidebar_edge_view_ widthAnchor] constraintEqualToConstant:kSidebarEdgeWidth],
      [[sidebar_edge_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_edge_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_edge_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[dock_view_ widthAnchor] constraintEqualToConstant:kDockWidth],
      dock_top_constraint_,
      [[dock_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor] constant:-kDockBottom],
      [[dock_view_ centerXAnchor] constraintEqualToAnchor:[view_ centerXAnchor]],
      [[tab_scroll_view_ leadingAnchor] constraintEqualToAnchor:[dock_view_ leadingAnchor]],
      [[tab_scroll_view_ topAnchor] constraintEqualToAnchor:[dock_view_ topAnchor]
                                                   constant:kDockContentTop],
      [[tab_scroll_view_ trailingAnchor] constraintEqualToAnchor:[dock_view_ trailingAnchor]],
      [[tab_scroll_view_ bottomAnchor] constraintEqualToAnchor:[control_stack_ topAnchor]
                                                      constant:-kNewTabGap],
      [[control_stack_ bottomAnchor] constraintEqualToAnchor:[dock_view_ bottomAnchor]
                                                  constant:-kDockContentBottom],
      [[control_stack_ centerXAnchor] constraintEqualToAnchor:[dock_view_ centerXAnchor]],
      [[top_stack_ topAnchor] constraintEqualToAnchor:[tab_document_view_ topAnchor]],
      [[top_stack_ centerXAnchor] constraintEqualToAnchor:[tab_document_view_ centerXAnchor]],
      [[top_stack_ bottomAnchor] constraintEqualToAnchor:[tab_document_view_ bottomAnchor]],
    ];

    horizontal_constraints_ = @[
      [[view_ heightAnchor] constraintEqualToConstant:72.0],
      [[sidebar_blur_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[sidebar_blur_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_blur_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_blur_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[sidebar_tint_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[sidebar_tint_view_ topAnchor] constraintEqualToAnchor:[view_ topAnchor]],
      [[sidebar_tint_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_tint_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[sidebar_edge_view_ heightAnchor] constraintEqualToConstant:kSidebarEdgeWidth],
      [[sidebar_edge_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]],
      [[sidebar_edge_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor]],
      [[sidebar_edge_view_ bottomAnchor] constraintEqualToAnchor:[view_ bottomAnchor]],
      [[dock_view_ leadingAnchor] constraintEqualToAnchor:[view_ leadingAnchor]
                                                 constant:12.0],
      dock_top_constraint_,
      [[dock_view_ trailingAnchor] constraintEqualToAnchor:[view_ trailingAnchor] constant:-12.0],
      [[dock_view_ heightAnchor] constraintEqualToConstant:52.0],
      [[tab_scroll_view_ leadingAnchor] constraintEqualToAnchor:[dock_view_ leadingAnchor]
                                                       constant:12.0],
      [[tab_scroll_view_ topAnchor] constraintEqualToAnchor:[dock_view_ topAnchor]],
      [[tab_scroll_view_ bottomAnchor] constraintEqualToAnchor:[dock_view_ bottomAnchor]],
      [[tab_scroll_view_ trailingAnchor] constraintEqualToAnchor:[control_stack_ leadingAnchor]
                                                        constant:-12.0],
      [[control_stack_ trailingAnchor] constraintEqualToAnchor:[dock_view_ trailingAnchor]
                                                      constant:-12.0],
      [[control_stack_ centerYAnchor] constraintEqualToAnchor:[dock_view_ centerYAnchor]],
      [[top_stack_ leadingAnchor] constraintEqualToAnchor:[tab_document_view_ leadingAnchor]],
      [[top_stack_ centerYAnchor] constraintEqualToAnchor:[tab_document_view_ centerYAnchor]],
      [[top_stack_ trailingAnchor] constraintEqualToAnchor:[tab_document_view_ trailingAnchor]],
    ];
    [NSLayoutConstraint activateConstraints:vertical_constraints_];
    ApplyAppearance();
    SetDockPosition(DockPosition::kLeft);
  }

  void SetNewTabAction(Action action) { bridge_->new_tab_action = std::move(action); }

  void SetOpenFilesAction(OpenFilesAction action) {
    bridge_->open_files_action = std::move(action);
    BrivibaDropButton* drop_button = (BrivibaDropButton*)new_tab_button_;
    drop_button->open_files_action = bridge_->open_files_action;
  }

  void SetSettingsAction(Action action) { bridge_->settings_action = std::move(action); }

  void SetSelectTabAction(SelectTabAction action) { bridge_->select_tab_action = std::move(action); }

  void SetCloseTabAction(CloseTabAction action) { bridge_->close_tab_action = std::move(action); }

  void SetBackTabAction(TabAction action) { bridge_->back_tab_action = std::move(action); }

  void SetForwardTabAction(TabAction action) { bridge_->forward_tab_action = std::move(action); }

  void SetReloadTabAction(TabAction action) { bridge_->reload_tab_action = std::move(action); }

  void SetEditTabAddressAction(TabAction action) {
    bridge_->edit_tab_address_action = std::move(action);
  }

  void SetClearTabCookiesAction(TabAction action) {
    bridge_->clear_tab_cookies_action = std::move(action);
  }

  void SetClearTabCachesAction(TabAction action) {
    bridge_->clear_tab_caches_action = std::move(action);
  }

  void SetDockPosition(Sidebar::DockPosition position) {
    if (dock_position_ == position) {
      return;
    }
    dock_position_ = position;
    [NSLayoutConstraint deactivateConstraints:vertical_constraints_];
    [NSLayoutConstraint deactivateConstraints:horizontal_constraints_];
    const BOOL horizontal = dock_position_ == Sidebar::DockPosition::kTop;
    [tab_scroll_view_ setHasHorizontalScroller:horizontal];
    [tab_scroll_view_ setHasVerticalScroller:!horizontal];
    [tab_stack_ setOrientation:horizontal ? NSUserInterfaceLayoutOrientationHorizontal
                                          : NSUserInterfaceLayoutOrientationVertical];
    [tab_stack_ setAlignment:horizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeCenterX];
    [top_stack_ setOrientation:horizontal ? NSUserInterfaceLayoutOrientationHorizontal
                                          : NSUserInterfaceLayoutOrientationVertical];
    [top_stack_ setAlignment:horizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeCenterX];
    [control_stack_ setOrientation:horizontal ? NSUserInterfaceLayoutOrientationHorizontal
                                              : NSUserInterfaceLayoutOrientationVertical];
    [control_stack_ setAlignment:horizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeCenterX];
    [NSLayoutConstraint activateConstraints:horizontal ? horizontal_constraints_
                                                       : vertical_constraints_];
    UpdateTabDocumentFrame(tab_stack_.arrangedSubviews.count);
  }

  void SetTabState(const std::vector<Sidebar::TabState>& tabs, size_t active_index) {
    for (NSView* subview in [[tab_stack_ arrangedSubviews] copy]) {
      [tab_stack_ removeArrangedSubview:subview];
      [subview removeFromSuperview];
    }

    for (size_t index = 0; index < tabs.size(); ++index) {
      [tab_stack_ addArrangedSubview:SiteTabItem(index, tabs[index], index == active_index,
                                                tabs.size() > 1, bridge_)];
    }
    UpdateTabDocumentFrame(tabs.size());
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
      [dock_top_constraint_ setConstant:kFullscreenDockTop];
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

    [dock_top_constraint_ setConstant:kDockTop];
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

  void UpdateTabDocumentFrame(size_t tab_count) {
    const BOOL horizontal = dock_position_ == Sidebar::DockPosition::kTop;
    if (horizontal) {
      const CGFloat width =
          (tab_count == 0 ? 0.0
                          : tab_count * kActiveTabButtonSize +
                                (tab_count - 1) * kStackSpacing) +
          kStackSpacing + kIconButtonSize;
      [tab_document_view_ setFrame:NSMakeRect(0.0, 0.0, width, 1.0)];
      return;
    }

    const CGFloat height =
        (tab_count == 0 ? 0.0
                        : tab_count * kActiveTabButtonSize +
                              (tab_count - 1) * kStackSpacing) +
        kStackSpacing + kIconButtonSize;
    [tab_document_view_ setFrame:NSMakeRect(0.0, 0.0, kDockWidth, height)];
  }

  BrivibaSidebarActionBridge* bridge_ = nil;
  NSVisualEffectView* sidebar_blur_view_ = nil;
  NSView* sidebar_tint_view_ = nil;
  NSView* sidebar_edge_view_ = nil;
  NSVisualEffectView* dock_view_ = nil;
  NSLayoutConstraint* dock_top_constraint_ = nil;
  NSScrollView* tab_scroll_view_ = nil;
  NSView* tab_document_view_ = nil;
  NSStackView* top_stack_ = nil;
  NSStackView* tab_stack_ = nil;
  NSStackView* control_stack_ = nil;
  NSArray<NSLayoutConstraint*>* vertical_constraints_ = nil;
  NSArray<NSLayoutConstraint*>* horizontal_constraints_ = nil;
  NSButton* new_tab_button_ = nil;
  NSButton* settings_button_ = nil;
  NSView* view_ = nil;
  Sidebar::DockPosition dock_position_ = Sidebar::DockPosition::kLeft;
  bool fullscreen_ = false;
};

Sidebar::Sidebar() : impl_(std::make_unique<Impl>()) {}

Sidebar::~Sidebar() = default;

void Sidebar::SetNewTabAction(Action action) {
  impl_->SetNewTabAction(std::move(action));
}

void Sidebar::SetOpenFilesAction(OpenFilesAction action) {
  impl_->SetOpenFilesAction(std::move(action));
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

void Sidebar::SetBackTabAction(TabAction action) {
  impl_->SetBackTabAction(std::move(action));
}

void Sidebar::SetForwardTabAction(TabAction action) {
  impl_->SetForwardTabAction(std::move(action));
}

void Sidebar::SetReloadTabAction(TabAction action) {
  impl_->SetReloadTabAction(std::move(action));
}

void Sidebar::SetEditTabAddressAction(TabAction action) {
  impl_->SetEditTabAddressAction(std::move(action));
}

void Sidebar::SetClearTabCookiesAction(TabAction action) {
  impl_->SetClearTabCookiesAction(std::move(action));
}

void Sidebar::SetClearTabCachesAction(TabAction action) {
  impl_->SetClearTabCachesAction(std::move(action));
}

void Sidebar::SetDockPosition(DockPosition position) {
  impl_->SetDockPosition(position);
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

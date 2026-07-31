#import <AppKit/AppKit.h>

#include <memory>

#include "briviba/window_manager.h"

@interface BrivibaAppDelegate : NSObject <NSApplicationDelegate> {
 @private
  std::unique_ptr<briviba::WindowManager> window_manager_;
}
@end

@implementation BrivibaAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;
  window_manager_ = std::make_unique<briviba::WindowManager>();
  window_manager_->OpenInitialWindow();
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  (void)notification;
  window_manager_.reset();
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

- (void)newTab:(id)sender {
  (void)sender;
  if (window_manager_ != nullptr) {
    window_manager_->CreateTabInActiveWindow();
  }
}

- (void)closeTab:(id)sender {
  (void)sender;
  if (window_manager_ != nullptr) {
    window_manager_->CloseTabInActiveWindow();
  }
}

- (void)reloadPage:(id)sender {
  (void)sender;
  if (window_manager_ != nullptr) {
    window_manager_->ReloadPageInActiveWindow();
  }
}

@end

namespace {

NSMenuItem* MenuItem(NSString* title, SEL action, NSString* key_equivalent,
                     NSEventModifierFlags modifiers = NSEventModifierFlagCommand) {
  NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title
                                                action:action
                                         keyEquivalent:key_equivalent];
  [item setKeyEquivalentModifierMask:modifiers];
  return item;
}

void ConfigureMainMenu() {
  NSMenu* main_menu = [[NSMenu alloc] initWithTitle:@"Briviba"];

  NSMenuItem* app_menu_item = [[NSMenuItem alloc] initWithTitle:@"Briviba"
                                                         action:nil
                                                  keyEquivalent:@""];
  [main_menu addItem:app_menu_item];
  NSMenu* app_menu = [[NSMenu alloc] initWithTitle:@"Briviba"];
  [app_menu addItem:MenuItem(@"Quit Briviba", @selector(terminate:), @"q")];
  [app_menu_item setSubmenu:app_menu];

  NSMenuItem* file_menu_item = [[NSMenuItem alloc] initWithTitle:@"File"
                                                          action:nil
                                                   keyEquivalent:@""];
  [main_menu addItem:file_menu_item];
  NSMenu* file_menu = [[NSMenu alloc] initWithTitle:@"File"];
  NSMenuItem* new_tab_item = MenuItem(@"New Tab", @selector(newTab:), @"t",
                            NSEventModifierFlagCommand);
  [new_tab_item setTarget:[NSApp delegate]];
  [file_menu addItem:new_tab_item];
  NSMenuItem* reload_item = MenuItem(@"Reload Page", @selector(reloadPage:), @"r",
                           NSEventModifierFlagCommand);
  [reload_item setTarget:[NSApp delegate]];
  [file_menu addItem:reload_item];
  NSMenuItem* close_tab_item = MenuItem(@"Close Tab", @selector(closeTab:), @"w",
                             NSEventModifierFlagCommand);
  [close_tab_item setTarget:[NSApp delegate]];
  [file_menu addItem:close_tab_item];
  [file_menu_item setSubmenu:file_menu];

  NSMenuItem* edit_menu_item = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                          action:nil
                                                   keyEquivalent:@""];
  [main_menu addItem:edit_menu_item];
  NSMenu* edit_menu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [edit_menu addItem:MenuItem(@"Undo", @selector(undo:), @"z")];
  [edit_menu addItem:MenuItem(@"Redo", @selector(redo:), @"Z")];
  [edit_menu addItem:[NSMenuItem separatorItem]];
  [edit_menu addItem:MenuItem(@"Cut", @selector(cut:), @"x")];
  [edit_menu addItem:MenuItem(@"Copy", @selector(copy:), @"c")];
  [edit_menu addItem:MenuItem(@"Paste", @selector(paste:), @"v")];
  [edit_menu addItem:MenuItem(@"Select All", @selector(selectAll:), @"a")];
  [edit_menu_item setSubmenu:edit_menu];

  [NSApp setMainMenu:main_menu];
}

}  // namespace

int main(int argc, char* argv[]) {
  (void)argc;
  (void)argv;

  @autoreleasepool {
    NSApplication* application = [NSApplication sharedApplication];
    BrivibaAppDelegate* delegate = [[BrivibaAppDelegate alloc] init];
    [application setDelegate:delegate];
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    ConfigureMainMenu();
    [application run];
  }

  return 0;
}

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

@end

int main(int argc, char* argv[]) {
  (void)argc;
  (void)argv;

  @autoreleasepool {
    NSApplication* application = [NSApplication sharedApplication];
    BrivibaAppDelegate* delegate = [[BrivibaAppDelegate alloc] init];
    [application setDelegate:delegate];
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    [application run];
  }

  return 0;
}

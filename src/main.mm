#import <AppKit/AppKit.h>

@interface BrivibaAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation BrivibaAppDelegate

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

#import <AppKit/AppKit.h>

#include <array>
#include <cstdlib>
#include <iostream>
#include <string>

namespace {

struct IconSize {
  const char* filename;
  CGFloat size;
};

constexpr std::array<IconSize, 10> kIconSizes{{
    {"icon_16x16.png", 16.0},
    {"icon_16x16@2x.png", 32.0},
    {"icon_32x32.png", 32.0},
    {"icon_32x32@2x.png", 64.0},
    {"icon_128x128.png", 128.0},
    {"icon_128x128@2x.png", 256.0},
    {"icon_256x256.png", 256.0},
    {"icon_256x256@2x.png", 512.0},
    {"icon_512x512.png", 512.0},
    {"icon_512x512@2x.png", 1024.0},
}};

NSImage* RoundedIcon(NSImage* source_image, CGFloat size) {
  NSImage* icon = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
  [icon lockFocus];

  const NSRect bounds = NSMakeRect(0.0, 0.0, size, size);
  [[NSColor clearColor] setFill];
  NSRectFill(bounds);

  NSBezierPath* clip_path =
      [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:size * 0.223 yRadius:size * 0.223];
  [clip_path addClip];

  [[NSColor whiteColor] setFill];
  NSRectFill(bounds);
  [source_image drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                  fraction:1.0];

  [icon unlockFocus];
  return icon;
}

bool WritePng(NSImage* image, NSString* path) {
  NSData* tiff = [image TIFFRepresentation];
  if (tiff == nil) {
    return false;
  }

  NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithData:tiff];
  NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  return png != nil && [png writeToFile:path atomically:YES];
}

}  // namespace

int main(int argc, char* argv[]) {
  @autoreleasepool {
    if (argc != 3) {
      std::cerr << "usage: make_app_icon input output-iconset\n";
      return EXIT_FAILURE;
    }

    NSString* input_path = [NSString stringWithUTF8String:argv[1]];
    NSString* output_path = [NSString stringWithUTF8String:argv[2]];
    NSImage* source_image = [[NSImage alloc] initWithContentsOfFile:input_path];
    if (source_image == nil) {
      std::cerr << "failed to read input image\n";
      return EXIT_FAILURE;
    }

    NSError* error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:output_path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error != nil) {
      std::cerr << "failed to create iconset\n";
      return EXIT_FAILURE;
    }

    for (const IconSize icon_size : kIconSizes) {
      NSImage* icon = RoundedIcon(source_image, icon_size.size);
      NSString* filename = [NSString stringWithUTF8String:icon_size.filename];
      NSString* path = [output_path stringByAppendingPathComponent:filename];
      if (!WritePng(icon, path)) {
        std::cerr << "failed to write " << icon_size.filename << "\n";
        return EXIT_FAILURE;
      }
    }
  }
  return EXIT_SUCCESS;
}

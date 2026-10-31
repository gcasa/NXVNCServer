/* Minimal AppKit boundary used to exercise the real native capture code. */
#import <Foundation/Foundation.h>
#define NSBorderlessWindowMask 0
#define NSBackingStoreNonretained 0
#define NSDeviceBlackColorSpace @"Black"
#define NSCalibratedBlackColorSpace @"CalibratedBlack"
#define NSDeviceWhiteColorSpace @"White"
#define NSCalibratedWhiteColorSpace @"CalibratedWhite"
#define NSDeviceRGBColorSpace @"RGB"
@interface NSDPSContext : NSObject
+ (void)setCurrentContext:(id)context;
- (void)printFormat:(NSString *)format, ...;
- (void)flush;
- (void)wait;
@end
@interface NSApplication : NSObject
+ (id)sharedApplication;
- (NSDPSContext *)context;
@end
extern NSApplication *NSApp;
@interface NSScreen : NSObject
+ (id)mainScreen;
- (NSRect)frame;
- (NSDictionary *)deviceDescription;
@end
@interface NSView : NSObject
- (void)lockFocus;
- (void)unlockFocus;
@end
@interface NSWindow : NSObject
- (id)initWithContentRect:(NSRect)rect styleMask:(int)style backing:(int)backing defer:(BOOL)defer;
- (void)setAutodisplay:(BOOL)value;
- (void)setLevel:(int)level;
- (int)windowNumber;
- (NSView *)contentView;
- (void)orderOut:(id)sender;
- (void)orderFrontRegardless;
@end
@interface NSBitmapImageRep : NSObject {
  unsigned char *_data;
  int _w, _h, _stride, _bps;
}
- (id)initWithFocusedViewRect:(NSRect)rect;
- (void)getBitmapDataPlanes:(unsigned char **)planes;
- (int)bitsPerSample;
- (int)samplesPerPixel;
- (int)isPlanar;
- (int)bytesPerRow;
- (int)bitsPerPixel;
- (int)hasAlpha;
- (int)pixelsWide;
- (int)pixelsHigh;
- (NSString *)colorSpaceName;
@end
void NSConvertWindowNumberToGlobal(int local, unsigned int *global);

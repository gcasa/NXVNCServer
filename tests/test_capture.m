/* Runs the production capture class against a deterministic AppKit boundary.
   Verifies logic and call ordering; does not model Window Server rendering. */
#import <AppKit/AppKit.h>
#import "NXVNCFramebuffer.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static int visible, waits, autofills, serviced, sampleBits=2, phase, failRead;
static NSRect lastRect;
NSApplication *NSApp;
@implementation NSDPSContext
+ (void)setCurrentContext:(id)context {}
- (void)printFormat:(NSString *)format, ... { autofills++; }
- (void)flush {}
- (void)wait { waits++; }
@end
@implementation NSApplication
+ (id)sharedApplication { if(!NSApp) NSApp=[self new]; return NSApp; }
- (NSDPSContext *)context {
  static NSDPSContext *context;
  if(!context) context=[NSDPSContext new]; return context;
}
@end
@implementation NSScreen
+ (id)mainScreen { static id screen; if(!screen) screen=[self new]; return screen; }
- (NSRect)frame { return NSMakeRect(0,0,67,35); }
@end
@implementation NSView
- (void)lockFocus { assert(visible); }
- (void)unlockFocus { assert(visible); }
@end
@implementation NSWindow
- (id)initWithContentRect:(NSRect)rect styleMask:(int)style backing:(int)backing defer:(BOOL)defer {
  return [super init];
}
- (void)setAutodisplay:(BOOL)value {}
- (void)setLevel:(int)level {}
- (int)windowNumber { return 1; }
- (NSView *)contentView { static id view; if(!view) view=[NSView new]; return view; }
- (void)orderOut:(id)sender { visible=0; }
- (void)orderFrontRegardless { assert(!visible); visible=1; }
@end
void NSConvertWindowNumberToGlobal(int local, unsigned int *global) { *global=local; }
static unsigned char shade(int x,int y) { return ((x+2*y+phase)%4)*85; }
@implementation NSBitmapImageRep
- (id)initWithFocusedViewRect:(NSRect)rect {
  int x,y,cx=(int)rect.origin.x,cy=35-(int)(rect.origin.y+rect.size.height);
  self=[super init]; assert(visible); lastRect=rect;
  _w=(int)rect.size.width; _h=(int)rect.size.height; _bps=sampleBits;
  _stride=(_w*_bps+7)/8+3; _data=calloc(_stride*_h,1);
  for(y=0;y<_h;y++) for(x=0;x<_w;x++) {
    unsigned g=shade(cx+x,cy+y);
    if(_bps==2) _data[y*_stride+x/4]|=(g/85)<<(6-2*(x%4));
    else _data[y*_stride+x]=(unsigned char)g;
  }
  return self;
}
- (void)getBitmapDataPlanes:(unsigned char **)planes {
  if(failRead) [NSException raise:@"CaptureFailure" format:@"test readback failure"];
  planes[0]=_data;
}
- (int)bitsPerSample { return _bps; }
- (int)samplesPerPixel { return 1; }
- (int)isPlanar { return 0; }
- (int)bytesPerRow { return _stride; }
- (int)bitsPerPixel { return _bps; }
- (int)hasAlpha { return 0; }
- (int)pixelsWide { return _w; }
- (int)pixelsHigh { return _h; }
- (NSString *)colorSpaceName { return @"White"; }
- (void)dealloc { free(_data); [super dealloc]; }
@end
static int service(void *context) { assert(!visible); serviced++; return 1; }
static void verify(NXVNCFramebuffer *fb,int x,int y,int w,int h) {
  int xx,yy;
  for(yy=y;yy<y+h;yy++) for(xx=x;xx<x+w;xx++) {
    const unsigned char *p=[fb pixels]+(yy*67+xx)*4;
    unsigned g=shade(xx,yy);
    assert(p[0]==0 && p[1]==g && p[2]==g && p[3]==g);
  }
}
int main(void) {
  NSAutoreleasePool *pool=[NSAutoreleasePool new];
  NXVNCScreenFramebuffer *fb=[NXVNCScreenFramebuffer new];
  unsigned char before[67*35*4];
  unsigned long oldVersion;
  int x,y;
  unsetenv("NXVNC_CAPTURE_SYNC"); unsetenv("NXVNC_FULL_CAPTURE");
  [fb setService:service context:0];
  assert([fb refresh]); verify(fb,0,0,67,35);
  assert(waits==2 && autofills==1 && serviced==2 && !visible);
  oldVersion=[fb tileVersions][0];
  assert([fb refresh]); assert(waits==4 && autofills==1);
  assert([fb tileVersions][0]==oldVersion);
  memcpy(before,[fb pixels],sizeof(before)); phase++;
  assert([fb refreshX:3 y:2 width:5 height:7]);
  assert(lastRect.origin.x==3 && lastRect.origin.y==26);
  assert(lastRect.size.width==5 && lastRect.size.height==7);
  verify(fb,3,2,5,7); assert(![fb tileVersions]);
  for(y=0;y<35;y++) for(x=0;x<67;x++)
    if(x<3 || x>=8 || y<2 || y>=9)
      assert(!memcmp([fb pixels]+(y*67+x)*4,before+(y*67+x)*4,4));
  assert([fb refresh]); verify(fb,0,0,67,35);
  assert([fb tileVersions][0]>oldVersion);
  sampleBits=8; phase++;
  assert([fb refreshX:65 y:34 width:2 height:1]); verify(fb,65,34,2,1);
  assert(![fb tileVersions]);
  assert(![fb refreshX:66 y:34 width:2 height:1]);
  assert(![fb refreshX:-1 y:0 width:1 height:1]);
  setenv("NXVNC_FULL_CAPTURE","1",1);
  assert([fb refreshX:3 y:2 width:5 height:7]); verify(fb,0,0,67,35);
  assert(lastRect.origin.y==0 && lastRect.size.width==67 && lastRect.size.height==35);
  setenv("NXVNC_CAPTURE_SYNC","1",1); waits=0;
  assert([fb refresh]); assert(waits==4 && !visible);
  failRead=1; assert(![fb refresh]); assert(!visible);
  failRead=0; assert([fb refresh]); verify(fb,0,0,67,35);
  [fb release]; [pool release];
  puts("PASS: native capture boundary, cropped coordinates, untouched pixels, cache invalidation, safe input callbacks, batched waits, compatibility paths, failure cleanup");
  return 0;
}

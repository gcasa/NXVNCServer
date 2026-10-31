/* Runs the production capture class against a deterministic AppKit boundary.
   Verifies logic and call ordering; does not model Window Server rendering. */
#import <AppKit/AppKit.h>
#import "NXVNCFramebuffer.h"
#import "NXVNCInterceptorFramebuffer.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
/* OPENSTEP libc has getenv but no setenv/unsetenv. Keep this fixture usable
   there as well as on macOS without changing the production environment API. */
extern char **environ;
static void testEnvironment(const char *name, const char *value) {
  static char **entries;
  static int count, capacity;
  int i;
  unsigned length=(unsigned)strlen(name);
  char *entry;
  if(!entries) {
    for(count=0;environ[count];count++) {}
    capacity=count+16;
    entries=calloc(capacity,sizeof(char *)); assert(entries);
    memcpy(entries,environ,count*sizeof(char *)); environ=entries;
  }
  for(i=0;i<count;i++)
    if(!strncmp(entries[i],name,length) && entries[i][length]=='=') break;
  if(!value) {
    if(i<count) { entries[i]=entries[--count]; entries[count]=0; }
    return;
  }
  entry=malloc(length+strlen(value)+2); assert(entry);
  sprintf(entry,"%s=%s",name,value);
  if(i==count) { assert(count+1<capacity); count++; }
  entries[i]=entry; entries[count]=0;
}
#define setenv(name,value,overwrite) testEnvironment(name,value)
#define unsetenv(name) testEnvironment(name,0)
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
- (NSDictionary *)deviceDescription {
  return [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0]
                                     forKey:@"NSScreenNumber"];
}
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

/* Loaded by name, just like the optional private framework. The source
   storage is independent of the canonical buffer and includes row padding. */
static unsigned char mappedData[35*(67*4+12)];
static int mappedBits=32, mappedAvailable=1, mappedNull, mappedThrow;
static int mappedWidth=67, mappedInvert, mappedBadEncoding, mappedShortRow;
static int mappedReads, changeAfterCopy, cancelService;
static int mapStride(void) { return mappedShortRow ? 1 : (67*mappedBits+7)/8+12; }
@interface NSFramebuffer : NSObject
- (id)initFromScreen:(int)screen andMapIfPossible:(char)map;
- (char)isMappable;
- (char *)data;
- (int)pixelsWide;
- (int)pixelsHigh;
- (int)bytesPerRow;
- (int)bitsPerPixel;
- (int)bitsPerSample;
- (int)samplesPerPixel;
- (char)isPlanar;
- (char)hasAlpha;
- (id)colorSpace;
- (id)pixelEncoding;
@end
@implementation NSFramebuffer
- (id)initFromScreen:(int)screen andMapIfPossible:(char)map {
  assert(screen==0 && map==1); return [super init];
}
- (char)isMappable {
  if(mappedThrow) [NSException raise:@"MappingFailure" format:@"test mapping failure"];
  return mappedAvailable;
}
- (char *)data { mappedReads++; return mappedNull ? 0 : (char *)mappedData; }
- (int)pixelsWide { return mappedWidth; }
- (int)pixelsHigh { return 35; }
- (int)bytesPerRow { return mapStride(); }
- (int)bitsPerPixel { return mappedBits; }
- (int)bitsPerSample { return mappedBits==32 ? 8 : mappedBits; }
- (int)samplesPerPixel { return mappedBits==32 ? 3 : 1; }
- (char)isPlanar { return 0; }
- (char)hasAlpha { return 0; }
- (id)colorSpace {
  return mappedBits==32 ? NSDeviceRGBColorSpace :
    (mappedInvert ? NSDeviceBlackColorSpace : NSDeviceWhiteColorSpace);
}
- (id)pixelEncoding {
  return mappedBadEncoding ? @"unknown" : @"--------RRRRRRRRGGGGGGGGBBBBBBBB";
}
@end
static void fillMapping(void) {
  int x,y;
  memset(mappedData,0,sizeof(mappedData));
  for(y=0;y<35;y++) for(x=0;x<67;x++) {
    unsigned char *row=mappedData+y*mapStride();
    if(mappedBits==32) {
      unsigned int r=(x*11+y+phase)&255, g=(x+y*7+phase*3)&255;
      unsigned int b=(y*2+x*5+phase*9)&255, word=(r<<16)|(g<<8)|b;
      memcpy(row+x*4,&word,4);
    } else if(mappedBits==2) row[x/4]|=(shade(x,y)/85)<<(6-2*(x%4));
    else row[x]=shade(x,y);
  }
}
static void verifyMapping(NXVNCFramebuffer *fb,int x,int y,int w,int h) {
  int xx,yy;
  for(yy=y;yy<y+h;yy++) for(xx=x;xx<x+w;xx++) {
    unsigned char *p=[fb pixels]+(yy*67+xx)*4;
    assert(p[0]==0);
    if(mappedBits==32) {
      assert(p[1]==((xx*11+yy+phase)&255));
      assert(p[2]==((xx+yy*7+phase*3)&255));
      assert(p[3]==((yy*2+xx*5+phase*9)&255));
    } else {
      unsigned g=mappedInvert ? 255-shade(xx,yy) : shade(xx,yy);
      assert(p[1]==g && p[2]==g && p[3]==g);
    }
  }
}
static int mappedService(void *context) {
  assert(!visible); serviced++;
  if(changeAfterCopy && serviced==2) memset(mappedData,255,sizeof(mappedData));
  return !cancelService;
}
static void interceptorTests(void) {
  NXVNCFramebuffer *fb;
  unsigned char before[67*35*4];
  unsigned long version=0;
  int x,y,i,reads;
  unsetenv("NXVNC_CAPTURE_SYNC"); unsetenv("NXVNC_FULL_CAPTURE");
  setenv("NXVNC_CAPTURE","dps",1);
  fb=NXVNCCreateScreenFramebuffer();
  assert(![fb isKindOfClass:[NXVNCInterceptorFramebuffer class]]); [fb release];
  setenv("NXVNC_CAPTURE","interceptor",1);
  for(i=0;i<3;i++) {
    mappedBits=i==0 ? 32 : i==1 ? 2 : 8;
    mappedInvert=i==2; phase=0; fillMapping();
    fb=NXVNCCreateScreenFramebuffer();
    assert([fb isKindOfClass:[NXVNCInterceptorFramebuffer class]]);
    [fb setService:mappedService context:0]; waits=autofills=serviced=0;
    assert([fb refresh]); verifyMapping(fb,0,0,67,35);
    assert(waits==0 && autofills==0 && serviced==2);
    if(mappedBits==2) {
      version=[fb tileVersions][0]; assert([fb refresh]);
      assert([fb tileVersions][0]==version);
    } else assert(![fb tileVersions]);
    /* Every two-bit alignment, single pixels, final row and column, and
       preservation of all off-request pixels. */
    for(x=0;x<4;x++) {
      memcpy(before,[fb pixels],sizeof(before)); phase++; fillMapping();
      assert([fb refreshX:x y:2 width:5 height:7]); verifyMapping(fb,x,2,5,7);
      assert(![fb tileVersions]);
      for(y=0;y<67*35;y++)
        if(y/67<2 || y/67>=9 || y%67<x || y%67>=x+5)
          assert(!memcmp([fb pixels]+y*4,before+y*4,4));
      assert([fb refreshX:x y:34 width:1 height:1]); verifyMapping(fb,x,34,1,1);
    }
    assert([fb refreshX:66 y:34 width:1 height:1]); verifyMapping(fb,66,34,1,1);
    assert(![fb refreshX:-1 y:0 width:1 height:1]);
    assert(![fb refreshX:66 y:34 width:2 height:1]);
    assert([fb refresh]); verifyMapping(fb,0,0,67,35);
    if(mappedBits==2) assert([fb tileVersions][0]>version);
    setenv("NXVNC_FULL_CAPTURE","1",1); phase++; fillMapping();
    assert([fb refreshX:5 y:2 width:1 height:1]); verifyMapping(fb,0,0,67,35);
    unsetenv("NXVNC_FULL_CAPTURE");
    /* Input after the copy may change the live mapping without changing the
       snapshot being converted, and cancellation must skip capture. */
    serviced=0; changeAfterCopy=1;
    assert([fb refresh]); verifyMapping(fb,0,0,67,35); changeAfterCopy=0;
    reads=mappedReads; cancelService=1;
    assert(![fb refresh]); assert(mappedReads==reads); cancelService=0;
    fillMapping(); mappedNull=1; sampleBits=8;
    assert([fb refreshX:3 y:2 width:5 height:7]); verify(fb,3,2,5,7);
    assert(![fb tileVersions] && waits==2 && !visible);
    mappedNull=0; reads=mappedReads;
    assert([fb refresh]); assert(mappedReads==reads); /* fallback is permanent */
    [fb release];
  }
  mappedBits=32; mappedInvert=0; fillMapping();
  for(i=0;i<6;i++) {
    mappedAvailable=i!=0; mappedBadEncoding=i==1; mappedWidth=i==2 ? 68 : 67;
    mappedShortRow=i==3; mappedThrow=i==4; mappedNull=i==5;
    fb=NXVNCCreateScreenFramebuffer();
    assert(fb && ![fb isKindOfClass:[NXVNCInterceptorFramebuffer class]]);
    [fb release];
  }
  mappedAvailable=1; mappedBadEncoding=mappedShortRow=mappedThrow=mappedNull=0;
  mappedWidth=67;
  fb=NXVNCCreateScreenFramebuffer(); mappedThrow=1;
  assert([fb refresh]); assert(![fb tileVersions]); [fb release]; mappedThrow=0;
  setenv("NXVNC_CAPTURE","invalid",1); assert(!NXVNCCreateScreenFramebuffer());
  unsetenv("NXVNC_CAPTURE");
  fb=NXVNCCreateScreenFramebuffer();
#ifdef __i386__
  assert([fb isKindOfClass:[NXVNCInterceptorFramebuffer class]]);
#else
  assert(![fb isKindOfClass:[NXVNCInterceptorFramebuffer class]]);
#endif
  [fb release];
  puts("PASS: Interceptor RGB/gray, padded rows, cropped edges and bit alignment, snapshot stability, cache versions, input callbacks, DPS selection and fallback");
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
  [fb release]; interceptorTests(); [pool release];
  puts("PASS: native capture boundary, cropped coordinates, untouched pixels, cache invalidation, safe input callbacks, batched waits, compatibility paths, failure cleanup");
  return 0;
}

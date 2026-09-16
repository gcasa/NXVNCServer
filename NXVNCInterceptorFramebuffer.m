/* Optional OPENSTEP Interceptor capture backend. GPL-3.0-or-later. */
#import "NXVNCInterceptorFramebuffer.h"
#import <AppKit/AppKit.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Only messages verified in Interceptor's metadata. The framework is loaded
   dynamically; no static NSFramebuffer class reference is emitted. */
@protocol NXVNCInterceptorBitmap
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

static Class interceptorClass(void)
{
  Class cls = NSClassFromString(@"NSFramebuffer");
  if (!cls) {
    NSBundle *bundle = [NSBundle bundleWithPath:
      @"/NextLibrary/PrivateFrameworks/Interceptor.framework"];
    if ([bundle load]) cls = NSClassFromString(@"NSFramebuffer");
  }
  return cls;
}

/* Reject layouts whose memory interpretation has not been implemented. */
static int mappedFormat(id<NXVNCInterceptorBitmap> fb, int w, int h,
                        int *stride, int *bits, int *invert)
{
  int bps, spp;
  id space;
  if (!fb || ![fb isMappable] || [fb pixelsWide] != w || [fb pixelsHigh] != h
      || [fb isPlanar] || [fb hasAlpha]) return 0;
  *stride = [fb bytesPerRow]; *bits = [fb bitsPerPixel]; *invert = 0;
  bps = [fb bitsPerSample]; spp = [fb samplesPerPixel];
  space = [fb colorSpace];
  if (spp == 1 && bps == *bits && (bps == 2 || bps == 8)) {
    if ([space isEqual:NSDeviceBlackColorSpace]
        || [space isEqual:NSCalibratedBlackColorSpace]) *invert = 1;
    else if (![space isEqual:NSDeviceWhiteColorSpace]
             && ![space isEqual:NSCalibratedWhiteColorSpace]) return 0;
  } else if (!(spp == 3 && bps == 8 && *bits == 32
               && [space isEqual:NSDeviceRGBColorSpace]
               && [[fb pixelEncoding]
                    isEqual:@"--------RRRRRRRRGGGGGGGGBBBBBBBB"])) return 0;
  return *stride >= (w * *bits + 7) / 8 && *stride <= 65536;
}

@implementation NXVNCInterceptorFramebuffer
- init
{
  volatile int ready = 0;
  Class cls;
  id number;
  int screen = 0;
  /* The inherited capture window stays hidden unless fallback is needed. */
  self = [super init];
  if (!self) return nil;
  NS_DURING
    cls = interceptorClass();
    number = [[[NSScreen mainScreen] deviceDescription]
                objectForKey:@"NSScreenNumber"];
    if (number) screen = [number intValue];
    if (cls && _width > 0 && _height > 0 && _width <= 8192 && _height <= 8192) {
      _mappedFramebuffer = [[cls alloc] initFromScreen:screen andMapIfPossible:1];
      if (mappedFormat(_mappedFramebuffer, _width, _height,
                        &_mappedStride, &_mappedBits, &_mappedInvert)
          && [_mappedFramebuffer data]) {
        _snapshot = malloc((unsigned long)((_width*_mappedBits+7)/8)*_height);
        ready = _snapshot != 0;
      }
    }
  NS_HANDLER
    NSLog(@"NXVNC: Interceptor initialization failed: %@", localException);
  NS_ENDHANDLER
  if (!ready) { [self release]; return nil; }
  fprintf(stderr, "NXVNC: capture backend Interceptor screen=%d %dx%d "
          "bpp=%d stride=%d\n", screen, _width, _height, _mappedBits, _mappedStride);
  return self;
}

- (int) refreshX:(int)cx y:(int)cy width:(int)cw height:(int)ch
{
  volatile int copied = 0;
  int x, y, bits, stride, invert, rowBytes, byteOffset, firstPixel;
  unsigned int endian = 1;
  double start, converted;
  NSRect frame;
  const unsigned char *source;
  if (!_mappedFramebuffer)
    return [super refreshX:cx y:cy width:cw height:ch];
  if (cx < 0 || cy < 0 || cw <= 0 || ch <= 0
      || cx > _width-cw || cy > _height-ch) return 0;
  if (getenv("NXVNC_FULL_CAPTURE")) { cx = cy = 0; cw = _width; ch = _height; }
  if (_service && !_service(_serviceContext)) return 0;
  start = NXVNCNow();
  _captureSeconds = _conversionSeconds = _packedCompareSeconds = 0;
  byteOffset = cx*_mappedBits/8;
  firstPixel = _mappedBits == 2 ? cx % 4 : 0;
  rowBytes = ((cw+firstPixel)*_mappedBits+7)/8;
  NS_DURING
    frame = [[NSScreen mainScreen] frame];
    if ((int)frame.size.width == _width && (int)frame.size.height == _height
        && mappedFormat(_mappedFramebuffer, _width, _height, &stride, &bits, &invert)
        && stride == _mappedStride && bits == _mappedBits && invert == _mappedInvert) {
      source = (const unsigned char *)[_mappedFramebuffer data];
      if (source) {
        /* Copy only requested rows/columns. A snapshot keeps conversion and
           dirty tracking consistent, though the live copy can still tear.
           Interceptor's i386 framebuffer locks provide no synchronization. */
        source += (unsigned long)cy*stride+byteOffset;
        if (rowBytes == stride)
          memcpy(_snapshot, source, (unsigned long)rowBytes*ch);
        else for (y = 0; y < ch; y++)
          memcpy(_snapshot+(unsigned long)y*rowBytes,
                 source+(unsigned long)y*stride, rowBytes);
        copied = 1;
      }
    }
  NS_HANDLER
    NSLog(@"NXVNC: Interceptor capture failed: %@", localException);
  NS_ENDHANDLER
  if (!copied) {
    fprintf(stderr, "NXVNC: Interceptor mapping changed or unavailable; "
            "falling back to DPS\n");
    [_mappedFramebuffer release]; _mappedFramebuffer = nil;
    free(_snapshot); _snapshot = 0;
    _usingGrayCache = 0; _grayCache.valid = 0; _loggedCapture = 0;
    return [super refreshX:cx y:cy width:cw height:ch];
  }
  _captureSeconds = NXVNCNow()-start;
  if (_service && !_service(_serviceContext)) return 0;
  converted = NXVNCNow();
  _usingGrayCache = _mappedBits == 2 && cx == 0 && cy == 0
                    && cw == _width && ch == _height;
  if (_usingGrayCache && !_grayCache.previous)
    _usingGrayCache = NXVNCInitGrayCache(&_grayCache, _width, _height);
  if (_usingGrayCache) {
    NXVNCRefreshGrayCache(&_grayCache, _snapshot, rowBytes, _mappedInvert,
                          _pixels, &_packedCompareSeconds, &_conversionSeconds);
  } else {
    _grayCache.valid = 0;
    for (y = 0; y < ch; y++) {
      const unsigned char *src = _snapshot+(unsigned long)y*rowBytes;
      unsigned char *dst = _pixels+((unsigned long)(cy+y)*_width+cx)*4;
      if (_mappedBits == 32) {
        for (x = 0; x < cw; x++, src += 4, dst += 4) {
          dst[0] = 0;
          if (*(unsigned char *)&endian) {
            dst[1] = src[2]; dst[2] = src[1]; dst[3] = src[0];
          } else {
            dst[1] = src[1]; dst[2] = src[2]; dst[3] = src[3];
          }
        }
      } else if (_mappedBits == 2) {
        /* The first copied byte can start before an unaligned RFB request. */
        x = 0;
        if (firstPixel) {
          for (; x < cw && x+firstPixel < 4; x++, dst += 4) {
            unsigned char g = ((*src >> (6-2*(x+firstPixel))) & 3)*85;
            if (_mappedInvert) g = 255-g;
            dst[0] = 0; dst[1] = dst[2] = dst[3] = g;
          }
          src++;
        }
        if (x < cw) NXVNCExpandGray2(src, dst, cw-x, _mappedInvert);
      } else {
        for (x = 0; x < cw; x++, dst += 4) {
          unsigned char g = _mappedInvert ? 255-src[x] : src[x];
          dst[0] = 0; dst[1] = dst[2] = dst[3] = g;
        }
      }
    }
    _conversionSeconds = NXVNCNow()-converted;
  }
  if (getenv("NXVNC_PROFILE") || !_loggedCapture)
    fprintf(stderr, "NXVNC: capture stages mode=interceptor area=%dx%d+%d+%d "
            "snapshot=%.3fs packedCompare=%.3fs convert=%.3fs\n",
            cw, ch, cx, cy, _captureSeconds, _packedCompareSeconds, _conversionSeconds);
  _loggedCapture = 1;
  return 1;
}

- (void) dealloc
{
  [_mappedFramebuffer release]; free(_snapshot);
  [super dealloc];
}
@end

NXVNCFramebuffer *NXVNCCreateScreenFramebuffer(void)
{
  const char *mode = getenv("NXVNC_CAPTURE");
  NXVNCFramebuffer *fb = nil;
  int useInterceptor = 0;
#ifdef __i386__
  useInterceptor = 1;
#endif
  if (mode && !strcmp(mode, "dps")) useInterceptor = 0;
  else if (mode && !strcmp(mode, "interceptor")) useInterceptor = 1;
  else if (mode && strcmp(mode, "auto")) {
    fprintf(stderr, "NXVNC: unknown NXVNC_CAPTURE '%s' (use auto, dps, or interceptor)\n", mode);
    return nil;
  }
  if (useInterceptor) {
    fb = [NXVNCInterceptorFramebuffer new];
    if (!fb) fprintf(stderr, "NXVNC: Interceptor unavailable or unsupported; falling back to DPS\n");
  }
  if (!fb) {
    fb = [NXVNCScreenFramebuffer new];
    if (fb) fprintf(stderr, "NXVNC: capture backend DPS\n");
  }
  return fb;
}

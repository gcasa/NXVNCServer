/* NXVNCFramebuffer.m - NXVNCserver implementation
 Copyright (C) 2026 NXVNCserver contributors

 This file is part of NXVNCserver.

 NXVNCserver is free software: you can redistribute it and/or modify it
 under the terms of the GNU General Public License as published by the
 Free Software Foundation, either version 3 of the License, or (at your
 option) any later version.

 NXVNCserver is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 General Public License for more details.

 You should have received a copy of the GNU General Public License along
 with NXVNCserver.  If not, see <https://www.gnu.org/licenses/>.  */

#import "NXVNCFramebuffer.h"
#include "NXVNCEncoding.h"
#import <AppKit/AppKit.h>
#import <AppKit/NSGraphics.h>
#import <Foundation/NSException.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Bitmap samples are packed most-significant bit first. Expand to RFB's
   eight-bit channels, including NeXT's two-bit gray and four-bit RGB. */
static unsigned char NXVNCReadSample(const unsigned char *row,
                                    unsigned long bit, int bits)
{
  unsigned value = 0;
  int i;
  if (bits == 8 && (bit & 7) == 0) return row[bit >> 3];
  for (i = 0; i < bits; i++, bit++)
    value = (value << 1) | ((row[bit >> 3] >> (7 - (bit & 7))) & 1);
  return (unsigned char)(value * 255 / ((1U << bits) - 1));
}

/* Allow AppKit to manage ordering without painting over captured pixels. */
@interface NXVNCCaptureWindow : NSWindow
@end

@implementation NXVNCCaptureWindow
- (void) display
{
}
- (void) displayIfNeeded
{
}
@end

@implementation NXVNCFramebuffer
- (void) setService: (int (*)(void *))service context: (void *)context
{ _service=service; _serviceContext=context; }
- initWidth: (int)width
   height: (int)height
{
  [super init];
  _width = width;
  _height = height;
  _pixels = (NXVNCByte *)malloc((unsigned)(width * height * 4));
  if (_pixels == 0)
    {
      [self release];
      return nil;
    }
  memset(_pixels, 0, (unsigned)(width * height * 4));
  return self;
}
- (int) width
{
  return _width;
}
- (int) height
{
  return _height;
}
- (NXVNCByte *) pixels
{
  return _pixels;
}
- (int) refresh
{
  return 1;
}
- (int) refreshX: (int)x y: (int)y width: (int)w height: (int)h
{
  return [self refresh];
}
- (double) captureSeconds { return _captureSeconds; }
- (double) conversionSeconds { return _conversionSeconds; }
- (double) packedCompareSeconds { return _packedCompareSeconds; }
- (const unsigned long *) tileVersions { return 0; }
- (void) dealloc
{
  if (_pixels != 0) free(_pixels);
  _pixels = 0;
  [super dealloc];
}
@end

@implementation NXVNCTestFramebuffer
- (int) refresh
{
  int x, y;
  NXVNCByte *p;
  _tick++;
  for (y = 0; y < _height; y++) {
    p = _pixels + y * _width * 4;
    for (x = 0; x < _width; x++) {
      /* RFB pixel is 00rrggbb on a big-endian NeXT. */
      *p++ = 0;
      *p++ = (NXVNCByte)((x + _tick) & 255);
      *p++ = (NXVNCByte)((y + _tick) & 255);
      *p++ = (NXVNCByte)((x ^ y) & 255);
    }
  }
  return 1;
}
@end

@implementation NXVNCScreenFramebuffer
- init
{
  NSRect frame;

  [NSApplication sharedApplication];
  frame = [[NSScreen mainScreen] frame];
  self = [super initWidth: (int)frame.size.width
                   height: (int)frame.size.height];
  if (self == nil) return nil;
  _captureWindow = [[NXVNCCaptureWindow alloc] initWithContentRect: frame
                           styleMask: NSBorderlessWindowMask
                             backing: NSBackingStoreNonretained
                               defer: NO];
  if (_captureWindow == nil)
    {
      [self release];
      return nil;
    }
  [_captureWindow setAutodisplay: NO];
  [_captureWindow setLevel: 100];
  return self;
}

- (int) refresh
{
  return [self refreshX:0 y:0 width:_width height:_height];
}

- (int) refreshX: (int)cx y: (int)cy width: (int)cw height: (int)ch
{
  NSBitmapImageRep * volatile image = nil;
  NSDPSContext *context;
  NSView *view;
  const char * volatile stage = "preparing capture";
  int windowNumber;
  unsigned int globalWindowNumber = 0;
  NSRect frame;
  unsigned char *planes[5];
  int x, y, i, rowBytes, spp, planar, bps, pixelBits, colors, invertGray;
  NSString *colorSpace;
  double captureStart = NXVNCNow(), conversionStart;
  double setupTime=0, orderTime=0, focusTime=0, readTime=0;
  double materializeTime=0, unfocusTime=0, hideTime=0, stageStart;
  int syncCapture=getenv("NXVNC_CAPTURE_SYNC")!=0;
  int profile=getenv("NXVNC_PROFILE")!=0;

  if (cx<0 || cy<0 || cw<=0 || ch<=0 || cx>_width-cw || cy>_height-ch) return 0;
  if (getenv("NXVNC_FULL_CAPTURE")) { cx=cy=0; cw=_width; ch=_height; }
  if (_service && !_service(_serviceContext)) return 0;

  context = [NSApp context];
  [NSDPSContext setCurrentContext: context];
  windowNumber = [_captureWindow windowNumber];
  if (windowNumber <= 0)
    {
      fprintf(stderr, "NXVNC: capture window has invalid ID %d\n", windowNumber);
      return 0;
    }
  /* OPENSTEP's AppKit window numbers are local to the application. Raw
     PostScript operators require the Window Server's global window ID. */
  NSConvertWindowNumberToGlobal(windowNumber, &globalWindowNumber);
  if (globalWindowNumber == 0)
    {
      fprintf(stderr, "NXVNC: no global ID for capture window %d\n",
              windowNumber);
      return 0;
    }
  view = [_captureWindow contentView];
  /* RFB coordinates start at the top; the unflipped capture view starts at
     the bottom. Bitmap rows are still returned in top-to-bottom order. */
  frame = NSMakeRect((float)cx, (float)(_height-cy-ch), (float)cw, (float)ch);
  for (i = 0; i < 5; i++) planes[i] = 0;

  /* setautofill applies only to nonretained windows. With filling disabled,
     ordering this window in leaves the existing screen pixels in place for
     readback. A retained window would expose its own backing store instead.
     AppKit performs ordering to keep its window list in sync with the server. */
  NS_DURING
    stageStart=NXVNCNow();
    stage = "disabling autofill";
    if (!_captureConfigured || syncCapture) {
      [context printFormat: @"false %u setautofill\n", globalWindowNumber];
      if(syncCapture) { [context flush]; [context wait]; }
    }
    /* The previous refresh already ordered this window out. The compatibility
       switch retains the original sequence for native A/B testing. */
    if(syncCapture) {
      stage = "ordering capture window out";
      [_captureWindow orderOut: nil];
      [context flush]; [context wait];
    }
    setupTime=NXVNCNow()-stageStart; stageStart=NXVNCNow();
    stage = "ordering capture window in";
    [_captureWindow orderFrontRegardless];
    [context flush];
    [context wait];
    _captureConfigured=1;
    orderTime=NXVNCNow()-stageStart; stageStart=NXVNCNow();
    stage = "focusing capture window";
    [view lockFocus];
    focusTime=NXVNCNow()-stageStart; stageStart=NXVNCNow();
    stage = "reading capture bitmap";
    image = [[NSBitmapImageRep alloc] initWithFocusedViewRect: frame];
    readTime=NXVNCNow()-stageStart; stageStart=NXVNCNow();
    /* Materialize the bitmap while its source is still focused and visible. */
    stage = "loading capture pixels";
    [image getBitmapDataPlanes: planes];
    materializeTime=NXVNCNow()-stageStart; stageStart=NXVNCNow();
    /* OPENSTEP focus locking installs exception cleanup. Balance it before
       NS_HANDLER removes our enclosing handler, in reverse nesting order. */
    stage = "unlocking capture window";
    [view unlockFocus];
    unfocusTime=NXVNCNow()-stageStart;
  NS_HANDLER
    fprintf(stderr, "NXVNC: screen capture failed while %s "
            "(AppKit window %d, global window %u)\n",
            stage, windowNumber, globalWindowNumber);
    NSLog(@"NXVNC: %@", localException);
    [image release];
    image = nil;
    _captureConfigured=0;
  NS_ENDHANDLER

  /* On an exception, AppKit unwinds the focus lock before our handler runs.
     Do not unlock it a second time here. */
  stageStart=NXVNCNow();
  [_captureWindow orderOut: nil];
  [context flush];
  [context wait];
  if (image == nil)
    {
      fprintf(stderr, "NXVNC: screen capture returned no bitmap\n");
      [image release];
      return 0;
    }

  hideTime=NXVNCNow()-stageStart;
  _captureSeconds = NXVNCNow() - captureStart;
  if(profile || !_loggedCapture)
    fprintf(stderr,"NXVNC: capture stages mode=%s area=%dx%d+%d+%d setup=%.3fs order/wait=%.3fs "
            "focus=%.3fs readback=%.3fs materialize=%.3fs unfocus=%.3fs hide/wait=%.3fs\n",
            syncCapture ? "sync" : "batched",cw,ch,cx,cy,setupTime,orderTime,focusTime,
            readTime,materializeTime,unfocusTime,hideTime);
  /* Never inject input while the temporary capture window covers the screen. */
  if (_service && !_service(_serviceContext)) { [image release]; return 0; }
  conversionStart = NXVNCNow();
  bps = [image bitsPerSample];
  spp = [image samplesPerPixel];
  planar = [image isPlanar];
  rowBytes = [image bytesPerRow];
  pixelBits = planar ? bps : [image bitsPerPixel];
  colors = spp - ([image hasAlpha] ? 1 : 0);
  colorSpace = [image colorSpaceName];
  invertGray = [colorSpace isEqual: NSDeviceBlackColorSpace]
               || [colorSpace isEqual: NSCalibratedBlackColorSpace];
  if ((bps != 1 && bps != 2 && bps != 4 && bps != 8)
      || (colors != 1 && colors != 3)
      || spp < 1 || spp > 4 || rowBytes <= 0
      || pixelBits < bps * (planar ? 1 : spp)
      || [image pixelsWide] != cw || [image pixelsHigh] != ch
      || (unsigned long)rowBytes <
         ((unsigned long)cw * pixelBits + 7) / 8)
    {
      fprintf(stderr, "NXVNC: unsupported capture bitmap: %dx%d, "
              "%d bits/sample, %d samples/pixel, %d bits/pixel, "
              "%d bytes/row, planar=%d, colors=%d\n",
              [image pixelsWide], [image pixelsHigh], bps, spp,
              pixelBits, rowBytes, planar, colors);
      [image release];
      return 0;
    }
  for (i = 0; i < (planar ? spp : 1); i++)
    if (planes[i] == 0)
      {
        fprintf(stderr, "NXVNC: capture bitmap is missing plane %d\n", i);
        [image release];
        return 0;
      }

  _usingGrayCache = bps == 2 && spp == 1 && pixelBits == 2
                    && cx==0 && cy==0 && cw==_width && ch==_height;
  if (_usingGrayCache && !_grayCache.previous)
    _usingGrayCache = NXVNCInitGrayCache(&_grayCache,_width,_height);
  if (_usingGrayCache) {
    NXVNCRefreshGrayCache(&_grayCache,planes[0],rowBytes,invertGray,_pixels,
                          &_packedCompareSeconds,&_conversionSeconds);
  } else {
    /* Format transitions must invalidate the cached packed image. */
    _grayCache.valid=0; _packedCompareSeconds=0;
    /* NSBitmapImageRep returns top-to-bottom rows, as required by RFB.
       Convert planar or meshed gray/RGB into RFB's 00rrggbb. */
    for (y = 0; y < ch; y++) {
      unsigned char *src;
      unsigned char *dst = _pixels + ((unsigned long)(cy+y)*_width+cx)*4;
      src = planes[0] + y * rowBytes;
      if(bps==2 && spp==1 && pixelBits==2) {
        NXVNCExpandGray2(src,dst,cw,invertGray);
        continue;
      }
      for (x = 0; x < cw; x++) {
        unsigned char red, green, blue;
        unsigned long bit = (unsigned long)x * pixelBits;
        red = NXVNCReadSample(src, bit, bps);
        if (colors == 1) {
          if (invertGray) red = 255 - red;
          green = blue = red;
        }
        else if (planar) {
          green = NXVNCReadSample(planes[1] + y * rowBytes,
                                 bit, bps);
          blue = NXVNCReadSample(planes[2] + y * rowBytes,
                                bit, bps);
        }
        else {
          green = NXVNCReadSample(src, bit + bps, bps);
          blue = NXVNCReadSample(src, bit + 2 * bps, bps);
        }
        *dst++ = 0; *dst++ = red; *dst++ = green; *dst++ = blue;
      }
    }
    _conversionSeconds = NXVNCNow() - conversionStart;
  }
  if (!_loggedCapture) {
    fprintf(stderr, "NXVNC: first capture %dx%d, bps=%d, spp=%d, "
            "bpp=%d, rowBytes=%d, planar=%d, alpha=%d\n",
            _width, _height, bps, spp, [image bitsPerPixel], rowBytes,
            planar, (int)[image hasAlpha]);
    _loggedCapture = 1;
  }
  [image release];
  return 1;
}

- (const unsigned long *) tileVersions
{
  return _usingGrayCache ? _grayCache.versions : 0;
}

- (void) dealloc
{
  NXVNCFreeGrayCache(&_grayCache);
  [_captureWindow release];
  [super dealloc];
}
@end

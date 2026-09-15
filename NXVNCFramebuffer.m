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
#import <AppKit/NSApplication.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSScreen.h>
#import <DPSClient/NSDPSContext.h>
#include <stdlib.h>
#include <string.h>

@implementation NXVNCFramebuffer
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
  return [super initWidth: (int)frame.size.width
                   height: (int)frame.size.height];
}

- (int) refresh
{
  NSBitmapImageRep *image;
  NSDPSContext *context;
  NSRect frame;
  unsigned char *planes[5];
  int x, y, i, rowBytes, spp, planar;

  context = [NSApp context];
  [NSDPSContext setCurrentContext: context];
  [context printFormat: @"0 setwindow\n"];
  [context flush];
  [context wait];

  frame = NSMakeRect(0.0, 0.0, (float)_width, (float)_height);
  image = [[NSBitmapImageRep alloc] initWithFocusedViewRect: frame];
  if (image == nil || [image bitsPerSample] != 8)
    {
      [image release];
      return 0;
    }

  spp = [image samplesPerPixel];
  planar = [image isPlanar];
  rowBytes = [image bytesPerRow];
  if (spp < 1 || spp > 5 || rowBytes <= 0)
    {
      [image release];
      return 0;
    }
  for (i = 0; i < 5; i++) planes[i] = 0;
  [image getBitmapDataPlanes: planes];

  /* Convert planar or meshed gray/RGB into RFB's 00rrggbb. */
  for (y = 0; y < _height; y++) {
    unsigned char *src;
    unsigned char *dst = _pixels + y * _width * 4;
    src = planes[0] + (_height - 1 - y) * rowBytes;
    for (x = 0; x < _width; x++) {
      unsigned char red, green, blue;
      if (spp < 3) {
        if (planar) red = green = blue =
          planes[0][(_height - 1 - y) * rowBytes + x];
        else red = green = blue = src[x * spp];
      }
      else if (planar) {
        red = planes[0][(_height - 1 - y) * rowBytes + x];
        green = planes[1][(_height - 1 - y) * rowBytes + x];
        blue = planes[2][(_height - 1 - y) * rowBytes + x];
      }
      else {
        red = src[x * spp];
        green = src[x * spp + 1];
        blue = src[x * spp + 2];
      }
      *dst++ = 0; *dst++ = red; *dst++ = green; *dst++ = blue;
    }
  }
  [image release];
  return 1;
}
@end

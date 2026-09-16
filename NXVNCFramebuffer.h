/* NXVNCFramebuffer.h - Frame buffer interfaces for NXVNCserver
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

#ifndef _NXVNCFramebuffer_h_GNUSTEP_BASE_INCLUDE
#define _NXVNCFramebuffer_h_GNUSTEP_BASE_INCLUDE

#import <Foundation/NSObject.h>
#include "NXVNCEncoding.h"

typedef unsigned char NXVNCByte;
@class NSWindow;

/**
 * NXVNCFramebuffer stores a display image in the canonical RFB pixel format.
 * Subclasses override <code>-refresh</code> to acquire a new display image.
 */
@interface NXVNCFramebuffer : NSObject
{
  int _width;
  int _height;
  NXVNCByte *_pixels;
  double _captureSeconds, _conversionSeconds, _packedCompareSeconds;
  int (*_service)(void *);
  void *_serviceContext;
}
/** Initializes a frame buffer having the supplied pixel dimensions. */
- initWidth: (int)width
   height: (int)height;
/** Returns the frame buffer width in pixels. */
- (int) width;
/** Returns the frame buffer height in pixels. */
- (int) height;
/** Returns the canonical 32-bit, big-endian RFB pixel storage. */
- (NXVNCByte *) pixels;
/** Refreshes the pixel storage and returns nonzero on success. */
- (int) refresh;
/** Refreshes a requested region; generic providers fall back to full refresh. */
- (int) refreshX: (int)x y: (int)y width: (int)w height: (int)h;
/** Services network input between safe capture stages; zero aborts refresh. */
- (void) setService: (int (*)(void *))service context: (void *)context;
- (double) captureSeconds;
- (double) conversionSeconds;
- (double) packedCompareSeconds;
/** Version per global 32x32 tile, or NULL for generic framebuffers. */
- (const unsigned long *) tileVersions;
/** Releases resources owned by the receiver. */
- (void) dealloc;
@end

/**
 * NXVNCTestFramebuffer generates an animated test image for protocol tests
 * performed without a NeXT Window Server.
 */
@interface NXVNCTestFramebuffer : NXVNCFramebuffer
{
  unsigned long _tick;
}
- (int) refresh;
@end

/**
 * NXVNCScreenFramebuffer reads the display through a capture window.
 */
@interface NXVNCScreenFramebuffer : NXVNCFramebuffer
{
  NSWindow *_captureWindow;
  int _loggedCapture, _captureConfigured;
  NXVNCGrayCache _grayCache;
  int _usingGrayCache;
}
/** Initializes a frame buffer with the dimensions of the primary screen. */
- init;
/** Reads and converts the current screen image. */
- (int) refresh;
- (void) dealloc;
@end

#endif /* _NXVNCFramebuffer_h_GNUSTEP_BASE_INCLUDE */

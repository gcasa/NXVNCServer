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

#import <objc/Object.h>

typedef unsigned char NXVNCByte;

/**
 * NXVNCFramebuffer stores a display image in the canonical RFB pixel format.
 * Subclasses override <code>-refresh</code> to acquire a new display image.
 */
@interface NXVNCFramebuffer : Object
{
  int _width;
  int _height;
  NXVNCByte *_pixels;
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
/** Releases the pixel storage and the receiver. */
- free;
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

#ifdef NEXTSTEP
/**
 * NXVNCScreenFramebuffer reads the root display through Display PostScript.
 */
@interface NXVNCScreenFramebuffer : NXVNCFramebuffer
/** Initializes a frame buffer with the dimensions of the primary screen. */
- init;
/** Reads and converts the current root-window image. */
- (int) refresh;
@end
#endif

#endif /* _NXVNCFramebuffer_h_GNUSTEP_BASE_INCLUDE */

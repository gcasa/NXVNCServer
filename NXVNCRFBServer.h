/* NXVNCRFBServer.h - RFB server interface for NXVNCserver
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

#ifndef _NXVNCRFBServer_h_GNUSTEP_BASE_INCLUDE
#define _NXVNCRFBServer_h_GNUSTEP_BASE_INCLUDE

#import <Foundation/NSObject.h>
#include "NXVNCEncoding.h"
#include "NXVNCInput.h"
@class NXVNCFramebuffer;

/**
 * NXVNCRFBServer accepts one RFB 3.3 client at a time and supplies encoded
 * framebuffer updates using an associated NXVNCFramebuffer.
 */
@interface NXVNCRFBServer : NSObject
{
  int _listenSocket;
  int _clientSocket;
  int _port;
  NXVNCFramebuffer *_framebuffer;
  int _bitsPerPixel;
  int _bigEndian;
  unsigned _redMax, _greenMax, _blueMax;
  int _redShift, _greenShift, _blueShift;
  NXVNCPixelFormat _format;
  unsigned char *_previous;
  unsigned long *_seenVersions;
  unsigned _versionCount;
  unsigned char _output[32768];
  unsigned _outputCount;
  unsigned long _wireBytes, _updateNumber;
  double _sendSeconds, _lastRefresh, _refreshInterval;
  int _encoding, _profile;
  NXVNCInput *_input;
}
/** Initializes the server to publish framebuffer on the specified TCP port. */
- initWithFramebuffer: (NXVNCFramebuffer *)framebuffer
         port: (int)port;
/** Runs the blocking accept loop and returns zero after a fatal error. */
- (int) run;
/** The caller owns input and keeps it alive until the server is released. */
- (void) setInput: (NXVNCInput *)input;
/** Closes open sockets and releases resources owned by the receiver. */
- (void) dealloc;
@end

#endif /* _NXVNCRFBServer_h_GNUSTEP_BASE_INCLUDE */

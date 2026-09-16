/* main.m - NXVNCserver implementation
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
#import "NXVNCInterceptorFramebuffer.h"
#import "NXVNCRFBServer.h"
#include "NXVNCStartup.h"
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
  int port = 5900;
  int testPattern = 0, portSeen = 0, viewOnly = 0, i;
  NXVNCInput input;
  NSAutoreleasePool *pool;
  NXVNCFramebuffer *fb;
  NXVNCRFBServer *server;

  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--test") == 0) testPattern = 1;
    else if (strcmp(argv[i], "--view-only") == 0) viewOnly = 1;
    else if (!portSeen) { port = atoi(argv[i]); portSeen = 1; }
    else { port = 0; break; }
  }
  if (port < 1 || port > 65535) {
    fprintf(stderr, "usage: %s [port] [--test] [--view-only]\n", argv[0]);
    return 2;
  }
  if (!NXVNCPrepareInput(&input,!testPattern && !viewOnly)) return 1;
  pool = [NSAutoreleasePool new];
  if (testPattern) {
    fb = [[NXVNCTestFramebuffer alloc] initWidth:640 height:480];
    fprintf(stderr, "NXVNC: test pattern enabled (640x480)\n");
  } else fb = NXVNCCreateScreenFramebuffer();
  if (fb == nil) {
    fprintf(stderr, "NXVNC: cannot create framebuffer\n");
    NXVNCInputClose(&input); [pool release]; return 1;
  }
  if ([fb width]<1 || [fb height]<1 || [fb width]>32768 || [fb height]>32768) {
    fprintf(stderr,"NXVNC: unsupported framebuffer dimensions\n");
    NXVNCInputClose(&input); [fb release]; [pool release]; return 1;
  }
  input.width=[fb width]; input.height=[fb height];
  server = [[NXVNCRFBServer alloc] initWithFramebuffer:fb port:port];
  if (server && input.post) [server setInput:&input];
  [fb release];
  if (![server run])
    {
      [server release];
      NXVNCInputClose(&input);
      [pool release];
      return 1;
    }
  [server release];
  NXVNCInputClose(&input);
  [pool release];
  return 0;
}

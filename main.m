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
#import "NXVNCRFBServer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
  int port = 5900;
  NXVNCFramebuffer *fb;
  NXVNCRFBServer *server;
  if (argc > 1) port = atoi(argv[1]);
  if (port < 1 || port > 65535) {
    fprintf(stderr, "usage: %s [port]\n", argv[0]);
    return 2;
  }
#ifdef NEXTSTEP
  fb = [NXVNCScreenFramebuffer new];
#else
  fb = [[NXVNCTestFramebuffer alloc] initWidth:640 height:480];
#endif
  if (fb == nil) { fprintf(stderr, "NXVNC: cannot create framebuffer\n"); return 1; }
  server = [[NXVNCRFBServer alloc] initWithFramebuffer:fb port:port];
  if (![server run]) return 1;
  return 0;
}

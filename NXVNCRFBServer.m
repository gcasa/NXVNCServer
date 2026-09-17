/* NXVNCRFBServer.m - NXVNCserver implementation
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

#import "NXVNCRFBServer.h"
#import "NXVNCFramebuffer.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <netinet/tcp.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
/* OPENSTEP declares read(), write(), and close() in libc.h. */
#ifndef __APPLE__
#include <libc.h>
#endif
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>

static int writeAll(int fd, const void *data, unsigned long length)
{
  const char *p = (const char *)data;
  int n;
  while (length != 0) {
    n = write(fd, p, length);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) {
      if (n < 0) perror("NXVNC: socket write");
      else fprintf(stderr, "NXVNC: socket write made no progress\n");
      return 0;
    }
    p += n; length -= (unsigned long)n;
  }
  return 1;
}

static int readAll(int fd, void *data, unsigned long length)
{
  char *p = (char *)data;
  int n;
  while (length != 0) {
    n = read(fd, p, length);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) {
      if (n < 0) perror("NXVNC: socket read");
      else fprintf(stderr, "NXVNC: client closed the connection\n");
      return 0;
    }
    p += n; length -= (unsigned long)n;
  }
  return 1;
}

static void put16(unsigned char *p, unsigned value)
{ p[0] = (unsigned char)(value >> 8); p[1] = (unsigned char)value; }
static void put32(unsigned char *p, unsigned long value)
{ p[0]=(unsigned char)(value>>24); p[1]=(unsigned char)(value>>16);
 p[2]=(unsigned char)(value>>8); p[3]=(unsigned char)value; }
static unsigned get16(unsigned char *p) { return ((unsigned)p[0]<<8)|p[1]; }
static unsigned long get32(unsigned char *p)
{ return ((unsigned long)p[0]<<24)|((unsigned long)p[1]<<16)|
    ((unsigned long)p[2]<<8)|p[3]; }

/* Only consume complete input messages at the head of the stream. Control
   messages stay ordered and are handled by serveClient after this update. */
@interface NXVNCRFBServer (InputService)
- (int) serviceInput;
- (void) disableFailedInput;
@end
static int serviceServerInput(void *context)
{ return [(NXVNCRFBServer *)context serviceInput]; }

@implementation NXVNCRFBServer
- (void) setInput: (NXVNCInput *)input { _input=input; }
- initWithFramebuffer: (NXVNCFramebuffer *)framebuffer
         port: (int)port
{
  [super init];
  _framebuffer = [framebuffer retain];
  _port = port; _listenSocket = _clientSocket = -1;
  _previous = (unsigned char *)malloc((unsigned long)[framebuffer width]
                                      * [framebuffer height] * 4);
  if (_previous == 0) {
    fprintf(stderr, "NXVNC: cannot allocate previous-frame cache\n");
    [self release]; return nil;
  }
  _versionCount=((unsigned)[framebuffer width]+31)/32
                *(((unsigned)[framebuffer height]+31)/32);
  _seenVersions=(unsigned long *)calloc(_versionCount,sizeof(unsigned long));
  if (!_seenVersions) { [self release]; return nil; }
  _profile = getenv("NXVNC_PROFILE") != 0;
  _refreshInterval = 0.25;
  {
    const char *value = getenv("NXVNC_MAX_FPS");
    char *end;
    double fps;
    if (value) {
      fps = strtod(value, &end);
      if (end != value && !*end && fps >= 1 && fps <= 60)
        _refreshInterval = 1.0 / fps;
      else fprintf(stderr,"NXVNC: NXVNC_MAX_FPS must be between 1 and 60; using 4\n");
    }
  }
  [_framebuffer setService:serviceServerInput context:self];
  _bitsPerPixel = 32; _bigEndian = 1;
  _redMax = _greenMax = _blueMax = 255;
  _redShift = 16; _greenShift = 8; _blueShift = 0;
  return self;
}

- (int) sendHandshake
{
  unsigned char init[24];
  unsigned char shared;
  static const char version[] = "RFB 003.003\n";
  static const char name[] = "NeXT RFB Display";
  memset(_seenVersions,0,_versionCount*sizeof(unsigned long));
  _outputCount = 0; _encoding = 0; _updateNumber = 0; _lastRefresh = 0;
  memset(_previous, 255, (unsigned long)[_framebuffer width]
                         * [_framebuffer height] * 4);
  NXVNCSetFormat(&_format, 32, 24, 1, 255, 255, 255, 16, 8, 0);
  /* Each connection starts with the format advertised in ServerInit. */
  _bitsPerPixel = 32; _bigEndian = 1;
  _redMax = _greenMax = _blueMax = 255;
  _redShift = 16; _greenShift = 8; _blueShift = 0;
  if (!writeAll(_clientSocket, version, 12)) return 0;
  if (!readAll(_clientSocket, init, 12)) return 0;
  /* RFB 3.3: security type 1 means None. */
  put32(init, 1);
  if (!writeAll(_clientSocket, init, 4)) return 0;
  if (!readAll(_clientSocket, &shared, 1)) return 0;
  memset(init, 0, sizeof(init));
  put16(init, [_framebuffer width]); put16(init + 2, [_framebuffer height]);
  init[4] = 32; init[5] = 24; init[6] = 1; init[7] = 1;
  put16(init + 8, 255); put16(init + 10, 255); put16(init + 12, 255);
  init[14] = 16; init[15] = 8; init[16] = 0;
  put32(init + 20, sizeof(name) - 1);
  return writeAll(_clientSocket, init, 24) &&
     writeAll(_clientSocket, name, sizeof(name) - 1);
}

/* Input-driver failures must not tear down the framebuffer connection.
   Release any held keys/buttons once, then stay view-only until restart. */
- (void) disableFailedInput
{
  fprintf(stderr,"NXVNC: remote input failed; continuing in view-only mode\n");
  NXVNCInputReset(_input);
  _input=0;
}

- (int) serviceInput
{
  unsigned char b[8];
  int available, length, n, budget = 64;
  fd_set reads;
  struct timeval timeout;
  while (budget--) {
    FD_ZERO(&reads); FD_SET(_clientSocket, &reads);
    timeout.tv_sec=0; timeout.tv_usec=0;
    n=select(_clientSocket+1,&reads,0,0,&timeout);
    if (n<0) { if(errno==EINTR) continue; return 0; }
    if (!n) return 1;
    n=recv(_clientSocket,b,1,MSG_PEEK);
    if(n<0 && (errno==EINTR || errno==EAGAIN || errno==EWOULDBLOCK)) continue;
    if (n<=0) return 0;
    length=b[0]==4 ? 8 : (b[0]==5 ? 6 : 0);
    if (!length) return 1;
    if (ioctl(_clientSocket,FIONREAD,&available)<0) return 0;
    if (available<length) return 1;
    if (!readAll(_clientSocket,b,length)) return 0;
    if (_input && b[0]==4 && !NXVNCInputKey(_input,get32(b+4),b[1]!=0)) [self disableFailedInput];
    if (_input && b[0]==5 && !NXVNCInputPointer(_input,get16(b+2),get16(b+4),b[1])) [self disableFailedInput];
  }
  return 1;
}

/* Nonblocking writes let input progress even when a viewer stops reading.
   Restore blocking mode before returning to the ordinary protocol parser. */
- (int) flushOutput
{
  double start;
  int nonblocking=1, n, ok=1;
  unsigned offset=0;
  fd_set writes;
  struct timeval timeout;
  if (_outputCount == 0) return 1;
  start = NXVNCNow();
  /* Accepted sockets are blocking outside this method. Use the BSD socket
     ioctl: OPENSTEP's headers do not provide the POSIX O_NONBLOCK flag. */
  if(ioctl(_clientSocket,FIONBIO,&nonblocking)<0) {
    perror("NXVNC: nonblocking socket setup"); return 0;
  }
  while(offset<_outputCount) {
    if (![self serviceInput]) { ok=0; break; }
    n=write(_clientSocket,_output+offset,_outputCount-offset);
    if(n>0) { offset+=(unsigned)n; continue; }
    if(n<0 && errno==EINTR) continue;
    if(n<0 && (errno==EAGAIN || errno==EWOULDBLOCK)) {
      FD_ZERO(&writes); FD_SET(_clientSocket,&writes);
      timeout.tv_sec=0; timeout.tv_usec=10000;
      n=select(_clientSocket+1,0,&writes,0,&timeout);
      if(n>=0 || errno==EINTR) continue;
    }
    if(n<0) perror("NXVNC: socket write/wait");
    else fprintf(stderr,"NXVNC: socket write made no progress\n");
    ok=0; break;
  }
  nonblocking=0;
  if(ioctl(_clientSocket,FIONBIO,&nonblocking)<0) {
    perror("NXVNC: restore blocking socket"); ok=0;
  }
  _sendSeconds += NXVNCNow() - start;
  _wireBytes += offset;
  _outputCount = 0;
  return ok;
}

- (int) appendBytes: (const unsigned char *)bytes length: (unsigned)length
{
  unsigned count;
  while (length) {
    count = sizeof(_output) - _outputCount;
    if (count > length) count = length;
    memcpy(_output + _outputCount, bytes, count);
    _outputCount += count; bytes += count; length -= count;
    if (_outputCount == sizeof(_output) && ![self flushOutput]) return 0;
  }
  return 1;
}

- (int) sendUpdateX: (int)x y: (int)y width: (int)w height: (int)h
        incremental: (int)incremental
{
  typedef struct { int x, y, w, h; } Rect;
  Rect *rects, r;
  int fw = [_framebuffer width], fh = [_framebuffer height];
  int tx, ty, row, col, n = 0, j, different, tw, th, length;
  unsigned capacity;
  unsigned char header[12], tile[1025], *converted = 0;
  const unsigned char *pixels, *src;
  const unsigned long *versions;
  int gx,gy,versionCols=(fw+31)/32,known;
  int left,right,top,bottom,px;
  double start, captured, scanned, sent, finished, captureTime, delay;
  struct timeval pause;

  if (x >= fw || y >= fh) { w = 0; h = 0; }
  if (x + w > fw) w = fw - x;
  if (y + h > fh) h = fh - y;
  if (w <= 0 || h <= 0) {
    memset(header, 0, 4);
    return [self appendBytes:header length:4] && [self flushOutput];
  }
  /* Keep the idle limit, but service input in bounded slices while waiting. */
  while ((delay = _refreshInterval - (NXVNCNow() - _lastRefresh)) > 0) {
    if (![self serviceInput]) return 0;
    if (delay > 0.01) delay = 0.01;
    pause.tv_sec = 0; pause.tv_usec = (long)(delay * 1000000.0);
    select(0, 0, 0, 0, &pause);
  }
  if (![self serviceInput]) return 0;
  start = NXVNCNow(); _lastRefresh = start;
  if (![_framebuffer refreshX:x y:y width:w height:h]) {
    fprintf(stderr, "NXVNC: framebuffer capture failed; closing client\n");
    return 0;
  }
  captured = NXVNCNow();
  pixels = [_framebuffer pixels];
  versions = [_framebuffer tileVersions];
  capacity = ((unsigned)w + 31) / 32 * (((unsigned)h + 31) / 32);
  /* RFB's rectangle count is 16-bit. Use one full rectangle if necessary. */
  if (capacity > 65535) incremental = 0;
  if (!incremental) capacity = 1;
  rects = (Rect *)malloc(capacity * sizeof(Rect));
  if (rects == 0) return 0;
  if (!incremental) {
    rects[0].x=x; rects[0].y=y; rects[0].w=w; rects[0].h=h; n=1;
  } else {
    for (ty=y; ty<y+h; ty+=32) for (tx=x; tx<x+w; tx+=32) {
      if(tx==x && ![self serviceInput]) { free(rects); return 0; }
      tw = x+w-tx; if (tw>32) tw=32;
      th = y+h-ty; if (th>32) th=32;
      known=versions!=0;
      for(gy=ty/32; known && gy<=(ty+th-1)/32; gy++)
        for(gx=tx/32; known && gx<=(tx+tw-1)/32; gx++) {
          unsigned index=gy*versionCols+gx;
          known=_seenVersions[index]!=0 && _seenVersions[index]==versions[index];
        }
      if(known) continue;
      different=0; left=tw; right=0; top=th; bottom=0;
      for (row=0; row<th; row++) {
        unsigned long offset = ((unsigned long)(ty+row)*fw+tx)*4;
        if (!memcmp(pixels+offset, _previous+offset, tw*4)) continue;
        different=1;
        if(row<top) top=row;
        bottom=row+1;
        for(px=0;px<left;px++)
          if(memcmp(pixels+offset+px*4,_previous+offset+px*4,4)) { left=px; break; }
        for(px=tw;px>right;px--)
          if(memcmp(pixels+offset+(px-1)*4,_previous+offset+(px-1)*4,4)) { right=px; break; }
      }
      if (different) {
        r.x=tx+left; r.y=ty+top; r.w=right-left; r.h=bottom-top;
        /* Join adjacent spans without adding unchanged pixels. */
        if(n && rects[n-1].y==r.y && rects[n-1].h==r.h
             && rects[n-1].x+rects[n-1].w==r.x) rects[n-1].w+=r.w;
        else rects[n++]=r;
      }
    }
  }
  scanned = NXVNCNow();
  _wireBytes=0; _sendSeconds=0;
  if (!_encoding && !_format.direct) {
    converted = (unsigned char *)malloc((unsigned)w * _format.bytes);
    if (converted == 0) { free(rects); return 0; }
  }
  memset(header, 0, 4); put16(header+2, n);
  if (![self appendBytes:header length:4]) goto failed;
  for (j=0; j<n; j++) {
    if (![self serviceInput]) goto failed;
    r=rects[j];
    put16(header,r.x); put16(header+2,r.y);
    put16(header+4,r.w); put16(header+6,r.h); put32(header+8,_encoding);
    if (![self appendBytes:header length:12]) goto failed;
    if (_encoding) {
      for (row=0; row<r.h; row+=16) for (col=0; col<r.w; col+=16) {
        if(col==0 && ![self serviceInput]) goto failed;
        tw=r.w-col; if (tw>16) tw=16;
        th=r.h-row; if (th>16) th=16;
        src=pixels+((unsigned long)(r.y+row)*fw+r.x+col)*4;
        length=_encoding == 15
          ? NXVNCEncodeTRLE(&_format,src,fw*4,tw,th,tile)
          : NXVNCEncodeHextile(&_format,src,fw*4,tw,th,tile);
        if (![self appendBytes:tile length:(unsigned)length]) goto failed;
      }
    } else {
      for (row=0; row<r.h; row++) {
        src=pixels+((unsigned long)(r.y+row)*fw+r.x)*4;
        if (!_format.direct) {
          NXVNCEncodeRow(&_format,src,converted,r.w); src=converted;
        }
        if (![self appendBytes:src length:(unsigned)r.w*_format.bytes]) goto failed;
      }
    }
  }
  if (![self flushOutput]) goto failed;
  sent=NXVNCNow();
  /* Commit only pixels delivered to this client. Off-request changes remain
     dirty, and reconnects start with an entirely invalid snapshot. */
  for (j=0; j<n; j++) for (row=0; row<rects[j].h; row++) {
    unsigned long offset=((unsigned long)(rects[j].y+row)*fw+rects[j].x)*4;
    memcpy(_previous+offset,pixels+offset,rects[j].w*4);
  }
  /* Every fully requested tile was inspected. Pixels outside the tight
     delivered bounds already matched the client, so acknowledge the version
     even when no rectangle was needed. Never acknowledge partial tiles. */
  if(versions) {
    for(gy=(y+31)/32;gy*32<y+h;gy++)
      for(gx=(x+31)/32;gx*32<x+w;gx++) {
        int right=(gx+1)*32, bottom=(gy+1)*32;
        if(right>fw) right=fw; if(bottom>fh) bottom=fh;
        if(right<=x+w && bottom<=y+h)
          _seenVersions[gy*versionCols+gx]=versions[gy*versionCols+gx];
      }
  }
  finished=NXVNCNow();
  captureTime=captured-start;
  if (_profile || _updateNumber == 0) {
    fprintf(stderr, "NXVNC: update %lu %s %s rects=%d bytes=%lu "
            "refresh=%.3fs (capture=%.3fs packedCompare=%.3fs expand=%.3fs other=%.3fs) compare=%.3fs "
            "encode/buffer=%.3fs cache=%.3fs socket=%.3fs total=%.3fs\n",
            ++_updateNumber, incremental ? "incremental" : "full",
            _encoding == 15 ? "TRLE" : (_encoding == 5 ? "Hextile" : (_format.direct ? "raw/direct" : "raw/table")),
            n,_wireBytes,captureTime,[_framebuffer captureSeconds],
            [_framebuffer packedCompareSeconds],
            [_framebuffer conversionSeconds],
            captureTime-[_framebuffer captureSeconds]-[_framebuffer conversionSeconds]
            -[_framebuffer packedCompareSeconds],
            scanned-captured,
            sent-scanned-_sendSeconds,finished-sent,_sendSeconds,finished-start);
  } else _updateNumber++;
  free(converted); free(rects); return 1;
failed:
  _outputCount=0; free(converted); free(rects); return 0;
}

- (int) serveClient
{
  unsigned char type, b[19];
  unsigned long count, bytes;
  while (readAll(_clientSocket, &type, 1)) {
    if (type == 0) { /* SetPixelFormat */
      if (!readAll(_clientSocket, b, 19)) return 0;
      if ((b[3] != 8 && b[3] != 16 && b[3] != 32) || !b[6] ||
        b[13] >= b[3] || b[14] >= b[3] || b[15] >= b[3]) {
        fprintf(stderr, "NXVNC: unsupported client pixel format "
                "(bpp=%u, trueColor=%u, shifts=%u/%u/%u)\n",
                (unsigned)b[3], (unsigned)b[6], (unsigned)b[13],
                (unsigned)b[14], (unsigned)b[15]);
        return 0;
      }
      if (!NXVNCSetFormat(&_format,b[3],b[4],b[5],get16(b+7),get16(b+9),
                          get16(b+11),b[13],b[14],b[15])) {
        fprintf(stderr,"NXVNC: invalid true-color fields\n"); return 0;
      }
      /* A reduced-depth format may have discarded information. Resend after
         any format change rather than trusting the old client snapshot. */
      memset(_seenVersions,0,_versionCount*sizeof(unsigned long));
      memset(_previous,255,(unsigned long)[_framebuffer width]
                              *[_framebuffer height]*4);
      _bitsPerPixel = b[3]; _bigEndian = b[5];
      _redMax = get16(b + 7); _greenMax = get16(b + 9);
      _blueMax = get16(b + 11);
      _redShift = b[13]; _greenShift = b[14]; _blueShift = b[15];
    } else if (type == 2) { /* SetEncodings */
      if (!readAll(_clientSocket, b, 3)) return 0;
      count = get16(b + 1); _encoding = 0;
      while (count--) {
        if (!readAll(_clientSocket,b,4)) return 0;
        if (get32(b) == 15) _encoding = 15;
        else if (get32(b) == 5 && _encoding != 15) _encoding = 5;
      }
      fprintf(stderr,"NXVNC: encoding %s\n",_encoding == 15 ? "TRLE" : (_encoding == 5 ? "Hextile" : "raw"));
    } else if (type == 3) { /* FramebufferUpdateRequest */
      if (!readAll(_clientSocket, b, 9)) return 0;
      if (![self sendUpdateX:get16(b + 1) y:get16(b + 3)
               width:get16(b + 5) height:get16(b + 7) incremental:b[0]]) return 0;
    } else if (type == 4) { /* KeyEvent */
      if (!readAll(_clientSocket, b, 7)) return 0;
      if (_input && !NXVNCInputKey(_input,get32(b+3),b[0]!=0)) [self disableFailedInput];
    } else if (type == 5) { /* PointerEvent */
      if (!readAll(_clientSocket, b, 5)) return 0;
      if (_input && !NXVNCInputPointer(_input,get16(b+1),get16(b+3),b[0])) [self disableFailedInput];
    } else if (type == 6) { /* ClientCutText */
      if (!readAll(_clientSocket, b, 7)) return 0;
      bytes = get32(b + 3);
      while (bytes != 0) {
        count = bytes > sizeof(b) ? sizeof(b) : bytes;
        if (!readAll(_clientSocket, b, count)) return 0;
        bytes -= count;
      }
    } else {
      fprintf(stderr, "NXVNC: unsupported client message %u\n", (unsigned)type);
      return 0;
    }
  }
  return 1;
}

- (int) run
{
  struct sockaddr_in address;
  int one = 1;
  /* A disconnected viewer must not terminate the listening server. */
  signal(SIGPIPE, SIG_IGN);
  _listenSocket = socket(AF_INET, SOCK_STREAM, 0);
  if (_listenSocket < 0) { perror("socket"); return 0; }
  setsockopt(_listenSocket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_ANY);
  address.sin_port = htons((unsigned short)_port);
  if (bind(_listenSocket, (struct sockaddr *)&address, sizeof(address)) < 0 ||
    listen(_listenSocket, 1) < 0) { perror("listen"); return 0; }
  fprintf(stderr, "NXVNC: listening on TCP port %d\n", _port);
  for (;;) {
    _clientSocket = accept(_listenSocket, 0, 0);
    if (_clientSocket < 0) { if (errno == EINTR) continue; perror("accept"); return 0; }
    if (_clientSocket>=FD_SETSIZE) { close(_clientSocket); _clientSocket=-1; continue; }
    setsockopt(_clientSocket,IPPROTO_TCP,TCP_NODELAY,&one,sizeof(one));
    fprintf(stderr, "NXVNC: client connected\n");
    if ([self sendHandshake]) {
      fprintf(stderr, "NXVNC: handshake complete\n");
      [self serveClient];
    } else fprintf(stderr, "NXVNC: handshake failed\n");
    if (_input) NXVNCInputReset(_input);
    close(_clientSocket); _clientSocket = -1;
  }
}

- (void) dealloc
{
  if (_input) NXVNCInputReset(_input);
  if (_clientSocket >= 0) close(_clientSocket);
  if (_listenSocket >= 0) close(_listenSocket);
  free(_seenVersions);
  free(_previous);
  [_framebuffer setService:0 context:0];
  [_framebuffer release];
  [super dealloc];
}
@end

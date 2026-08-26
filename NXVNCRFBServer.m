#import "NXVNCRFBServer.h"
#import "NXVNCFramebuffer.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static int writeAll(int fd, const void *data, unsigned long length)
{
    const char *p = (const char *)data;
    int n;
    while (length != 0) {
        n = write(fd, p, length);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
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
        if (n <= 0) return 0;
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

@implementation NXVNCRFBServer
- initWithFramebuffer:(NXVNCFramebuffer *)framebuffer port:(int)port
{
    [super init];
    _framebuffer = framebuffer;
    _port = port; _listenSocket = _clientSocket = -1;
    _bitsPerPixel = 32; _bigEndian = 1;
    _redMax = _greenMax = _blueMax = 255;
    _redShift = 16; _greenShift = 8; _blueShift = 0;
    return self;
}

- (int)sendHandshake
{
    unsigned char init[24];
    unsigned char shared;
    static const char version[] = "RFB 003.003\n";
    static const char name[] = "NeXT RFB Display";
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

- (int)sendUpdateX:(int)x y:(int)y width:(int)w height:(int)h
{
    unsigned char header[16];
    NXVNCByte *pixels;
    unsigned char *converted, *src, *dst;
    unsigned long value;
    int row, column, bytesPerPixel, i;
    if (![_framebuffer refresh]) return 0;
    if (x < 0) x = 0; if (y < 0) y = 0;
    if (x + w > [_framebuffer width]) w = [_framebuffer width] - x;
    if (y + h > [_framebuffer height]) h = [_framebuffer height] - y;
    if (w <= 0 || h <= 0) return 1;
    memset(header, 0, sizeof(header));
    put16(header + 2, 1);
    put16(header + 4, x); put16(header + 6, y);
    put16(header + 8, w); put16(header + 10, h);
    put32(header + 12, 0); /* raw encoding */
    if (!writeAll(_clientSocket, header, sizeof(header))) return 0;
    pixels = [_framebuffer pixels];
    bytesPerPixel = _bitsPerPixel / 8;
    converted = (unsigned char *)malloc((unsigned)(w * bytesPerPixel));
    if (converted == 0) return 0;
    for (row = 0; row < h; row++) {
        src = pixels + ((y + row) * [_framebuffer width] + x) * 4;
        dst = converted;
        for (column = 0; column < w; column++) {
            value = (((unsigned long)src[1] * _redMax / 255) << _redShift) |
                    (((unsigned long)src[2] * _greenMax / 255) << _greenShift) |
                    (((unsigned long)src[3] * _blueMax / 255) << _blueShift);
            if (_bigEndian) {
                for (i = bytesPerPixel - 1; i >= 0; i--)
                    *dst++ = (unsigned char)(value >> (i * 8));
            } else {
                for (i = 0; i < bytesPerPixel; i++)
                    *dst++ = (unsigned char)(value >> (i * 8));
            }
            src += 4;
        }
        if (!writeAll(_clientSocket, converted,
                      (unsigned long)w * bytesPerPixel)) {
            free(converted); return 0;
        }
    }
    free(converted);
    return 1;
}

- (int)serveClient
{
    unsigned char type, b[19];
    unsigned long count, bytes;
    while (readAll(_clientSocket, &type, 1)) {
        if (type == 0) { /* SetPixelFormat */
            if (!readAll(_clientSocket, b, 19)) return 0;
            if ((b[3] != 8 && b[3] != 16 && b[3] != 32) || !b[6] ||
                b[13] >= b[3] || b[14] >= b[3] || b[15] >= b[3]) return 0;
            _bitsPerPixel = b[3]; _bigEndian = b[5];
            _redMax = get16(b + 7); _greenMax = get16(b + 9);
            _blueMax = get16(b + 11);
            _redShift = b[13]; _greenShift = b[14]; _blueShift = b[15];
        } else if (type == 2) { /* SetEncodings */
            if (!readAll(_clientSocket, b, 3)) return 0;
            count = get16(b + 1); bytes = count * 4;
            while (bytes != 0) {
                count = bytes > sizeof(b) ? sizeof(b) : bytes;
                if (!readAll(_clientSocket, b, count)) return 0;
                bytes -= count;
            }
        } else if (type == 3) { /* FramebufferUpdateRequest */
            if (!readAll(_clientSocket, b, 9)) return 0;
            if (![self sendUpdateX:get16(b + 1) y:get16(b + 3)
                              width:get16(b + 5) height:get16(b + 7)]) return 0;
        } else if (type == 4) { /* KeyEvent: parsed, injection backend pending */
            if (!readAll(_clientSocket, b, 7)) return 0;
            (void)get32(b + 3);
        } else if (type == 5) { /* PointerEvent */
            if (!readAll(_clientSocket, b, 5)) return 0;
        } else if (type == 6) { /* ClientCutText */
            if (!readAll(_clientSocket, b, 7)) return 0;
            bytes = get32(b + 3);
            while (bytes != 0) {
                count = bytes > sizeof(b) ? sizeof(b) : bytes;
                if (!readAll(_clientSocket, b, count)) return 0;
                bytes -= count;
            }
        } else return 0;
    }
    return 1;
}

- (int)run
{
    struct sockaddr_in address;
    int one = 1;
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
        if ([self sendHandshake]) [self serveClient];
        close(_clientSocket); _clientSocket = -1;
    }
}

- free
{
    if (_clientSocket >= 0) close(_clientSocket);
    if (_listenSocket >= 0) close(_listenSocket);
    return [super free];
}
@end

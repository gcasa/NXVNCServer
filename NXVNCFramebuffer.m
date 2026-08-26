#import "NXVNCFramebuffer.h"
#include <stdlib.h>
#include <string.h>

#ifdef NEXTSTEP
#import <appkit/appkit.h>
#import <appkit/graphics.h>

/* Generated DPS operator wrapper supplied by the NeXT AppKit. */
extern void PSsetwindow(int windowNumber);
#endif

@implementation NXVNCFramebuffer
- initWidth:(int)width height:(int)height
{
    [super init];
    _width = width;
    _height = height;
    _pixels = (NXVNCByte *)malloc((unsigned)(width * height * 4));
    if (_pixels == 0) return [self free];
    memset(_pixels, 0, (unsigned)(width * height * 4));
    return self;
}
- (int)width { return _width; }
- (int)height { return _height; }
- (NXVNCByte *)pixels { return _pixels; }
- (int)refresh { return 1; }
- free
{
    if (_pixels != 0) free(_pixels);
    _pixels = 0;
    return [super free];
}
@end

@implementation NXVNCTestFramebuffer
- (int)refresh
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

#ifdef NEXTSTEP
@implementation NXVNCScreenFramebuffer
- init
{
    NXRect r;
    int size, pw, ph, bps, spp, config, mask;

    [Application new];
    r.origin.x = r.origin.y = 0.0;
    r.size = [NXApp screenSize];
    PSsetwindow(0);
    NXSizeBitmap(&r, &size, &pw, &ph, &bps, &spp, &config, &mask);
    return [super initWidth:pw height:ph];
}

- (int)refresh
{
    NXRect r;
    int size, pw, ph, bps, spp, config, mask;
    unsigned char *planes[5];
    int x, y, i, rowBytes;

    r.origin.x = r.origin.y = 0.0;
    r.size.width = (float)_width;
    r.size.height = (float)_height;
    PSsetwindow(0);
    NXSizeBitmap(&r, &size, &pw, &ph, &bps, &spp, &config, &mask);
    if (bps != 8 || spp < 1 || spp > 5 || size <= 0) return 0;
    for (i = 0; i < 5; i++) planes[i] = 0;
    /* config == 0 is meshed; otherwise the samples occupy spp planes. */
    for (i = 0; i < (config ? spp : 1); i++) {
        planes[i] = (unsigned char *)malloc((unsigned)size);
        if (planes[i] == 0) {
            while (--i >= 0) free(planes[i]);
            return 0;
        }
    }
    NXReadBitmap(&r, pw, ph, bps, spp, config, mask,
                 planes[0], planes[1], planes[2], planes[3], planes[4]);

    /* Convert packed gray/RGB into RFB's 00rrggbb.  Screen coordinates
       are bottom-up; RFB scan lines are top-down. */
    for (y = 0; y < _height; y++) {
        unsigned char *src;
        unsigned char *dst = _pixels + y * _width * 4;
        rowBytes = config ? size / ph : size / ph;
        src = planes[0] + (_height - 1 - y) * rowBytes;
        for (x = 0; x < _width; x++) {
            unsigned char red, green, blue;
            if (spp < 3) {
                if (config) red = green = blue =
                    planes[0][(_height - 1 - y) * rowBytes + x];
                else red = green = blue = src[x * spp];
            }
            else if (config) {
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
    for (i = 0; i < (config ? spp : 1); i++) free(planes[i]);
    return 1;
}
@end
#endif

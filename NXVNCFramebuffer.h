#import <objc/Object.h>

typedef unsigned char NXVNCByte;

@interface NXVNCFramebuffer : Object
{
    int _width;
    int _height;
    NXVNCByte *_pixels;
}
- initWidth:(int)width height:(int)height;
- (int)width;
- (int)height;
- (NXVNCByte *)pixels;
- (int)refresh;
- free;
@end

/* Useful for protocol testing on a non-NeXT host. */
@interface NXVNCTestFramebuffer : NXVNCFramebuffer
{
    unsigned long _tick;
}
- (int)refresh;
@end

#ifdef NEXTSTEP
@interface NXVNCScreenFramebuffer : NXVNCFramebuffer
- init;
- (int)refresh;
@end
#endif


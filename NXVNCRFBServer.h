#import <objc/Object.h>
@class NXVNCFramebuffer;

@interface NXVNCRFBServer : Object
{
    int _listenSocket;
    int _clientSocket;
    int _port;
    NXVNCFramebuffer *_framebuffer;
    int _bitsPerPixel;
    int _bigEndian;
    unsigned _redMax, _greenMax, _blueMax;
    int _redShift, _greenShift, _blueShift;
}
- initWithFramebuffer:(NXVNCFramebuffer *)framebuffer port:(int)port;
- (int)run;
- free;
@end

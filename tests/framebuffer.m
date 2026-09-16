/* Deterministic fixture for testing the real RFB server without DPS. */
#import <Foundation/Foundation.h>
#import "NXVNCFramebuffer.h"
#import "NXVNCRFBServer.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static const char *statePath;
static NXVNCGrayCache cache;
static int packed;
static NXVNCInput input;
static int recordInput(void *context,const NXVNCInputEvent *event) {
  (void)context;
  fprintf(stderr,"INPUT %d %d %d %u %u %u %d\n",event->type,event->x,event->y,
          event->flags,event->set,event->code,event->repeat);
  return 1;
}
@implementation NXVNCFramebuffer
- (void) setService: (int (*)(void *))service context: (void *)context
{ _service=service; _serviceContext=context; }
- initWidth:(int)w height:(int)h {
  self=[super init]; _width=w; _height=h; _pixels=calloc(w*h,4); return self;
}
- (int)width { return _width; }
- (int)height { return _height; }
- (NXVNCByte *)pixels { return _pixels; }
- (double)captureSeconds { return 0; }
- (double)conversionSeconds { return 0; }
- (double)packedCompareSeconds { return 0; }
- (const unsigned long *)tileVersions { return packed ? cache.versions : 0; }
- (int)refreshX:(int)x y:(int)y width:(int)w height:(int)h {
  fprintf(stderr,"CAPTURE %d %d %d %d\n",x,y,w,h);
  return [self refresh];
}
- (int)refresh {
  int x,y;
  for(y=0;y<_height;y++) for(x=0;x<_width;x++) {
    unsigned char g=(unsigned char)(((x/8+y/8)%4)*85);
    unsigned char *p=_pixels+(y*_width+x)*4;
    p[0]=0; p[1]=g; p[2]=g; p[3]=g;
  }
  if (statePath) {
    FILE *f=fopen(statePath,"r");
    int px,py,value;
    if (f) {
      while (fscanf(f,"%d %d %d",&px,&py,&value)==3
          && px>=0 && px<_width && py>=0 && py<_height) {
        unsigned char *p=_pixels+(py*_width+px)*4;
        p[1]=p[2]=p[3]=(unsigned char)value;
      }
      fclose(f);
    }
  }
  if(packed) {
    unsigned char raw[17*35];
    double a,b;
    memset(raw,0,sizeof(raw));
    for(y=0;y<_height;y++) for(x=0;x<_width;x++)
      raw[y*17+x/4]|=(_pixels[(y*_width+x)*4+1]/85) << (6-2*(x%4));
    if(!cache.previous) NXVNCInitGrayCache(&cache,_width,_height);
    NXVNCRefreshGrayCache(&cache,raw,17,0,_pixels,&a,&b);
  }
  return 1;
}
- (void)dealloc { free(_pixels); [super dealloc]; }
@end
int main(int argc,char **argv) {
  NSAutoreleasePool *pool=[NSAutoreleasePool new];
  int width=getenv("NXVNC_TEST_LARGE") ? 2048 : 67;
  int height=getenv("NXVNC_TEST_LARGE") ? 1024 : 35;
  NXVNCFramebuffer *fb=[[NXVNCFramebuffer alloc] initWidth:width height:height];
  NXVNCRFBServer *server=[[NXVNCRFBServer alloc] initWithFramebuffer:fb port:atoi(argv[1])];
  int ok;
  statePath=argc>2 ? argv[2] : 0;
  packed=argc>3;
  NXVNCInputInit(&input,width,height,recordInput,0);
  [server setInput:&input];
  ok=[server run];
  [server release]; [fb release]; [pool release]; return !ok;
}

/* Exercise real main.m with fake framebuffer/listener and credential calls. */
#import "NXVNCFramebuffer.h"
#import "NXVNCInterceptorFramebuffer.h"
#import "NXVNCRFBServer.h"
#include "startup_fixture.h"
#include <assert.h>
#include <stdio.h>
static int gui,listener,attached;
int NXVNCMain(int,char **);
@implementation NXVNCFramebuffer
- initWidth:(int)w height:(int)h {
  assert(testEUID==testUID && testEGID==testGID);
  self=[super init]; _width=w;_height=h;gui++;return self;
}
- (int)width { return _width; }
- (int)height { return _height; }
@end
@implementation NXVNCTestFramebuffer
@end
@implementation NXVNCScreenFramebuffer
- init { return [self initWidth:1120 height:832]; }
@end
NXVNCFramebuffer *NXVNCCreateScreenFramebuffer(void) {
  return [NXVNCScreenFramebuffer new];
}
@implementation NXVNCRFBServer
- initWithFramebuffer:(NXVNCFramebuffer *)fb port:(int)port {
  (void)fb; (void)port; assert(testEUID==testUID);
  return [super init];
}
- (void)setInput:(NXVNCInput *)input {
  assert(input->width==1120 && input->height==832 && input->post);attached++;
}
- (int)run { assert(testEUID==testUID);listener++;return 0; }
@end
int main(void) {
  char *normal[]={"nxvncserver",0};
  char *view[]={"nxvncserver","--view-only",0};
  char *pattern[]={"nxvncserver","--test",0};
  resetStartupFixture();
  assert(NXVNCMain(1,normal)==1 && gui==1 && listener==1 && attached==1 && closes==1);
  resetStartupFixture();failUID=1;
  assert(NXVNCMain(1,normal)==1 && gui==1 && listener==1 && closes==1);
  resetStartupFixture();
  assert(NXVNCMain(2,view)==1 && gui==2 && listener==2 && attached==1 && !opens);
  resetStartupFixture();
  assert(NXVNCMain(2,pattern)==1 && gui==3 && listener==3 && attached==1 && !opens);
  puts("PASS: real main drops credentials before framebuffer/listener creation, preserves handle and applies screen bounds");
  return 0;
}

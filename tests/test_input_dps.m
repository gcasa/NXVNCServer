#include "NXVNCInput.h"
#include "NXVNCPlatform.h"
#import "input_dps_stub.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
NXVNCMockApplication *NSApp;
static NSDPSContext *context;
static int active=123,fail,throws,posts,lookups;
static unsigned int word1,word2;
@implementation NSDPSContext
+ (void)setCurrentContext:(NSDPSContext *)value { assert(value==context); }
@end
@implementation NXVNCMockApplication
- (NSDPSContext *)context { return context; }
@end
void PScurrentactiveapp(int *value) { *value=active; lookups++; }
void PSrealtime(int *value) { *value=42; }
void PSposteventbycontext(int type,float x,float y,int time,int flags,int window,
                         int repeat,int data1,int data2,int target,int *posted)
{
  assert(type==10 || type==11);
  assert(x==0 && y==0 && time==42 && window==0 && repeat==0);
  assert(flags==(1<<21) && target==123);
  if(throws) [NSException raise:@"DPS failure" format:@"test"];
  word1=(unsigned int)data1; word2=(unsigned int)data2;
  posts++; *posted=!fail;
}
int main(void)
{
  NSAutoreleasePool *pool=[NSAutoreleasePool new];
  NXVNCInputEvent e;
  int target=0;
  memset(&e,0,sizeof(e)); e.type=10; e.flags=1U<<21;
  e.set=1; e.code=e.originalCode=0xac;
#ifdef NXVNC_INPUT_INTEL
  e.keyCode=0x66;
#else
  e.keyCode=9;
#endif
  assert(!NXVNCInputPostArrow(&e,&target));
  NSApp=[NXVNCMockApplication new]; context=[NSDPSContext new];
  assert(NXVNCInputPostArrow(&e,&target) && target==123 && posts==1);
#ifdef NXVNC_INPUT_INTEL
  assert(word1==0x00ac0001U && word2==0x00ac0066U);
#else
  assert(word1==0x000100acU && word2==0x000900acU);
#endif
  active=456; e.type=11;
  assert(NXVNCInputPostArrow(&e,&target) && !target && lookups==1);
  active=123; e.type=10; fail=1;
  assert(!NXVNCInputPostArrow(&e,&target) && !target);
  fail=0; throws=1;
  assert(!NXVNCInputPostArrow(&e,&target) && !target);
  throws=0; active=0;
  assert(NXVNCInputPostArrow(&e,&target) && !target);
  [context release]; [NSApp release]; [pool release];
  puts("PASS: DPS arrow packing, target lifetime, rejection and exception cleanup");
  return 0;
}

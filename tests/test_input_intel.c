#include "NXVNCInput.h"
#include "input_intel_stub.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
struct MockEventHandle { int unused; };
static struct MockEventHandle handle;
static unsigned int last[6];
static NXEventData data;
static int calls,closed,failOpen,failPost,pointer,arrowCalls,arrowTarget;
NXEventHandle NXOpenEventStatus(void) { return failOpen ? 0 : &handle; }
void NXCloseEventStatus(NXEventHandle h) { assert(h==&handle); closed++; }
int NXEvSetParameterInt(NXEventHandle h,char *name,unsigned int *params,unsigned int count)
{
  assert(h==&handle && count==6);
  assert(!strcmp(name,"Ev_LLPostEvent") || !strcmp(name,"Ev_PointerLLPostEvent"));
  if(failPost) return 17;
  memcpy(last,params,sizeof(last)); memcpy(&data,params+3,sizeof(data));
  pointer=!strcmp(name,"Ev_PointerLLPostEvent"); calls++; return 0;
}
int NXVNCInputPostArrow(const NXVNCInputEvent *e,int *target)
{
  assert(e->keyCode==0x66 && (e->flags&(1U<<21)));
  if(e->type==10) { assert(!*target); *target=123; }
  else { assert(*target==123); *target=0; }
  arrowTarget=*target; arrowCalls++; return 1;
}
int main(void)
{
  NXVNCInput s;
  int n;
  assert(!NXVNCInputOpen(&s,0,832) && !s.post);
  failOpen=1; assert(!NXVNCInputOpen(&s,1120,832) && !s.post); failOpen=0;
  assert(NXVNCInputOpen(&s,1120,832));
  assert(NXVNCInputPointer(&s,40,70,1));
  assert(calls==2 && pointer && last[0]==1 && last[1]==40 && last[2]==70);
  assert(last[3]==0 && last[4]==0 && last[5]==255);
  assert(NXVNCInputPointer(&s,65535,65535,1));
  assert(last[0]==6 && last[1]==1119 && last[2]==831);
  assert(NXVNCInputPointer(&s,0,0,4) && last[0]==3 && data.mouse.pressure==255);
  assert(NXVNCInputPointer(&s,10,20,4) && last[0]==7);
  assert(NXVNCInputKey(&s,'A',1));
  assert(!pointer && last[0]==10 && data.key.keyCode==0x1e);
  /* Check the independent little-endian integer wire values, not just fields. */
  assert(last[3]==0 && last[4]==0x00410000U && last[5]==0x0061001eU);
  assert(NXVNCInputKey(&s,'A',1) && last[3]==0x00010000U);
  assert(NXVNCInputKey(&s,'A',0) && last[0]==11);
  assert(NXVNCInputKey(&s,0xff51,1) && arrowCalls==1 && arrowTarget==123);
  n=calls;
  assert(NXVNCInputKey(&s,0xffeb,1));
  assert(NXVNCInputKey(&s,'q',1) && calls==n);
  assert(NXVNCInputKey(&s,'q',0) && calls==n);
  assert(NXVNCInputKey(&s,0xff51,0) && arrowCalls==2 && !arrowTarget);
  assert(NXVNCInputKey(&s,0xffeb,0));
  failPost=1; assert(!NXVNCInputKey(&s,'x',1)); failPost=0;
  assert(NXVNCInputKey(&s,'z',1));
  NXVNCInputClose(&s);
  assert(closed==1 && last[0]==4 && !s.post && !s.context);
  NXVNCInputClose(&s); assert(closed==1);
  puts("PASS: Intel Mach input payloads, cursor movement, drag, arrow routing, failures and releases");
  return 0;
}

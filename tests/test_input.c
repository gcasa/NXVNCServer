#include "NXVNCInput.h"
#include "NXVNCPlatform.h"
#include <assert.h>
#include <stdio.h>
static NXVNCInputEvent events[1024];
static int count,fail;
static int post(void *context,const NXVNCInputEvent *e)
{
  (void)context;
  if(fail) return 0;
  assert(count<1024); events[count++]=*e; return 1;
}
int main(void)
{
  NXVNCInput s;
  int n;
  NXVNCInputInit(&s,1120,832,post,0);
  assert(NXVNCInputReset(&s) && count==0);
  assert(NXVNCInputPointer(&s,65535,65535,1));
  assert(count==2 && events[0].type==5 && events[1].type==1);
  assert(events[0].x==1119 && events[0].y==831);
  assert(NXVNCInputPointer(&s,100,50,1));
  assert(events[2].type==6 && events[2].x==100 && events[2].y==50);
  assert(NXVNCInputPointer(&s,100,50,1) && count==3);
  assert(NXVNCInputPointer(&s,100,50,4));
  assert(events[3].type==2 && events[4].type==3);
  assert(NXVNCInputPointer(&s,101,50,4) && events[5].type==7);
  assert(NXVNCInputReset(&s) && events[6].type==4);
  assert(NXVNCInputKey(&s,0xffe1,1));
  assert(NXVNCInputKey(&s,0xffe2,1));
  assert(NXVNCInputKey(&s,0xffe1,0));
  assert(events[count-1].flags==(1U<<17));
  assert(NXVNCInputKey(&s,'A',1));
  assert(events[count-1].code=='A' && events[count-1].originalCode=='a');
#ifdef NXVNC_INPUT_INTEL
  assert(events[count-1].keyCode==0x1e && !events[count-1].repeat);
#else
  assert(events[count-1].keyCode==0x39 && !events[count-1].repeat);
#endif
  assert(NXVNCInputKey(&s,'A',1) && events[count-1].repeat);
  assert(NXVNCInputKey(&s,'A',0) && events[count-1].type==11);
  assert(NXVNCInputKey(&s,0xff09,1) && events[count-1].code==25);
  assert(NXVNCInputReset(&s) && !s.modifiers);
  assert(NXVNCInputKey(&s,0xffe3,1));
  assert(NXVNCInputKey(&s,'c',1) && events[count-1].code==3);
  assert(events[count-1].flags==(1U<<18));
  assert(NXVNCInputReset(&s));
  assert(NXVNCInputKey(&s,0xffeb,1));
  assert(NXVNCInputKey(&s,'q',1) && events[count-1].flags==(1U<<20));
  assert(NXVNCInputReset(&s));
  assert(NXVNCInputKey(&s,0xffe5,1));
  n=count; assert(NXVNCInputKey(&s,0xffe5,1) && count==n);
  assert(NXVNCInputKey(&s,0xffe5,0));
  assert(NXVNCInputKey(&s,0xffe5,1) && events[count-1].flags==0);
  assert(NXVNCInputReset(&s));
  assert(NXVNCInputKey(&s,0xff51,1));
  assert(events[count-1].set==1 && events[count-1].code==0xac);
  assert(NXVNCInputKey(&s,0xffbe,1));
  assert(events[count-1].set==254 && events[count-1].code==0x20);
  assert(NXVNCInputReset(&s));
  n=count;
  assert(NXVNCInputKey(&s,0x0101f600,1) && count==n);
  assert(NXVNCInputKey(&s,'x',0) && count==n);
  fail=1;
  assert(!NXVNCInputPointer(&s,101,50,1) && s.buttons==0);
  assert(!NXVNCInputKey(&s,'x',1));
  fail=0; assert(NXVNCInputReset(&s));
#ifdef NXVNC_INPUT_INTEL
  {
    static const unsigned long symbols[]={'!','Z',' ',0xff0d,0xff08,0xff09,
      0xff1b,0xff51,0xff52,0xff53,0xff54,0xff63,0xffff,0xff50,0xff57,
      0xff55,0xff56,0xff8d,0xffbe,0xffc7,0xffc8,0xffc9,
      0xffe1,0xffe2,0xffe3,0xffe4,0xffe9,0xffeb,0xffe5};
    static const unsigned short codes[]={0x02,0x2c,0x39,0x1c,0x0e,0x0f,
      0x01,0x66,0x64,0x67,0x65,0x68,0x69,0x6c,0x6d,
      0x6a,0x6b,0x62,0x3b,0x44,0x57,0x58,
      0x2a,0x36,0x1d,0x60,0x61,0x38,0x3a};
    unsigned i;
    for(i=0;i<sizeof(codes)/sizeof(codes[0]);i++) {
      assert(NXVNCInputKey(&s,symbols[i],1));
      assert(events[count-1].keyCode==codes[i]);
      assert(NXVNCInputReset(&s));
    }
  }
#endif
  puts("PASS: input translation, modifiers, repeats, drag, clipping, disconnect release, failures");
  return 0;
}

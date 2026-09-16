#include "NXVNCInput.h"
#include <assert.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include "input_driver_stub.h"
static struct evsioLLEvent last;
static unsigned long lastRequest;
static int calls,closed,failOpen,interruptOnce,failPost;
int mockInputOpen(const char *path,int flags,...)
{
  (void)flags; assert(!strcmp(path,"/dev/evs0"));
  if(failOpen) { errno=EACCES; return -1; }
  return 42;
}
int mockInputClose(int fd) { assert(fd==42); closed++; return 0; }
int mockInputIoctl(int fd,unsigned long request,struct evsioLLEvent *e)
{
  assert(fd==42);
  if(interruptOnce) { interruptOnce=0; errno=EINTR; return -1; }
  if(failPost) { errno=EIO; return -1; }
  last=*e; lastRequest=request; calls++; return 0;
}
int main(void)
{
  NXVNCInput s;
  int n;
  assert(NXVNCInputOpen(&s,1120,832));
  interruptOnce=1;
  assert(NXVNCInputPointer(&s,40,70,1));
  assert(calls==2 && last.type==1 && lastRequest==EVSIOPTRLLPE);
  assert(last.location.x==40 && last.location.y==70 && last.data.mouse.pressure==255);
  assert(NXVNCInputKey(&s,'A',1));
  assert(lastRequest==EVSIOLLPE && last.type==10);
  assert(last.data.key.charCode=='A' && last.data.key.origCharCode=='a');
  assert(last.data.key.keyCode==0x39 && !last.data.key.repeat);
  assert(NXVNCInputKey(&s,'A',1) && last.data.key.repeat);
  assert(NXVNCInputKey(&s,'A',0) && last.type==11);
  n=calls;
  assert(NXVNCInputKey(&s,0xffeb,1));
  assert(NXVNCInputKey(&s,'q',1) && calls==n);
  assert(NXVNCInputKey(&s,'q',0));
  assert(NXVNCInputKey(&s,0xffeb,0) && calls==n);
  failPost=1; assert(!NXVNCInputKey(&s,'x',1)); failPost=0;
  NXVNCInputClose(&s);
  assert(last.type==2 && closed==1 && !s.post && !s.context);
  NXVNCInputClose(&s); assert(closed==1);
  failOpen=1; assert(!NXVNCInputOpen(&s,1120,832));
  assert(!s.post && !s.context);
  puts("PASS: native input adapter, cursor/key payloads, retries, failure handling, close releases");
  return 0;
}

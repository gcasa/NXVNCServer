/* OPENSTEP/m68k event-status driver adapter. GPL-3.0-or-later.
   Keep kernel event headers out of Objective-C/AppKit translation units:
   their NXEvent definitions have different coordinate representations. */
#include "NXVNCInput.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#if defined(m68k) || defined(__m68k__) || defined(NXVNC_INPUT_NATIVE_TEST)
#include <fcntl.h>
#ifdef NXVNC_INPUT_NATIVE_TEST
#include "tests/input_driver_stub.h"
#else
#include <libc.h>
#include <bsd/dev/m68k/evsio.h>
#endif

typedef struct { int fd, warned; } NativeInput;

static int postNative(void *context,const NXVNCInputEvent *event)
{
  NativeInput *native=(NativeInput *)context;
  struct evsioLLEvent e;
  int result;
  unsigned long request;
  /* EVSIOLLPE carries NXEventData, not the enclosing NXEvent.flags.
     Do not pretend a flags-changed event changes the hardware modifiers.
     Suppress Command/Option chords instead of unexpectedly typing letters. */
  if(event->flags & ((1U<<19)|(1U<<20))) {
    if(!native->warned) {
      fprintf(stderr,"NXVNC: Command/Option input is not supported by the m68k event-posting interface\n");
      native->warned=1;
    }
    if(event->type==10 || event->type==11) return 1;
  }
  if(event->type==12) return 1;
  memset(&e,0,sizeof(e)); e.type=event->type;
  /* The event driver uses screen coordinates from the top left, like RFB.
     Do not apply the AppKit bottom-left coordinate conversion here. */
  e.location.x=(short)event->x; e.location.y=(short)event->y;
  request=EVSIOLLPE;
  if(event->type>=1 && event->type<=7) {
    request=EVSIOPTRLLPE;
    e.data.mouse.pressure=(event->type==1 || event->type==3 ||
                          event->type==6 || event->type==7) ? 255 : 0;
  } else {
    e.data.key.charSet=event->set; e.data.key.charCode=event->code;
    e.data.key.origCharSet=event->originalSet;
    e.data.key.origCharCode=event->originalCode;
    e.data.key.keyCode=event->keyCode; e.data.key.repeat=(short)event->repeat;
  }
  do { result=ioctl(native->fd,request,&e); } while(result<0 && errno==EINTR);
  if(result<0) perror("NXVNC: event injection");
  return result>=0;
}

int NXVNCInputOpen(NXVNCInput *input,int width,int height)
{
  NativeInput *native;
  int fd;
  NXVNCInputInit(input,width,height,0,0);
  if(width<1 || height<1 || width>32768 || height>32768) return 0;
  fd=open("/dev/evs0",O_RDWR,0);
  if(fd<0) { perror("NXVNC: open /dev/evs0 (remote input unavailable)"); return 0; }
  native=(NativeInput *)calloc(1,sizeof(*native));
  if(!native) { close(fd); return 0; }
  native->fd=fd; input->post=postNative; input->context=native;
  fprintf(stderr,"NXVNC: keyboard and two-button mouse input enabled via /dev/evs0\n");
  return 1;
}
void NXVNCInputClose(NXVNCInput *input)
{
  NativeInput *native=(NativeInput *)input->context;
  if(!native) return;
  NXVNCInputReset(input); close(native->fd); free(native);
  input->context=0; input->post=0;
}
#else
int NXVNCInputOpen(NXVNCInput *input,int width,int height)
{
  NXVNCInputInit(input,width,height,0,0);
  fprintf(stderr,"NXVNC: native input requires OPENSTEP/m68k; view-only\n");
  return 0;
}
void NXVNCInputClose(NXVNCInput *input) { (void)input; }
#endif

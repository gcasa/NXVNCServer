/* OPENSTEP m68k and Intel event-status adapters. GPL-3.0-or-later.
   Keep kernel event headers out of Objective-C/AppKit translation units:
   their NXEvent definitions have different coordinate representations. */
#include "NXVNCInput.h"
#include "NXVNCPlatform.h"
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

typedef struct { int fd, warned; int arrowTargets[4]; } NativeInput;

static int postNative(void *context,const NXVNCInputEvent *event)
{
  NativeInput *native=(NativeInput *)context;
  struct evsioLLEvent e;
  int result, arrow=-1;
  unsigned long request;
  if((event->type==10 || event->type==11) && event->originalSet==1
      && event->originalCode>=0xac && event->originalCode<=0xaf)
    arrow=event->originalCode-0xac;
  /* EVSIOLLPE carries NXEventData, not the enclosing NXEvent.flags.
     Do not pretend a flags-changed event changes the hardware modifiers.
     Suppress Command/Option chords instead of unexpectedly typing letters. */
  if(event->flags & ((1U<<19)|(1U<<20))) {
    if(!native->warned) {
      fprintf(stderr,"NXVNC: Command/Option input is not supported by the m68k event-posting interface\n");
      native->warned=1;
    }
    /* Still release an arrow posted before the modifier was pressed. */
    if(event->type==10 || (event->type==11 &&
        (arrow<0 || !native->arrowTargets[arrow]))) return 1;
  }
  if(event->type==12) return 1;
  /* Symbol arrows without NX_NUMERICPADMASK are printable glyphs in Terminal.
     EVSIOLLPE has no flags field, so deliver these through the Window Server. */
  if(arrow>=0) return NXVNCInputPostArrow(event,&native->arrowTargets[arrow]);
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
#elif defined(NXVNC_INPUT_INTEL)
#ifdef NXVNC_INPUT_INTEL_TEST
#include "tests/input_intel_stub.h"
#else
#include <drivers/event_status_driver.h>
/* evio.h exposes the low-level posting parameter names only to driver clients. */
#ifndef DRIVER_PRIVATE
#define DRIVER_PRIVATE
#define NXVNC_UNDEF_DRIVER_PRIVATE
#endif
#include <bsd/dev/evio.h>
#ifdef NXVNC_UNDEF_DRIVER_PRIVATE
#undef DRIVER_PRIVATE
#undef NXVNC_UNDEF_DRIVER_PRIVATE
#endif
#endif

typedef struct { NXEventHandle handle; int warned, arrowTargets[4]; } IntelInput;

static int postIntel(void *context,const NXVNCInputEvent *event)
{
  IntelInput *native=(IntelInput *)context;
  NXEventData data;
  unsigned int params[EVIOLLPE_SIZE];
  char *request=EVIOLLPE;
  int result, arrow=-1;
  if((event->type==10 || event->type==11) && event->originalSet==1
      && event->originalCode>=0xac && event->originalCode<=0xaf)
    arrow=event->originalCode-0xac;
  /* Like the m68k ioctls, the Mach parameter API carries no event flags. */
  if(event->flags & ((1U<<19)|(1U<<20))) {
    if(!native->warned) {
      fprintf(stderr,"NXVNC: Command/Option input is not supported by the Intel event-posting interface\n");
      native->warned=1;
    }
    if(event->type==10 || (event->type==11 &&
        (arrow<0 || !native->arrowTargets[arrow]))) return 1;
  }
  if(event->type==12) return 1;
  if(arrow>=0) return NXVNCInputPostArrow(event,&native->arrowTargets[arrow]);
  memset(&data,0,sizeof(data)); memset(params,0,sizeof(params));
  params[EVIOLLPE_TYPE]=event->type;
  params[EVIOLLPE_LOC_X]=event->x; params[EVIOLLPE_LOC_Y]=event->y;
  if(event->type>=1 && event->type<=7) {
    request=EVIOPTRLLPE;
    data.mouse.pressure=(event->type==1 || event->type==3 ||
                        event->type==6 || event->type==7) ? 255 : 0;
  } else {
    data.key.charSet=event->set; data.key.charCode=event->code;
    data.key.origCharSet=event->originalSet;
    data.key.origCharCode=event->originalCode;
    data.key.keyCode=event->keyCode; data.key.repeat=(short)event->repeat;
  }
  /* Use the SDK's native layout; this is a Mach integer array, not RFB data. */
  memcpy(&params[EVIOLLPE_DATA0],&data,sizeof(data));
  result=NXEvSetParameterInt(native->handle,request,params,EVIOLLPE_SIZE);
  if(result!=0) fprintf(stderr,"NXVNC: Intel event injection failed (%d)\n",result);
  return result==0;
}

int NXVNCInputOpen(NXVNCInput *input,int width,int height)
{
  IntelInput *native;
  NXEventHandle handle;
  NXVNCInputInit(input,width,height,0,0);
  if(width<1 || height<1 || width>32768 || height>32768) return 0;
  /* The native event payload must fit the documented three data words. */
  if(sizeof(NXEventData) != (EVIOLLPE_SIZE-EVIOLLPE_DATA0)*sizeof(unsigned int)) {
    fprintf(stderr,"NXVNC: unsupported Intel event-data layout; view-only\n");
    return 0;
  }
  handle=NXOpenEventStatus();
  if(!handle) {
    fprintf(stderr,"NXVNC: cannot open Intel event status driver; view-only\n");
    return 0;
  }
  native=(IntelInput *)calloc(1,sizeof(*native));
  if(!native) { NXCloseEventStatus(handle); return 0; }
  native->handle=handle; input->post=postIntel; input->context=native;
  fprintf(stderr,"NXVNC: keyboard and two-button mouse input enabled via Intel event status driver\n");
  return 1;
}
void NXVNCInputClose(NXVNCInput *input)
{
  IntelInput *native=(IntelInput *)input->context;
  if(!native) return;
  NXVNCInputReset(input); NXCloseEventStatus(native->handle); free(native);
  input->context=0; input->post=0;
}
#else
int NXVNCInputOpen(NXVNCInput *input,int width,int height)
{
  NXVNCInputInit(input,width,height,0,0);
  fprintf(stderr,"NXVNC: native input requires OPENSTEP/m68k or Intel; view-only\n");
  return 0;
}
void NXVNCInputClose(NXVNCInput *input) { (void)input; }
#endif

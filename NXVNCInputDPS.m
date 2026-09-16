/* Flag-preserving arrow-key delivery for OPENSTEP. GPL-3.0-or-later. */
#include "NXVNCInput.h"
#include "NXVNCPlatform.h"
#include <stdio.h>

#if defined(m68k) || defined(__m68k__) || defined(NXVNC_INPUT_INTEL) || defined(NXVNC_INPUT_DPS_TEST)
#ifdef NXVNC_INPUT_DPS_TEST
#import "tests/input_dps_stub.h"
#else
#import <AppKit/AppKit.h>
#import <AppKit/psops.h>
#import <AppKit/psopsNeXT.h>
#endif
#import <Foundation/NSException.h>

int NXVNCInputPostArrow(const NXVNCInputEvent *event,int *target)
{
  int active, time;
  int volatile success=0;
  unsigned long data1, data2;
  NSDPSContext *context=[NSApp context];
  if(!context) return 0;
  /* posteventbycontext supplies the event flags that EVSIOLLPE cannot carry.
     Its subtype and two data words cover repeat, charset/character, and
     keycode/original character in the native event payload. The reserved first
     short (origCharSet in the driver) is not expressible through this API.
     Window zero lets the receiving app dispatch keys to its key window. */
#ifdef NXVNC_INPUT_INTEL
  data1=((unsigned long)event->code<<16)|event->set;
  data2=((unsigned long)event->originalCode<<16)|event->keyCode;
#else
  data1=((unsigned long)event->set<<16)|event->code;
  data2=((unsigned long)event->keyCode<<16)|event->originalCode;
#endif
  NS_DURING
    [NSDPSContext setCurrentContext:context];
    if(event->type==10 && !*target) {
      PScurrentactiveapp(&active);
      *target=active;
    }
    if(*target) {
      int posted=0;
      PSrealtime(&time);
      PSposteventbycontext(event->type,0.0,0.0,time,(int)event->flags,0,
                           event->repeat,(int)data1,(int)data2,*target,&posted);
      success=posted;
    } else success=1; /* No active application: nothing to receive the key. */
  NS_HANDLER
    NSLog(@"NXVNC: arrow event posting failed: %@",localException);
    success=0;
  NS_ENDHANDLER
  if(event->type==11 || !success) *target=0;
  if(!success) fprintf(stderr,"NXVNC: Window Server rejected arrow event\n");
  return success;
}
#else
int NXVNCInputPostArrow(const NXVNCInputEvent *event,int *target)
{ (void)event; (void)target; return 0; }
#endif

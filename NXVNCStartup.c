/* Acquire only the native input capability while elevated, then permanently
   return to the invoking user before GUI initialization and networking.
   GPL-3.0-or-later. */
#include "NXVNCStartup.h"
#include "NXVNCPlatform.h"
#include <sys/types.h>
#include <unistd.h>
#ifndef __APPLE__
#include <libc.h>
#endif
#include <stdio.h>
#ifdef NXVNC_STARTUP_TEST
#include "tests/startup_system_stub.h"
#endif

int NXVNCPrepareInput(NXVNCInput *input,int enabled)
{
  uid_t user=getuid();
  gid_t group=getgid();
  int elevated=geteuid()!=user || getegid()!=group;
  NXVNCInputInit(input,32768,32768,0,0);
  /* Setuid launches preserve the real invoking UID. A root login/su/sudo
     launch does not identify a safe user to return to; never guess one. */
  if(user==0) {
    fprintf(stderr,"NXVNC: launch the installed setuid executable from your normal user account, not as root\n");
    return 0;
  }
  if(enabled) {
#ifdef NXVNC_INPUT_INTEL
    if(geteuid()!=0)
      fprintf(stderr,"NXVNC: Intel input requires the setuid installation; continuing view-only\n");
    else
#endif
      /* Bounds are replaced with the screen dimensions after GUI startup.
         Opening the handle does not post an event or contact AppKit. */
      NXVNCInputOpen(input,32768,32768);
  }
  if(elevated) {
    /* This executable is installed setuid, not setgid. Supplementary groups
       therefore already belong to the invoking user and remain unchanged. */
    if(setgid(group)<0 || setuid(user)<0 || getuid()!=user || geteuid()!=user ||
        getgid()!=group || getegid()!=group || setuid(0)==0) {
      fprintf(stderr,"NXVNC: cannot permanently drop privileges; refusing to start\n");
      NXVNCInputClose(input);
      return 0;
    }
    fprintf(stderr,"NXVNC: privileges dropped to the invoking user\n");
  }
  return 1;
}

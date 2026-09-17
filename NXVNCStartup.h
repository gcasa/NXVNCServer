/* Early native-input acquisition and credential drop. GPL-3.0-or-later. */
#ifndef NXVNC_STARTUP_H
#define NXVNC_STARTUP_H
#include "NXVNCInput.h"
/* Call before allocating Foundation/AppKit objects or opening a listener.
   Initializes input; success includes view-only fallback. Zero is fatal. */
int NXVNCPrepareInput(NXVNCInput *input,int enabled);
#endif

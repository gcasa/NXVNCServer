/* Optional OPENSTEP Interceptor capture backend. GPL-3.0-or-later. */
#ifndef NXVNC_INTERCEPTOR_FRAMEBUFFER_H
#define NXVNC_INTERCEPTOR_FRAMEBUFFER_H

#import "NXVNCFramebuffer.h"

/** Mapped screen capture, with the inherited DPS implementation as fallback. */
@interface NXVNCInterceptorFramebuffer : NXVNCScreenFramebuffer
{
  id _mappedFramebuffer;
  unsigned char *_snapshot;
  int _mappedStride, _mappedBits, _mappedInvert;
}
- init;
@end

/** Returns an owned screen framebuffer. NXVNC_CAPTURE selects auto, dps,
 * or interceptor. Auto tries Interceptor on i386 and DPS elsewhere.
 * An unavailable Interceptor backend always falls back to DPS. */
NXVNCFramebuffer *NXVNCCreateScreenFramebuffer(void);

#endif

# NXVNCserver

An intentionally small VNC/RFB display server for NeXTSTEP 3.3/OPENSTEP-era
systems.  The source uses Objective-C 1.0 messaging, `Object`, C89 declarations,
BSD sockets, and GCC 2.7-compatible syntax.

## What it implements

* RFB 3.3 server handshake
* `None` security (security type 1)
* negotiated 8-, 16-, or 32-bit true-color pixels in either byte order
* raw framebuffer encoding
* requested rectangular and incremental framebuffer updates
* one client at a time, reconnectable
* native screen acquisition through Display PostScript's `NXSizeBitmap()` and
  `NXReadBitmap()` when compiled with `NEXTSTEP`
* a moving test pattern on other systems

Keyboard and pointer messages are consumed but are not injected.  This first
version is therefore a display server, not yet a remote-control server.

## Building on NeXTSTEP/OPENSTEP

Install the Developer tools, then run:

    make
    ./nxvncserver 5900

If your headers do not predefine `NEXTSTEP`, add `-DNEXTSTEP` to `CFLAGS`.
The shipped Makefile uses the historical Objective-C runtime and system shared
library.  On OPENSTEP 4.x, replace `-lsys_s` with the platform's normal AppKit
link flags if required by that installation.

Connect a VNC viewer to `next-host:5900`. Because there is no authentication,
bind or firewall this port to a trusted network only; an SSH tunnel is the
preferred exposure method.

## Design

`NXVNCFramebuffer` owns the canonical RFB pixel buffer. Its native subclass
captures window 0 (the root/screen window) using the documented Display
PostScript bitmap API and flips NeXT's bottom-up scan lines. `NXVNCRFBServer`
owns all network and RFB framing. Keeping those responsibilities separate makes
it possible to replace screen capture for a particular NeXT OS release without
touching the protocol implementation.

The native implementation follows the documented NeXTSTEP 3.3 `NXSizeBitmap`
and `NXReadBitmap` ABI. Use the declaration in the target machine's
`appkit/graphics.h` as authoritative if an older SDK reports an argument
mismatch.

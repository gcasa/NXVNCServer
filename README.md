# NXVNCserver

An intentionally small VNC/RFB display server for OPENSTEP 4.2 systems. The
source uses Objective-C 1.0 messaging, OPENSTEP Foundation and AppKit classes,
C89 declarations, BSD sockets, and GCC 2.7-compatible syntax.

## What it implements

* RFB 3.3 server handshake
* `None` security (security type 1)
* negotiated 8-, 16-, or 32-bit true-color pixels in either byte order
* raw framebuffer encoding
* requested rectangular and incremental framebuffer updates
* one client at a time, reconnectable
* native screen acquisition through `NSDPSContext` and `NSBitmapImageRep`
* a moving test pattern on other systems

Keyboard and pointer messages are consumed but are not injected.  This first
version is therefore a display server, not yet a remote-control server.

## Building on OPENSTEP 4.2

Install the Developer tools, then run:

    make
    ./nxvncserver 5900

The Makefile links the `AppKit` and `Foundation` frameworks directly. It does
not require the NeXTSTEP compatibility libraries `libNeXT_s` or `libsys_s`.

Connect a VNC viewer to `next-host:5900`. Because there is no authentication,
bind or firewall this port to a trusted network only; an SSH tunnel is the
preferred exposure method.

## Design

`NXVNCFramebuffer` owns the canonical RFB pixel buffer. Its native subclass
selects window 0 (the root/screen window) through the application's
`NSDPSContext`, captures it with `NSBitmapImageRep`, and flips the bottom-up
scan lines. `NXVNCRFBServer`
owns all network and RFB framing. Keeping those responsibilities separate makes
it possible to replace screen capture for a particular NeXT OS release without
touching the protocol implementation.

The implementation contains no NeXTSTEP `NX*` APIs, legacy `Object` or
`Application` classes, or references to NeXTSTEP compatibility libraries.

## Documentation

The public interfaces use GNUstep's autogsdoc comment format.  With GNUstep
Base development tools installed, generate the class reference with:

    make documentation

The generated `.gsdoc` files may be converted to HTML with the standard
GNUstep documentation tools.

## License

NXVNCserver is free software distributed under the GNU General Public License,
version 3 or (at your option) any later version.

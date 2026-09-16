# NXVNCserver

An intentionally small VNC/RFB display server for OPENSTEP 4.2 systems. The
source uses Objective-C 1.0 messaging, OPENSTEP Foundation and AppKit classes,
C89 declarations, BSD sockets, and GCC 2.7-compatible syntax.

## What it implements

* RFB 3.3 server handshake
* `None` security (security type 1)
* negotiated 8-, 16-, or 32-bit true-color pixels in either byte order
* raw, TRLE palette, and Hextile framebuffer encodings
* requested-area capture and updates, with tight changed rectangles for incremental updates
* one client at a time, reconnectable
* Interceptor screen capture on i386, with Display PostScript fallback
* expansion of 1-, 2-, 4-, and 8-bit screen samples to VNC pixel channels
* a moving test pattern on other systems

Remote input selects the native interface at compile time:

* OPENSTEP/m68k opens `/dev/evs0` and posts through `EVSIOLLPE` and
  `EVSIOPTRLLPE`, retaining the m68k event structures and NeXT keyboard codes.
* OPENSTEP/Intel uses `NXOpenEventStatus` and `NXEvSetParameterInt` with
  `EVIOLLPE` and `EVIOPTRLLPE`. Mouse posting updates the system cursor as well
  as delivering the event. Keyboard events use PC scan codes, including the
  event driver's extended codes for arrows and navigation keys.

ASCII typing, shifted text, Control characters, navigation keys, and left/right
clicks and drags are connected. Held keys and buttons are released when the
viewer disconnects. Arrows use the Window Server posting routine to preserve the
numeric-pad flag, with native byte ordering for each architecture.
Intel support has host-side tests but has not yet been built or exercised on
an OPENSTEP/Intel installation. Native behavior still needs verification on genoa.

Neither low-level driver interface has an event-flags argument. Command/Option key chords
are therefore ignored with a log message; modified mouse clicks are ordinary
clicks. Middle-button, wheel, and non-ASCII input are not supported. This backend
does not change hardware modifier state. The test fixture records input without
injecting it into the host desktop.

On Intel, event posting requires a privileged event-status handle. The server
can be installed setuid root: on launch it opens that handle, permanently drops
to the invoking user's UID/GID, and then creates Foundation/AppKit objects and
opens the network listener. No separate input process or executable is used.
The normal user's supplementary groups are preserved; the executable is not
setgid. A failed credential drop aborts startup, including in `--view-only` or
`--test` mode. Launches with real UID zero are refused: run the installed binary
from your normal account rather than using `su` or `sudo` to launch it.

Build normally:

    gnumake

An administrator installs the server once, choosing an existing group containing
only users authorized to control this desktop (replace `vncusers` below):

    gnumake install-setuid INPUT_GROUP=vncusers

Run the installation command as root. Ensure `/usr/local/bin` and its parents
are owned by root and not writable by those users. The installed server is owned
by root and the selected group, with mode `4750`. After installation, launch the
installed copy from your normal user account:

    /usr/local/bin/nxvncserver 5900

Reinstall after rebuilding. The build-tree `./nxvncserver` is not setuid and
starts view-only on Intel. `--view-only` and `--test` skip acquiring the input
handle but still drop elevated credentials. If posting fails, the server attempts
to release held input and continues view-only until restarted. Error `-705`
(`IO_R_PRIVILEGE`) means the driver denied posting access.

If you installed the previous `nxvnc-input-helper`, it is no longer used; an
administrator can remove `/usr/local/libexec/nxvnc-input-helper`.

Keeping the acquired Mach port after dropping UNIX privileges still needs
verification on the target OPENSTEP/Intel installation. Host tests verify
acquisition/drop ordering, failure handling, and view-only startup with mocked
credentials and driver calls.

Use `--view-only` to disable input. `--test` also disables native input. If opening
the event device or event-status handle fails, the server logs the error and
continues view-only. Posting failures are logged separately.

## Building on OPENSTEP 4.2

Install the Developer tools, then run:

    make
    ./nxvncserver 5900

Run `make clean` before rebuilding for another architecture or after copying
a source tree containing object files from another machine. Architecture
selection follows the compiler target; no input-backend option is necessary.

To diagnose a viewer disconnect, capture the server's diagnostics:

    ./nxvncserver 5900 2>error.log

The log identifies handshake failures, unsupported bitmap formats or client
messages, capture exceptions, and socket errors.

For a blank viewer, the first capture logs the bitmap format. The first completed update logs its encoding, byte count, and timings. To isolate screen capture from the VNC
connection, stop the server and run the animated color pattern:

    ./nxvncserver 5900 --test 2>test.log

This uses the same RFB handshake and pixel encoding without screen capture.

The Makefile links the `AppKit` and `Foundation` frameworks directly. It does
not require the NeXTSTEP compatibility libraries `libNeXT_s` or `libsys_s`.

Interceptor is optional and loaded at runtime. Capture defaults to Interceptor
on i386, with DPS fallback if unavailable or unsupported, and DPS elsewhere.
Set `NXVNC_CAPTURE` to `auto` (default), `dps`, or `interceptor` to override.
Interceptor on m68k is unverified. Mapped capture can tear during screen
changes; restart the server after changing display resolution.

Connect a VNC viewer to `next-host:5900`. Because there is no authentication,
bind or firewall this port to a trusted network only; an SSH tunnel is the
preferred exposure method.

## Performance and profiling

The native two-bit grayscale path first checks whole 32-row bands of packed
samples, skipping unchanged bands. Tightly packed 1120x832 frames need only
26 large comparisons when unchanged, instead of 29,120 tiny tile-row
comparisons. Changed bands are checked in 32x32 tiles, then only changed
tiles are expanded, four pixels at a time through a lookup
table. Unchanged RGB pixels remain in the framebuffer. Raw output in the default 32-bit big-endian RGB format bypasses
pixel conversion; other true-color formats use precomputed channel tables.
Socket output is batched into 32 KB writes.

When advertised by the viewer, TRLE encodes 16x16 tiles as solid colors or
packed palettes, with raw tiles for complex images. Hextile is the fallback
for viewers such as TigerVNC that advertise Hextile but not TRLE. The server
never sends an encoding the viewer did not advertise (raw is always allowed).
The four-shade grayscale Hextile path forms rectangles from byte-sized shade
indices and avoids the general color histogram and per-pixel memory comparisons.
Identical spans on consecutive rows become one taller rectangle. Two-color
tiles send their foreground color once instead of repeating it per rectangle.
For example, a 16x16 tile split into black and white halves uses 12 bytes in
32-bit Hextile, compared with 102 bytes for the earlier row-run encoder.
No zlib library is required. If the log says `encoding raw`, enable Hextile in
the viewer's encoding options to use compression.

Incremental requests use per-tile versions to skip unchanged regions. Regions
with changed versions (or without packed-cache support) are compared against
the last pixels delivered to that client. Changed tiles are trimmed to the bounding box of their changed pixels;
adjacent boxes with the same vertical extent are merged. A one-pixel change
therefore sends one pixel instead of a whole 32x32 tile. Fully inspected tiles
can acknowledge their version after the update is sent, including when the
remaining pixels already matched. Partially requested tiles stay unacknowledged.
Only changed regions within the request are sent. Full requests
always send the requested area. An unchanged incremental request receives an
empty update; the default capture limit is four starts per second to avoid an
idle polling loop consuming the CPU. Set `NXVNC_MAX_FPS` to a number between 1
and 60 to change it. This is a ceiling, not an expected FPS; a capture that takes
longer than the interval is not delayed further.

Input is serviced during the polling delay, between encoding batches, and while
nonblocking socket writes wait for a slow viewer. Polling/backpressure waits
use slices of at most 10 ms, but this is not an end-to-end latency guarantee.
Only complete key/pointer messages at the head of the input stream are consumed;
format changes and update requests retain their protocol order. Input behind
such a control message waits for the current update to finish. TCP_NODELAY
avoids delaying small update packets. Input callbacks run before capture and
after the capture window is hidden; an individual synchronous DPS readback or
wait still blocks input. The temporary capture window must not receive injected
mouse clicks.

The comparison cache uses four bytes per screen pixel (about 3.55 MiB for
1120x832), in addition to the existing framebuffer and AppKit capture storage.
The packed cache adds about 233 KB at 1120x832, plus small tile-version tables.
The native capture reads only the requested rectangle. Full-screen requests
still capture the whole screen and use the packed comparison cache, expanding
only changed gray tiles. Partial captures use the gray lookup table directly
(or generic conversion for other formats), preserving pixels outside the request.
They invalidate the packed cache so a subsequent full capture cannot trust stale
tile versions. The first capture and changes in grayscale polarity also
invalidate all packed tiles. Generic framebuffer providers can fall back to a
full refresh through `refreshX:y:width:height:`.

DPS capture configures `setautofill` once per capture window, removes the redundant
initial `orderOut`, and batches setup with ordering before one synchronization.
It still waits after ordering the window in and after hiding it. This reduces
explicit DPS waits from four to two per refresh. The accompanying Grabber source
uses ordered DPS commands without a wait between every operation; native
OPENSTEP validation is still required for this optimized sequence and cropping.
The DPS backend does not use direct framebuffer access.

Log every update's timings with:

    NXVNC_PROFILE=1 ./nxvncserver 5900 2>performance.log

The first update is timed even without this variable. DPS capture also logs
`setup`, `order/wait`, `focus`, `readback`, `materialize`, `unfocus`, and
`hide/wait`, plus the captured area. These separate synchronization costs from
bitmap acquisition. Logged times are wall clock seconds:

* `refresh`: total framebuffer refresh, including capture and expansion.
* `capture` and `expand`: native capture and conversion portions of refresh.
* `packedCompare`: comparison/copying of packed native grayscale tiles.
  For an unchanged native grayscale frame, expansion does no pixel work.
* `other`: remaining refresh time, including first-frame metadata logging and
  releasing the captured bitmap. Full-frame diagnostic scans are not performed.
* `compare`: dirty-region scanning and rectangle-list preparation.
* `encode/buffer`: encoding and output buffering, excluding socket writes.
* `cache`: copying delivered pixels and acknowledging tile versions after sending.
* `socket`: time in socket writes, including any wait for the receiver.
* `total`: the whole update, excluding the polling rate-limit delay.
* `rects` and `bytes`: rectangles and RFB update bytes sent, including headers.

Use `--test` with profiling to measure protocol/encoding costs without DPS.
The test framebuffer's native `capture` and `expand` fields are zero; its
pattern generation is included in `refresh`. Timing on genoa is necessary;
host-side tests cannot establish 68040 performance.

Hextile stops building subrectangles once a tile would use 64 rectangles or would
save less than half the raw payload. Such tiles use Hextile's raw subencoding;
the default pixel format copies raw rows directly. Solid tiles stay compressed.
This bounds rectangle-building work on busy screens but can increase network traffic.
Compare `encode/buffer`, `cache`, `socket`, and `bytes` on genoa to assess the
CPU/network tradeoff.

For native A/B testing, capture comparable idle, typing, dragging, and scrolling
sessions with the same viewer settings:

    NXVNC_PROFILE=1 ./nxvncserver 5900 2>optimized.log
    NXVNC_PROFILE=1 NXVNC_CAPTURE_SYNC=1 NXVNC_FULL_CAPTURE=1 ./nxvncserver 5900 2>compatibility.log

Run these separately. `NXVNC_CAPTURE_SYNC` restores the original four-wait
capture sequence; `NXVNC_FULL_CAPTURE` restores full-screen acquisition even for
small requests. Set either variable independently to isolate its effect.
Check cropped updates near all screen edges and compare `capture stages`,
`compare`, `encode/buffer`, and `bytes`. To explore the rate ceiling after
capture improves:

    NXVNC_PROFILE=1 NXVNC_MAX_FPS=10 ./nxvncserver 5900 2>fps10.log

Host-side tests establish pixel/protocol correctness at the mocked AppKit
boundary, not native DPS rendering or a measured 68040 speedup.

The Intel input implementation follows the NeXT Mach event-driver interface
retained in the archived [event-status implementation](https://github.com/neozeed/Darwin_0.1/blob/master/Libc/drivers.subproj/evs_api.c),
[posting parameter definitions](https://github.com/neozeed/Darwin_0.1/blob/master/kernel/bsd/dev/evio.h),
and [PC keyboard map](https://github.com/neozeed/Darwin_0.1/blob/master/kernel/bsd/dev/i386/PCKeymap.c).
These are successor-system sources, not proof of an OPENSTEP 4.2 runtime test.
Production builds use the installed SDK's event structures. The Intel Mach
posting parameter names and word offsets are defined locally because OPENSTEP
SDKs omit the private Intel `evio.h`; the payload size is checked before use.

## Tests

On a modern Mac with Command Line Tools and Python 3:

    python3 tests/test_rfb.py
    python3 tests/test_startup.py

This compiles the C helpers with C89 warnings as errors, decodes their output
independently, and exercises the real Objective-C server over TCP using a
small deterministic framebuffer fixture. Tests cover raw, TRLE, Hextile,
pixel formats and byte orders, edge tiles, grayscale lookup tables, partial
requests, unchanged frames, off-request changes, format changes, and reconnects.
Tests also check single-pixel updates and merged bounds, compressed byte counts,
fragmented input during the polling delay, and input while an 8 MiB transfer is
blocked by a viewer that stops reading. A deterministic AppKit boundary runs the
production capture code to verify cropped coordinates, untouched pixels, cache
invalidation, callback safety, wait counts, and exception cleanup. Build products
are kept in a temporary directory. Native DPS capture still requires an OPENSTEP
run.

Input tests cover both m68k ioctl and Intel Mach parameter adapters, native key
codes and payloads, arrow routing and DPS word ordering, driver failures, and
disconnect releases. These tests substitute driver and DPS calls; they do not
inject events into the host desktop. On Intel hardware, validate typing,
Shift/Control, arrows, clicks, double-clicks, dragging, and disconnecting while
holding a key or button before treating the port as natively verified.

## Design

`NXVNCFramebuffer` owns the canonical RFB pixel buffer. `NXVNCInterceptorFramebuffer`
reads mapped screen memory and falls back to `NXVNCScreenFramebuffer`, which
uses NeXT's Grabber technique: it briefly orders a borderless nonretained window
over the screen with Display PostScript automatic filling disabled, reads its
focused content with `NSBitmapImageRep`, and removes it before converting the
pixels. AppKit manages window ordering; a capture-window subclass suppresses
painting over the capture. `NSConvertWindowNumberToGlobal` translates the
AppKit window number to the Window Server ID required by `setautofill`.
Nonretained backing is required: `setautofill` does not apply to retained
windows, which would supply their own backing-store pixels instead.
It preserves the bitmap's top-to-bottom row order. `NXVNCRFBServer`
owns all network and RFB framing. Keeping those responsibilities separate makes
it possible to replace screen capture for a particular NeXT OS release without
touching the protocol implementation.

The UI and capture implementation uses OPENSTEP AppKit and Foundation, with no
legacy `Object` or `Application` classes. Intel input also uses the system's
C event-status APIs (`NXOpenEventStatus`, `NXEvSetParameterInt`, and
`NXCloseEventStatus`). No NeXTSTEP compatibility libraries are explicitly linked.

## Documentation

The public interfaces use GNUstep's autogsdoc comment format.  With GNUstep
Base development tools installed, generate the class reference with:

    make documentation

The generated `.gsdoc` files may be converted to HTML with the standard
GNUstep documentation tools.

## License

NXVNCserver is free software distributed under the GNU General Public License,
version 3 or (at your option) any later version.

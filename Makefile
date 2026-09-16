CC = cc
OBJC = cc
CFLAGS = -O2 -Wall -Wno-import -traditional-cpp
OBJCFLAGS = $(CFLAGS) -ObjC
FRAMEWORKS = -framework AppKit -framework Foundation

OBJS = NXVNCEncoding.o NXVNCInput.o NXVNCInputNative.o NXVNCStartup.o NXVNCInputDPS.o NXVNCFramebuffer.o NXVNCInterceptorFramebuffer.o NXVNCRFBServer.o main.o

.PHONY: all clean documentation

all: nxvncserver

NXVNCEncoding.o: NXVNCEncoding.c NXVNCEncoding.h
	$(CC) $(CFLAGS) -c NXVNCEncoding.c

NXVNCInput.o: NXVNCInput.c NXVNCInput.h NXVNCPlatform.h
	$(CC) $(CFLAGS) -c NXVNCInput.c

NXVNCInputNative.o: NXVNCInputNative.c NXVNCInput.h NXVNCPlatform.h
	$(CC) $(CFLAGS) -c NXVNCInputNative.c

NXVNCFramebuffer.o: NXVNCFramebuffer.h NXVNCEncoding.h
NXVNCInputDPS.o: NXVNCInput.h NXVNCPlatform.h
NXVNCInterceptorFramebuffer.o: NXVNCInterceptorFramebuffer.h NXVNCFramebuffer.h NXVNCEncoding.h
main.o: NXVNCInterceptorFramebuffer.h
NXVNCRFBServer.o main.o: NXVNCFramebuffer.h NXVNCRFBServer.h NXVNCEncoding.h NXVNCInput.h

nxvncserver: $(OBJS)
	$(OBJC) -o nxvncserver $(OBJS) $(FRAMEWORKS)

.m.o:
	$(OBJC) $(OBJCFLAGS) -c $<

clean:
	rm -f $(OBJS) nxvncserver NXVNCFramebuffer.gsdoc NXVNCRFBServer.gsdoc

documentation:
	autogsdoc NXVNCFramebuffer.h NXVNCRFBServer.h

NXVNCStartup.o: NXVNCStartup.c NXVNCStartup.h NXVNCInput.h NXVNCPlatform.h
	$(CC) $(CFLAGS) -c NXVNCStartup.c

main.o: NXVNCStartup.h

# Explicit, one-time administrator installation; no separate input executable.
BINDIR = /usr/local/bin
INPUT_GROUP =
.PHONY: install-setuid
install-setuid: nxvncserver
	@test -n "$(INPUT_GROUP)" || (echo "Specify INPUT_GROUP: only this group may control the desktop"; exit 1)
	install -d -m 755 $(BINDIR)
	install -o root -g "$(INPUT_GROUP)" -m 4750 nxvncserver $(BINDIR)/nxvncserver

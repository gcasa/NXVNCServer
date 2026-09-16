CC = cc
OBJC = cc
CFLAGS = -O2 -Wall -Wno-import -traditional-cpp
OBJCFLAGS = $(CFLAGS) -ObjC
FRAMEWORKS = -framework AppKit -framework Foundation

OBJS = NXVNCEncoding.o NXVNCInput.o NXVNCInputNative.o NXVNCFramebuffer.o NXVNCRFBServer.o main.o

.PHONY: all clean documentation

all: nxvncserver

NXVNCEncoding.o: NXVNCEncoding.c NXVNCEncoding.h
	$(CC) $(CFLAGS) -c NXVNCEncoding.c

NXVNCInput.o: NXVNCInput.c NXVNCInput.h
	$(CC) $(CFLAGS) -c NXVNCInput.c

NXVNCInputNative.o: NXVNCInputNative.c NXVNCInput.h
	$(CC) $(CFLAGS) -c NXVNCInputNative.c

NXVNCFramebuffer.o: NXVNCFramebuffer.h NXVNCEncoding.h
NXVNCRFBServer.o main.o: NXVNCFramebuffer.h NXVNCRFBServer.h NXVNCEncoding.h NXVNCInput.h

nxvncserver: $(OBJS)
	$(OBJC) -o nxvncserver $(OBJS) $(FRAMEWORKS)

.m.o:
	$(OBJC) $(OBJCFLAGS) -c $<

clean:
	rm -f $(OBJS) nxvncserver NXVNCFramebuffer.gsdoc NXVNCRFBServer.gsdoc

documentation:
	autogsdoc NXVNCFramebuffer.h NXVNCRFBServer.h

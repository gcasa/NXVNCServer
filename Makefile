CC = gcc
OBJC = gcc
CFLAGS = -O2 -Wall -Wno-import -traditional-cpp
OBJCFLAGS = $(CFLAGS) -ObjC
FRAMEWORKS = -framework AppKit -framework Foundation

OBJS = NXVNCFramebuffer.o NXVNCRFBServer.o main.o

.PHONY: all clean documentation

all: nxvncserver

nxvncserver: $(OBJS)
	$(OBJC) -o nxvncserver $(OBJS) $(FRAMEWORKS)

.m.o:
	$(OBJC) $(OBJCFLAGS) -c $<

clean:
	rm -f $(OBJS) nxvncserver NXVNCFramebuffer.gsdoc NXVNCRFBServer.gsdoc

documentation:
	autogsdoc NXVNCFramebuffer.h NXVNCRFBServer.h

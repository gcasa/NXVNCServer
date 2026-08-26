CC = gcc
OBJC = gcc
CFLAGS = -O2 -Wall -Wno-import -traditional-cpp
OBJCFLAGS = $(CFLAGS) -ObjC
LIBS = -lNeXT_s

OBJS = NXVNCFramebuffer.o NXVNCRFBServer.o main.o

all: nxvncserver

nxvncserver: $(OBJS)
	$(OBJC) -o nxvncserver $(OBJS) $(LIBS)

.m.o:
	$(OBJC) $(OBJCFLAGS) -c $<

clean:
	rm -f $(OBJS) nxvncserver

/* Minimal driver boundary for host tests; never used in a native build. */
#include <unistd.h>
struct evsioLLEvent {
  int type;
  struct { short x,y; } location;
  union {
    struct { unsigned char subx,suby; short eventNum; int click;
      unsigned char pressure; char reserved1; short reserved2; } mouse;
    struct { unsigned short origCharSet; short repeat;
      unsigned short charSet,charCode,keyCode,origCharCode; } key;
  } data;
};
#define EVSIOLLPE 2UL
#define EVSIOPTRLLPE 3UL
int mockInputIoctl(int,unsigned long,struct evsioLLEvent *);
int mockInputOpen(const char *,int,...);
int mockInputClose(int);
#define ioctl mockInputIoctl
#define open mockInputOpen
#define close mockInputClose

/* Mach event parameter ABI used by the Intel backend; no host input injection. */
#ifndef NXVNC_INPUT_INTEL_STUB_H
#define NXVNC_INPUT_INTEL_STUB_H
typedef struct MockEventHandle *NXEventHandle;
typedef union {
  struct { unsigned char subx,suby; short eventNum; int click;
    unsigned char pressure; char reserved1; short reserved2; } mouse;
  struct { unsigned short origCharSet; short repeat;
    unsigned short charSet,charCode,keyCode,origCharCode; } key;
} NXEventData;
#define EVIOLLPE "Ev_LLPostEvent"
#define EVIOPTRLLPE "Ev_PointerLLPostEvent"
enum { EVIOLLPE_TYPE, EVIOLLPE_LOC_X, EVIOLLPE_LOC_Y,
       EVIOLLPE_DATA0, EVIOLLPE_DATA1, EVIOLLPE_DATA2 };
#define EVIOLLPE_SIZE 6
NXEventHandle NXOpenEventStatus(void);
void NXCloseEventStatus(NXEventHandle);
int NXEvSetParameterInt(NXEventHandle,char *,unsigned int *,unsigned int);
#endif

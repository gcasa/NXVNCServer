/* Remote input translation. GPL-3.0-or-later. */
#ifndef NXVNC_INPUT_H
#define NXVNC_INPUT_H

/* NeXT event types and character sets; independent of native header layout. */
typedef struct {
  int type, x, y;
  unsigned flags;
  unsigned short code, set, keyCode, originalCode, originalSet;
  int repeat;
} NXVNCInputEvent;
typedef int (*NXVNCInputPost)(void *, const NXVNCInputEvent *);
typedef struct {
  unsigned long symbol;
  NXVNCInputEvent event;
} NXVNCHeldKey;
typedef struct {
  int width, height, x, y, positioned;
  unsigned buttons, modifiers;
  NXVNCHeldKey keys[128];
  NXVNCInputPost post;
  void *context;
} NXVNCInput;
void NXVNCInputInit(NXVNCInput *, int, int, NXVNCInputPost, void *);
int NXVNCInputKey(NXVNCInput *, unsigned long symbol, int down);
int NXVNCInputPointer(NXVNCInput *, int x, int y, unsigned buttons);
int NXVNCInputReset(NXVNCInput *);
int NXVNCInputOpen(NXVNCInput *, int width, int height);
void NXVNCInputClose(NXVNCInput *);

#endif

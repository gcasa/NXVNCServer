/* RFB keysyms and pointer state to NeXT events. GPL-3.0-or-later. */
#include "NXVNCInput.h"
#include <string.h>

static unsigned flags(unsigned mods)
{
  unsigned f=0;
  if(mods&3) f|=1U<<17;
  if(mods&12) f|=1U<<18;
  if(mods&48) f|=1U<<19;
  if(mods&192) f|=1U<<20;
  if(mods&256) f|=1U<<16;
  return f;
}

void NXVNCInputInit(NXVNCInput *s,int w,int h,NXVNCInputPost post,void *context)
{
  memset(s,0,sizeof(*s)); s->width=w; s->height=h;
  s->post=post; s->context=context;
}

static int emit(NXVNCInput *s,NXVNCInputEvent *e)
{
  e->x=s->x; e->y=s->y;
  return !s->post || s->post(s->context,e);
}

static int modifier(unsigned long sym, unsigned *bit, unsigned short *key)
{
  switch(sym) {
  case 0xffe1: *bit=1; *key=0x52; break;
  case 0xffe2: *bit=2; *key=0x57; break;
  case 0xffe3: *bit=4; *key=0x51; break;
  case 0xffe4: *bit=8; *key=0x51; break;
  case 0xffe9: *bit=16; *key=0x53; break;
  case 0xffea: *bit=32; *key=0x56; break;
  case 0xffe7: case 0xffeb: *bit=64; *key=0x54; break;
  case 0xffe8: case 0xffec: *bit=128; *key=0x55; break;
  case 0xffe5: *bit=256; *key=0; break;
  default: return 0;
  }
  return 1;
}

static int translate(unsigned long sym, NXVNCInputEvent *e)
{
  /* US NeXT hardware key numbers. Text is taken from the viewer's keysym,
     so shifted punctuation does not depend on the viewer's physical layout. */
  static const char letters[]="abcdefghijklmnopqrstuvwxyz";
  static const unsigned char codes[]={0x39,0x35,0x33,0x3b,0x44,0x3c,0x3d,
    0x40,0x06,0x3f,0x3e,0x2d,0x36,0x37,0x07,0x08,0x42,0x45,0x3a,0x48,
    0x46,0x34,0x43,0x32,0x47,0x31};
  static const char normal[]="0123456789-=[]\\;',./` ";
  static const char shifted[]= ")!@#$%^&*(_+{}|:\"<>?~ ";
  static const unsigned char punct[]={0x20,0x4a,0x4b,0x4c,0x4d,0x50,0x4f,
    0x4e,0x1e,0x1f,0x1d,0x1c,0x05,0x04,0x03,0x2c,0x2b,0x2e,0x2f,0x30,0x26,0x38};
  int i;
  memset(e,0,sizeof(*e));
  if(sym>=32 && sym<=126) {
    unsigned ch=(unsigned)sym;
    e->code=(unsigned short)ch; e->originalCode=e->code;
    if(ch>='A' && ch<='Z') ch+='a'-'A';
    for(i=0;letters[i];i++) if(ch==(unsigned char)letters[i]) {
      e->keyCode=codes[i]; e->originalCode=(unsigned short)ch; return 1;
    }
    for(i=0;normal[i];i++) if(ch==(unsigned char)normal[i] || ch==(unsigned char)shifted[i]) {
      e->keyCode=punct[i]; e->originalCode=(unsigned char)normal[i]; return 1;
    }
    return 1;
  }
  switch(sym) {
  case 0xff08: e->code=127; e->keyCode=0x1b; break;
  case 0xff09: case 0xfe20: e->code=9; e->keyCode=0x41; break;
  case 0xff0d: e->code=13; e->keyCode=0x2a; break;
  case 0xff1b: e->code=27; e->keyCode=0x49; break;
  case 0xff51: e->set=1; e->code=0xac; e->keyCode=9; break;
  case 0xff52: e->set=1; e->code=0xad; e->keyCode=0x16; break;
  case 0xff53: e->set=1; e->code=0xae; e->keyCode=0x10; break;
  case 0xff54: e->set=1; e->code=0xaf; e->keyCode=0xf; break;
  case 0xff63: e->set=254; e->code=0x2c; break;
  case 0xffff: e->set=254; e->code=0x2d; break;
  case 0xff50: e->set=254; e->code=0x2e; break;
  case 0xff57: e->set=254; e->code=0x2f; break;
  case 0xff55: e->set=254; e->code=0x30; break;
  case 0xff56: e->set=254; e->code=0x31; break;
  case 0xff8d: e->code=3; e->keyCode=0xd; e->flags=1U<<21; break;
  default:
    if(sym>=0xffbe && sym<=0xffc9) { e->set=254; e->code=(unsigned short)(0x20+sym-0xffbe); }
    else return 0;
  }
  e->originalCode=e->code; e->originalSet=e->set;
  return 1;
}

int NXVNCInputKey(NXVNCInput *s,unsigned long sym,int down)
{
  NXVNCInputEvent e;
  unsigned bit;
  unsigned short key;
  int i,slot=-1;
  for(i=0;i<128;i++) {
    if(s->keys[i].symbol==sym && sym) { slot=i; break; }
  }
  if(down && slot<0) {
    for(i=0;i<128 && s->keys[i].symbol;i++);
    if(i==128) return 0;
  }
  if(modifier(sym,&bit,&key)) {
    unsigned mods=s->modifiers;
    if(bit==256) {
      /* Caps Lock is a latch. Ignore autorepeat while its key is held. */
      if(down && slot<0) mods^=bit;
    } else if(down) mods|=bit; else mods&=~bit;
    memset(&e,0,sizeof(e)); e.type=12; e.keyCode=key; e.flags=flags(mods);
    if(mods!=s->modifiers && !emit(s,&e)) return 0;
    s->modifiers=mods;
  } else {
    if(!down && slot<0) return 1;
    if(slot>=0) e=s->keys[slot].event;
    else if(!translate(sym,&e)) return 1;
    e.type=down ? 10 : 11; e.repeat=down && slot>=0;
    e.flags=(e.flags&(1U<<21))|flags(s->modifiers);
    if(down && e.set==0 && (s->modifiers&12)) {
      if(e.code>=64 && e.code<=127) e.code&=31;
      else if(e.code==' ') e.code=0;
    }
    if(down && e.code==9 && (s->modifiers&3)) e.code=25;
    if(!emit(s,&e)) return 0;
  }
  if(down && slot<0) {
    for(i=0;i<128;i++) if(!s->keys[i].symbol) { slot=i; break; }
    if(slot<0) return 0;
    s->keys[slot].symbol=sym; s->keys[slot].event=e;
  } else if(!down && slot>=0) s->keys[slot].symbol=0;
  return 1;
}

int NXVNCInputPointer(NXVNCInput *s,int x,int y,unsigned buttons)
{
  NXVNCInputEvent e;
  unsigned bit;
  if(s->width<=0 || s->height<=0) return 0;
  if(x<0) x=0; if(x>=s->width) x=s->width-1;
  if(y<0) y=0; if(y>=s->height) y=s->height-1;
  memset(&e,0,sizeof(e)); e.flags=flags(s->modifiers);
  if(!s->positioned || x!=s->x || y!=s->y) {
    s->x=x; s->y=y;
    e.type=(s->buttons&1) ? 6 : ((s->buttons&4) ? 7 : 5);
    if(!emit(s,&e)) return 0;
    s->positioned=1;
  }
  for(bit=1;bit<=4;bit<<=2) if((buttons^s->buttons)&bit) {
    e.type=bit==1 ? ((buttons&bit) ? 1 : 2) : ((buttons&bit) ? 3 : 4);
    if(!emit(s,&e)) return 0;
    s->buttons^=bit;
  }
  /* OPENSTEP has two mouse buttons and no wheel event. */
  return 1;
}

int NXVNCInputReset(NXVNCInput *s)
{
  int i,ok=1;
  NXVNCInputEvent e;
  for(i=0;i<128;i++) if(s->keys[i].symbol)
    if(!NXVNCInputKey(s,s->keys[i].symbol,0)) ok=0;
  if(s->buttons && !NXVNCInputPointer(s,s->x,s->y,0)) ok=0;
  if(s->modifiers) {
    memset(&e,0,sizeof(e)); e.type=12;
    if(!emit(s,&e)) ok=0;
  }
  memset(s->keys,0,sizeof(s->keys)); s->modifiers=s->buttons=0;
  return ok;
}

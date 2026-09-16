/* NXVNCserver pixel helpers. GPL-3.0-or-later. */
#include "NXVNCEncoding.h"
#include <string.h>
#include <stdlib.h>
#include <sys/time.h>
#ifndef __APPLE__
#include <libc.h>
#endif

int NXVNCSetFormat(NXVNCPixelFormat *f, int bpp, int depth, int bigEndian,
                  unsigned r, unsigned g, unsigned b, int rs, int gs, int bs)
{
  unsigned long rm, gm, bm, mask;
  int i, low;
  if ((bpp != 8 && bpp != 16 && bpp != 32) || depth < 1 || depth > bpp
      || !r || !g || !b || r > 65535 || g > 65535 || b > 65535
      || (r & (r + 1)) || (g & (g + 1)) || (b & (b + 1))
      || rs < 0 || gs < 0 || bs < 0 || rs >= bpp || gs >= bpp || bs >= bpp)
    return 0;
  if (r > (0xffffffffUL >> (32 - bpp + rs))
      || g > (0xffffffffUL >> (32 - bpp + gs))
      || b > (0xffffffffUL >> (32 - bpp + bs))) return 0;
  rm = (unsigned long)r << rs; gm = (unsigned long)g << gs;
  bm = (unsigned long)b << bs;
  if ((rm & gm) || (rm & bm) || (gm & bm)) return 0;
  mask = rm | gm | bm;
  f->bytes = bpp / 8; f->bigEndian = bigEndian != 0;
  f->compactBytes = f->bytes; f->compactOffset = 0;
  low = (mask & 0xff000000UL) == 0;
  if (bpp == 32 && depth <= 24 && (low || !(mask & 255))) {
    f->compactBytes = 3;
    f->compactOffset = low ? f->bigEndian : !f->bigEndian;
  }
  f->direct = bpp == 32 && bigEndian && r == 255 && g == 255 && b == 255
              && rs == 16 && gs == 8 && bs == 0;
  for (i = 0; i < 256; i++) {
    f->red[i] = ((unsigned long)i * r / 255) << rs;
    f->green[i] = ((unsigned long)i * g / 255) << gs;
    f->blue[i] = ((unsigned long)i * b / 255) << bs;
  }
  return 1;
}

void NXVNCEncodeRow(const NXVNCPixelFormat *f, const unsigned char *src,
                    unsigned char *dst, int width)
{
  int x, i;
  if (f->direct) { memcpy(dst, src, (unsigned)width * 4); return; }
  for (x = 0; x < width; x++, src += 4) {
    unsigned long v = f->red[src[1]] | f->green[src[2]] | f->blue[src[3]];
    for (i = 0; i < f->bytes; i++)
      *dst++ = (unsigned char)(v >> (8 * (f->bigEndian ? f->bytes-1-i : i)));
  }
}

int NXVNCEncodeTRLE(const NXVNCPixelFormat *f, const unsigned char *src,
                    int stride, int width, int height, unsigned char *out)
{
  unsigned char pixels[1024], palette[16][4], indices[256], *dst = out;
  int x, y, n = 0, count = 0, overflow = 0, i, k, bits, shift;
  unsigned packed;
  for (y = 0; y < height; y++) {
    NXVNCEncodeRow(f, src + y * stride, pixels + y * width * f->bytes, width);
    for (x = 0; x < width; x++, n++) {
      const unsigned char *p = pixels + n * f->bytes + f->compactOffset;
      if (overflow) continue;
      for (i = 0; i < count; i++)
        if (!memcmp(p, palette[i], f->compactBytes)) break;
      if (i == count) {
        if (count == 16) { overflow = 1; continue; }
        memcpy(palette[count++], p, f->compactBytes);
      }
      indices[n] = (unsigned char)i;
    }
  }
  bits = count <= 2 ? 1 : (count <= 4 ? 2 : 4);
  /* Never inflate a tile compared with its raw CPIXEL representation. */
  if (overflow || (count > 1 && count * f->compactBytes
      + ((width * bits + 7) / 8) * height >= n * f->compactBytes)) {
    *dst++ = 0;
    for (i = 0; i < n; i++) {
      memcpy(dst, pixels + i * f->bytes + f->compactOffset, f->compactBytes);
      dst += f->compactBytes;
    }
  } else {
    *dst++ = (unsigned char)count;
    for (i = 0; i < count; i++) {
      memcpy(dst, palette[i], f->compactBytes); dst += f->compactBytes;
    }
    if (count > 1) {
      k = 0;
      for (y = 0; y < height; y++) {
        packed = 0; shift = 8;
        for (x = 0; x < width; x++) {
          shift -= bits; packed |= (unsigned)indices[k++] << shift;
          if (!shift) { *dst++ = (unsigned char)packed; packed = 0; shift = 8; }
        }
        if (shift != 8) *dst++ = (unsigned char)packed;
      }
    }
  }
  return (int)(dst - out);
}

void NXVNCExpandGray2(const unsigned char *src, unsigned char *dst,
                     int width, int invert)
{
  static unsigned char table[2][256][16];
  static int ready = 0;
  int v, p, polarity, x;
  if (!ready) {
    for (polarity = 0; polarity < 2; polarity++)
      for (v = 0; v < 256; v++)
        for (p = 0; p < 4; p++) {
          unsigned char g = (unsigned char)(((v >> (6 - p*2)) & 3) * 85);
          if (polarity) g = 255 - g;
          table[polarity][v][p*4] = 0;
          table[polarity][v][p*4+1] = g;
          table[polarity][v][p*4+2] = g;
          table[polarity][v][p*4+3] = g;
        }
    ready = 1;
  }
  for (x = 0; x + 4 <= width; x += 4, dst += 16)
    memcpy(dst, table[invert != 0][*src++], 16);
  if (x < width) memcpy(dst, table[invert != 0][*src], (width-x)*4);
}

double NXVNCNow(void)
{
  struct timeval tv;
  gettimeofday(&tv, 0);
  return (double)tv.tv_sec + (double)tv.tv_usec / 1000000.0;
}

/* The NeXT monochrome display has exactly four shades. Scan bytes once,
   then form runs from shade indices, without general pixel memcmp calls or
   a 256-entry histogram for every tile. Zero requests the color fallback. */
static int encodeGrayHextile(const NXVNCPixelFormat *f, const unsigned char *src,
                             int stride, int width, int height, unsigned char *out)
{
  static const unsigned char canonical[16] = {
    0,0,0,0, 0,85,85,85, 0,170,170,170, 0,255,255,255
  };
  typedef struct { unsigned char x,y,w,h,color; } GrayRun;
  unsigned char gray[256], palette[16], *dst;
  GrayRun runs[64];
  int previous[16], current[16];
  int counts[4] = {0,0,0,0};
  int x,y,n=0,best=0,index,end,count=0,i,foreground=-1,colors=0,run;
  int bytes=f->bytes, rawSize=1+width*height*bytes, headerSize, runSize;
  for(y=0;y<height;y++) {
    const unsigned char *p=src+y*stride;
    for(x=0;x<width;x++,p+=4) {
      unsigned g=p[1];
      if(g!=p[2] || g!=p[3] || (g!=0 && g!=85 && g!=170 && g!=255)) return 0;
      index=g>>6; gray[n++]=(unsigned char)index; counts[index]++;
    }
  }
  for(i=1;i<4;i++) if(counts[i]>counts[best]) best=i;
  NXVNCEncodeRow(f,canonical,palette,4);
  if(counts[best]==n) {
    out[0]=2; memcpy(out+1,palette+best*bytes,bytes); return 1+bytes;
  }
  for(i=0;i<4;i++) if(counts[i]) { colors++; if(i!=best) foreground=i; }
  if(colors!=2) foreground=-1;
  headerSize=2+bytes+(foreground>=0 ? bytes : 0);
  runSize=2+(foreground>=0 ? 0 : bytes);
  for(x=0;x<width;x++) previous[x]=-1;
  for(y=0;y<height;y++) {
    for(x=0;x<width;x++) current[x]=-1;
    for(x=0;x<width;x=end) {
      index=gray[y*width+x]; end=x+1;
      while(end<width && gray[y*width+end]==index) end++;
      if(index==best) continue;
      run=previous[x];
      /* Extend an identical span from the preceding row in constant time. */
      if(run>=0 && runs[run].w==end-x && runs[run].color==index) {
        runs[run].h++; current[x]=run; continue;
      }
      if(count==64 || headerSize+(count+1)*runSize>=rawSize/2) goto raw;
      runs[count].x=(unsigned char)x; runs[count].y=(unsigned char)y;
      runs[count].w=(unsigned char)(end-x); runs[count].h=1;
      runs[count].color=(unsigned char)index; current[x]=count++;
    }
    for(x=0;x<width;x++) previous[x]=current[x];
  }
  dst=out;
  *dst++=(unsigned char)(foreground>=0 ? 14 : 26);
  memcpy(dst,palette+best*bytes,bytes); dst+=bytes;
  if(foreground>=0) { memcpy(dst,palette+foreground*bytes,bytes); dst+=bytes; }
  *dst++=(unsigned char)count;
  for(run=0;run<count;run++) {
    if(foreground<0) {
      memcpy(dst,palette+runs[run].color*bytes,bytes); dst+=bytes;
    }
    *dst++=(unsigned char)((runs[run].x<<4)|runs[run].y);
    *dst++=(unsigned char)(((runs[run].w-1)<<4)|(runs[run].h-1));
  }
  return (int)(dst-out);
raw:
  out[0]=1; dst=out+1;
  if(f->direct) {
    for(y=0;y<height;y++,dst+=width*bytes)
      NXVNCEncodeRow(f,src+y*stride,dst,width);
  } else {
    for(x=0;x<n;x++) for(i=0;i<bytes;i++) *dst++=palette[gray[x]*bytes+i];
  }
  return rawSize;
}

/* Stateless Hextile fallback for viewers that do not advertise TRLE.
   Every non-raw tile explicitly supplies its background and run colors. */
int NXVNCEncodeHextile(const NXVNCPixelFormat *f, const unsigned char *src,
                      int stride, int width, int height, unsigned char *out)
{
  unsigned char pixels[1024], runs[2048], background[4];
  int x,y,end,length=0,count=0,rawSize=1+width*height*f->bytes;
  int histogram[256], best=0, i;
  int grayLength=encodeGrayHextile(f,src,stride,width,height,out);
  if(grayLength) return grayLength;
  /* Pick the most frequent grayscale shade cheaply; the general-color
     fallback uses the first pixel as the background. */
  memset(histogram,0,sizeof(histogram));
  for(y=0;y<height;y++) {
    NXVNCEncodeRow(f,src+y*stride,pixels+y*width*f->bytes,width);
    for(x=0;x<width;x++) histogram[src[y*stride+x*4+1]]++;
  }
  for(i=1;i<256;i++) if(histogram[i]>histogram[best]) best=i;
  memcpy(background,pixels,f->bytes);
  for(y=0;y<height;y++) for(x=0;x<width;x++)
    if(src[y*stride+x*4+1]==best) {
      memcpy(background,pixels+(y*width+x)*f->bytes,f->bytes);
      y=height; break;
    }
  for(y=0;y<height;y++) for(x=0;x<width;x=end) {
    const unsigned char *p=pixels+(y*width+x)*f->bytes;
    end=x+1;
    while(end<width && !memcmp(p,pixels+(y*width+end)*f->bytes,f->bytes)) end++;
    if(!memcmp(p,background,f->bytes)) continue;
    if(count==64 || 2+f->bytes+length+f->bytes+2 >= rawSize/2) goto raw;
    memcpy(runs+length,p,f->bytes); length+=f->bytes;
    runs[length++]=(unsigned char)((x<<4)|y);
    runs[length++]=(unsigned char)((end-x-1)<<4);
    count++;
  }
  out[0]=(unsigned char)(count ? 26 : 2);
  memcpy(out+1,background,f->bytes);
  if(!count) return 1+f->bytes;
  out[1+f->bytes]=(unsigned char)count;
  memcpy(out+2+f->bytes,runs,length);
  return 2+f->bytes+length;
raw:
  out[0]=1; memcpy(out+1,pixels,rawSize-1); return rawSize;
}

int NXVNCInitGrayCache(NXVNCGrayCache *c, int width, int height)
{
  unsigned long tiles=((unsigned long)width+31)/32*((height+31)/32);
  memset(c,0,sizeof(*c));
  c->width=width; c->height=height; c->rowBytes=(width+3)/4;
  c->previous=(unsigned char *)malloc((unsigned long)c->rowBytes*height);
  c->dirty=(unsigned char *)malloc(tiles);
  c->versions=(unsigned long *)calloc(tiles,sizeof(unsigned long));
  if(!c->previous || !c->dirty || !c->versions) {
    NXVNCFreeGrayCache(c); return 0;
  }
  return 1;
}
void NXVNCFreeGrayCache(NXVNCGrayCache *c)
{
  free(c->previous); free(c->dirty); free(c->versions);
  memset(c,0,sizeof(*c));
}
/* Check a whole 32-row band before subdividing it. A tightly packed
   screen needs one large libc comparison per band instead of one tiny
   comparison per tile row. Never compare capture padding or unused bits. */
static int grayBandEqual(const NXVNCGrayCache *c, const unsigned char *source,
                         int stride, int y, int height)
{
  const unsigned char *src=source+(unsigned long)y*stride;
  const unsigned char *old=c->previous+(unsigned long)y*c->rowBytes;
  int row,whole=c->width/4;
  unsigned mask=(c->width%4) ? (255U << (8-2*(c->width%4))) & 255 : 0;
  if(!mask && stride==c->rowBytes)
    return memcmp(src,old,(unsigned long)height*c->rowBytes)==0;
  for(row=0;row<height;row++,src+=stride,old+=c->rowBytes)
    if(memcmp(src,old,whole) || (mask && ((src[whole]^old[whole])&mask)))
      return 0;
  return 1;
}

int NXVNCRefreshGrayCache(NXVNCGrayCache *c, const unsigned char *source,
                         int stride, int invert, unsigned char *rgb,
                         double *compareSeconds, double *expandSeconds)
{
  int x,y,row,w,h,bytes,whole,changed,index=0,count=0;
  double start=NXVNCNow(),compared;
  unsigned mask;
  for(y=0;y<c->height;y+=32) {
    int columns=(c->width+31)/32;
    h=c->height-y; if(h>32) h=32;
    if(c->valid && c->invert==invert && grayBandEqual(c,source,stride,y,h)) {
      memset(c->dirty+index,0,columns);
      index+=columns;
      continue;
    }
    for(x=0;x<c->width;x+=32,index++) {
      w=c->width-x; if(w>32) w=32;
      bytes=(w+3)/4; whole=w/4;
      mask=(w%4) ? (255U << (8-2*(w%4))) & 255 : 0;
      changed=!c->valid || c->invert!=invert;
      for(row=0;row<h && !changed;row++) {
        const unsigned char *src=source+(y+row)*stride+x/4;
        const unsigned char *old=c->previous+(y+row)*c->rowBytes+x/4;
        changed=memcmp(src,old,whole)!=0
          || (mask && ((src[whole]^old[whole])&mask));
      }
      c->dirty[index]=(unsigned char)(changed!=0);
      if(changed) {
        count++; c->versions[index]++;
        for(row=0;row<h;row++)
          memcpy(c->previous+(y+row)*c->rowBytes+x/4,
                 source+(y+row)*stride+x/4,bytes);
      }
    }
  }
  compared=NXVNCNow(); index=0;
  for(y=0;y<c->height;y+=32) for(x=0;x<c->width;x+=32,index++) {
    if(!c->dirty[index]) continue;
    w=c->width-x; if(w>32) w=32;
    h=c->height-y; if(h>32) h=32;
    for(row=0;row<h;row++)
      NXVNCExpandGray2(c->previous+(y+row)*c->rowBytes+x/4,
                       rgb+((unsigned long)(y+row)*c->width+x)*4,w,invert);
  }
  c->valid=1; c->invert=invert;
  *compareSeconds=compared-start; *expandSeconds=NXVNCNow()-compared;
  return count;
}

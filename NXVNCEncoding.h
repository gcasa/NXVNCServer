/* NXVNCserver pixel helpers. GPL-3.0-or-later. */
#ifndef NXVNC_ENCODING_H
#define NXVNC_ENCODING_H

typedef struct {
  int bytes, compactBytes, compactOffset, direct;
  unsigned long red[256], green[256], blue[256];
  int bigEndian;
} NXVNCPixelFormat;

/* Returns zero for invalid or overlapping true-color fields. */
int NXVNCSetFormat(NXVNCPixelFormat *f, int bpp, int depth, int bigEndian,
                  unsigned r, unsigned g, unsigned b, int rs, int gs, int bs);
void NXVNCEncodeRow(const NXVNCPixelFormat *f, const unsigned char *src,
                    unsigned char *dst, int width);
/* At most 16x16 pixels; output requires 1025 bytes. */
int NXVNCEncodeTRLE(const NXVNCPixelFormat *f, const unsigned char *src,
                    int stride, int width, int height, unsigned char *out);
int NXVNCEncodeHextile(const NXVNCPixelFormat *f, const unsigned char *src,
                      int stride, int width, int height, unsigned char *out);
/* Expand four packed gray pixels per byte, including a partial final byte. */
void NXVNCExpandGray2(const unsigned char *src, unsigned char *dst,
                     int width, int invert);
typedef struct {
  int width, height, rowBytes, valid, invert;
  unsigned char *previous, *dirty;
  unsigned long *versions;
} NXVNCGrayCache;
int NXVNCInitGrayCache(NXVNCGrayCache *cache, int width, int height);
void NXVNCFreeGrayCache(NXVNCGrayCache *cache);
/* Compare packed samples first, then update only changed canonical tiles.
   Row padding and unused bits in the final byte are ignored. */
int NXVNCRefreshGrayCache(NXVNCGrayCache *cache, const unsigned char *source,
                         int stride, int invert, unsigned char *rgb,
                         double *compareSeconds, double *expandSeconds);
double NXVNCNow(void);
#endif

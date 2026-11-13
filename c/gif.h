/*
 * gif.h - GIF87a/89a reader, compositor and writer in plain C.
 *
 * From Brian O'Brien's Readgif (gif_read.cpp, interlace.cpp, 1999) and Writegif
 * (Writegif.cpp, 1998-99, the GIF export of WinFLI 4.0). Fixed on the way:
 *   - the writer filled its colour table backwards (from the image instead of to it);
 *   - 1-bit images need an LZW code size of 2, not 1;
 *   - the colour table size in the packed fields now matches what is written;
 *   - unknown extensions are skipped instead of ending the program;
 *   - a file cut short inside an image keeps the part that is there, as browsers and Pillow do;
 *   - binary images the old writer saved with LZW code size 1 (illegal, rejected by Pillow and
 *     others) are still read, as ffmpeg does;
 *   - frames are kept with their own rectangle, palette, delay, disposal and transparency,
 *     and gif_composite renders them the way a viewer shows them.
 */
#ifndef GIF_H
#define GIF_H

#include <stddef.h>
#include <stdint.h>

typedef struct
{
    int      left, top, width, height;  /* rectangle on the logical screen */
    int      interlaced;                /* as stored; pixels below are always in row order */
    int      ncolors;                   /* colours in the local palette, 0 = use the global one */
    uint8_t  palette[768];
    int      delay;                     /* hundredths of a second */
    int      disposal;                  /* 0 none, 1 keep, 2 restore background, 3 restore previous */
    int      transparent;               /* transparent colour index, -1 = none */
    uint8_t *pixels;                    /* width*height colour indices */
} GIFFrame;

typedef struct
{
    int       width, height;            /* logical screen */
    int       version89;                /* 1 for GIF89a */
    int       ncolors;                  /* global palette size, 0 = none */
    uint8_t   palette[768];
    int       background;               /* background colour index */
    int       loopCount;                /* NETSCAPE2.0 loop count, 0 = forever, -1 = no extension */
    char      comment[256];             /* first comment extension, if any */
    int       truncated;                /* 1 if the file ended inside an image (what was there is kept) */
    int       nFrames;
    GIFFrame *frames;
} GIFFile;

/* Read every frame. NULL with err filled on failure. */
GIFFile *gif_read(const char *path, char *err, size_t errlen);
void     gif_free(GIFFile *g);

/* Render frames 0..upTo onto the logical screen the way a viewer shows them: canvas starts
   transparent; each frame's disposal is applied before the next frame is drawn; transparent
   pixels leave what is underneath. Returns width*height RGBA (malloc'd). */
uint8_t *gif_composite(const GIFFile *g, int upTo);

/* Write a GIF89a. Frames need left/top/width/height, pixels, and either a local palette
   (ncolors > 0) or the global one in g. Returns 1, or 0 with err filled. */
int gif_write(const char *path, const GIFFile *g, char *err, size_t errlen);

/* Lossless optimizer (gifopt.c): re-cut every frame to what changed, transparency where it pays,
   exact palettes, identical frames merged. The result looks exactly like g. NULL on failure. */
GIFFile *gif_optimize(const GIFFile *g, char *err, size_t errlen);

/* Lossy: at most k colours (2..256) over the whole animation, by weighted k-means in OKLab
   (quant.c): every palette entry is rewritten to its colour's representative. Run gif_optimize
   after it. Returns the number of colours left, or -1 with err set. */
int gif_quantize(GIFFile *g, int k, char *err, size_t errlen);

/* 1 if a and b show the same pictures for the same times (identical frames in a row count as one). */
int gif_same_look(const GIFFile *a, const GIFFile *b, char *why, size_t whylen);

#endif

/*
 * fli.h - Autodesk Animator FLI and FLC reader, and FLC writer, in plain C.
 *
 * The reader follows Brian O'Brien's Readfli (Readfli.cpp / Fli.hpp, 1998-2000), the core of
 * WinFLI 98: file header, frames, and the chunks COLOR_256 (4), FLC delta / SS2 (7), COLOR_64 (11),
 * FLI delta / LC (12), BLACK (13), BYTE_RUN (15), COPY (16), postage stamp (18). Fixed on the way:
 *   - COLOR chunks with several packets: the colour index now moves past each packet;
 *   - FLC speed is in milliseconds (FLI speed is in 1/70 s);
 *   - BYTE_RUN lines are decoded to the image width (the old per-line packet count is ignored,
 *     as the FLC specification says, so wide FLC lines with over 255 packets work);
 *   - 64-level colours become 0..255 with (v << 2) | (v >> 4) instead of v * 4;
 *   - chunk sizes are used to step from chunk to chunk; prefix and unknown chunks are skipped.
 * WinFLI only ever wrote GIFs, so the FLC writer is new: BYTE_RUN for the first frame, SS2
 * deltas after it (LC for odd widths, whose SS2 'last byte' word ffmpeg misplaces), COLOR_256 when the palette changes, and the ring frame back to the start.
 */
#ifndef FLI_H
#define FLI_H

#include <stddef.h>
#include <stdint.h>

#define FLI_MAGIC 0xAF11       /* FLI: 320x200, speed in 1/70 s */
#define FLC_MAGIC 0xAF12       /* FLC: any size, speed in ms */
#define FLI_FRAME 0xF1FA
#define FLI_PREFIX 0xF100

typedef struct
{
    uint8_t *pixels;           /* width*height colour indices */
    uint8_t  palette[768];     /* the palette in force for this frame, 0..255 per component */
} FLIFrame;

typedef struct
{
    int       type;            /* FLI_MAGIC or FLC_MAGIC */
    int       width, height;
    int       delayMs;         /* time per frame */
    int       nFrames;         /* frames in the animation (the ring frame is not kept) */
    FLIFrame *frames;
} FLIFile;

/* Read every frame. NULL with err filled on failure. */
FLIFile *fli_read(const char *path, char *err, size_t errlen);
void     fli_free(FLIFile *f);

/* Write an FLC. Returns 1, or 0 with err filled. */
int fli_write_flc(const char *path, const FLIFile *f, char *err, size_t errlen);

#endif

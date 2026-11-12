/*
 * fli.c - FLI/FLC reader and FLC writer. See fli.h.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fli.h"

#define FLI_FLC_COLOR  4       /* COLOR_256 */
#define FLI_FLC_DELTA  7       /* DELTA_FLC / SS2 */
#define FLI_COLOR      11      /* COLOR_64 */
#define FLI_LC         12      /* DELTA_FLI / LC */
#define FLI_BLACK      13
#define FLI_BRUN       15      /* BYTE_RUN */
#define FLI_COPY       16      /* raw pixels */
#define FLI_FLC_PSTAMP 18

static void seterr(char *err, size_t errlen, const char *msg)
{
    if (err && errlen)
    {
        strncpy(err, msg, errlen - 1);
        err[errlen - 1] = 0;
    }
}

static int rd16(const uint8_t *p) { return p[0] | p[1] << 8; }
static int rds16(const uint8_t *p) { return (int16_t) (p[0] | p[1] << 8); }
static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t) p[3] << 24; }

/* The chunk decoders work on [p, end) and never read past end. */

static void do_color(const uint8_t *p, const uint8_t *end, uint8_t *pal, int six_bit)
{
    int npackets, color = 0;
    if (end - p < 2)
        return;
    npackets = rd16(p);
    p += 2;
    while (npackets-- > 0 && end - p >= 2)
    {
        int skip = p[0], n = p[1] ? p[1] : 256, j;
        p += 2;
        color += skip;
        for (j = 0; j < n && color < 256 && end - p >= 3; ++j, ++color, p += 3)
        {
            int k;
            for (k = 0; k < 3; ++k)
                pal[3 * color + k] = six_bit ? (uint8_t) ((p[k] & 63) << 2 | (p[k] & 63) >> 4) : p[k];
        }
        /* fix: the old code did not move past the packet, so a second packet landed on the first */
    }
}

static void do_brun(const uint8_t *p, const uint8_t *end, uint8_t *px, int w, int h)
{
    int y;
    for (y = 0; y < h; ++y)
    {
        uint8_t *row = px + (size_t) y * w;
        int x = 0;
        if (p >= end)
            return;
        p++;                                      /* old packet count: ignored (FLC spec) */
        while (x < w && p < end)
        {
            int n = (int8_t) *p++;
            if (n > 0)                            /* repeat the next byte n times */
            {
                if (p >= end)
                    return;
                for (; n > 0 && x < w; --n)
                    row[x++] = *p;
                p++;
            }
            else if (n < 0)                       /* copy -n bytes */
            {
                for (n = -n; n > 0 && x < w && p < end; --n)
                    row[x++] = *p++;
            }
        }
    }
}

static void do_lc(const uint8_t *p, const uint8_t *end, uint8_t *px, int w, int h)
{
    int y, nlines;
    if (end - p < 4)
        return;
    y = rd16(p);
    nlines = rd16(p + 2);
    p += 4;
    for (; nlines > 0 && y < h && p < end; --nlines, ++y)
    {
        int npackets = *p++, x = 0;
        uint8_t *row = px + (size_t) y * w;
        while (npackets-- > 0 && end - p >= 2)
        {
            int n;
            x += *p++;
            n = (int8_t) *p++;
            if (n > 0)                            /* copy n bytes */
            {
                for (; n > 0 && p < end; --n, ++x, ++p)
                    if (x < w)
                        row[x] = *p;
            }
            else if (n < 0)                       /* repeat the next byte -n times */
            {
                if (p >= end)
                    return;
                for (n = -n; n > 0; --n, ++x)
                    if (x < w)
                        row[x] = *p;
                p++;
            }
        }
    }
}

static void do_ss2(const uint8_t *p, const uint8_t *end, uint8_t *px, int w, int h)
{
    int nlines, y = 0;
    if (end - p < 2)
        return;
    nlines = rd16(p);
    p += 2;
    while (nlines > 0 && end - p >= 2 && y < h)
    {
        int word = rd16(p), npackets, x = 0;
        p += 2;
        if ((word & 0xC000) == 0xC000)            /* line skip: -word lines */
        {
            y -= rds16(p - 2);
            continue;
        }
        if ((word & 0xC000) == 0x8000)            /* last byte of this line, then the packet count */
        {
            px[(size_t) y * w + w - 1] = (uint8_t) (word & 0xFF);
            if (end - p < 2)
                return;
            word = rd16(p);
            p += 2;
            if ((word & 0xC000) != 0)
                return;                           /* malformed */
        }
        if ((word & 0xC000) == 0x4000)            /* undefined: skip it */
            continue;
        npackets = word;
        --nlines;
        while (npackets-- > 0 && end - p >= 2)
        {
            int n;
            x += *p++;                            /* column skip, in bytes */
            n = (int8_t) *p++;
            if (n >= 0)                           /* copy n words */
            {
                for (; n > 0 && end - p >= 2; --n, x += 2, p += 2)
                {
                    if (x < w)     px[(size_t) y * w + x] = p[0];
                    if (x + 1 < w) px[(size_t) y * w + x + 1] = p[1];
                }
            }
            else                                  /* repeat the next word -n times */
            {
                if (end - p < 2)
                    return;
                for (n = -n; n > 0; --n, x += 2)
                {
                    if (x < w)     px[(size_t) y * w + x] = p[0];
                    if (x + 1 < w) px[(size_t) y * w + x + 1] = p[1];
                }
                p += 2;
            }
        }
        ++y;
    }
}

FLIFile *fli_read(const char *path, char *err, size_t errlen)
{
    FILE *fp = fopen(path, "rb");
    uint8_t *data, *px, pal[768];
    long size;
    FLIFile *f;
    size_t pos;
    int speed, total, i;

    if (!fp)
    {
        seterr(err, errlen, "cannot open the file");
        return NULL;
    }
    fseek(fp, 0, SEEK_END);
    size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    data = malloc(size > 0 ? (size_t) size : 1);
    if (!data || fread(data, 1, (size_t) size, fp) != (size_t) size)
    {
        fclose(fp);
        free(data);
        seterr(err, errlen, "cannot read the file");
        return NULL;
    }
    fclose(fp);
    if (size < 128 || (rd16(data + 4) != FLI_MAGIC && rd16(data + 4) != FLC_MAGIC))
    {
        free(data);
        seterr(err, errlen, "not an FLI or FLC file");
        return NULL;
    }
    f = calloc(1, sizeof(FLIFile));
    f->type = rd16(data + 4);
    total = rd16(data + 6);
    f->width = rd16(data + 8);
    f->height = rd16(data + 10);
    speed = (int) rd32(data + 16);
    f->delayMs = f->type == FLI_MAGIC ? (speed * 1000 + 35) / 70 : speed;   /* fix: FLC is in ms */
    if (f->width <= 0 || f->height <= 0 || total <= 0)
    {
        fli_free(f);
        free(data);
        seterr(err, errlen, "bad header");
        return NULL;
    }
    f->frames = calloc(total, sizeof(FLIFrame));
    px = calloc((size_t) f->width * f->height, 1);
    memset(pal, 0, sizeof pal);
    pos = 128;
    if (f->type == FLC_MAGIC && rd32(data + 80) >= 128 && rd32(data + 80) < (uint32_t) size)
        pos = rd32(data + 80);                    /* oframe1, as Readfli seeks to it */

    while (f->nFrames < total && pos + 16 <= (size_t) size)
    {
        uint32_t fsize = rd32(data + pos);
        int ftype = rd16(data + pos + 4), nchunks = rd16(data + pos + 6);
        const uint8_t *p = data + pos + 16, *fend;
        if (fsize < 16 || pos + fsize > (size_t) size)
            fsize = (uint32_t) ((size_t) size - pos);   /* a short last frame: use what is there */
        fend = data + pos + fsize;
        if (ftype == FLI_PREFIX || ftype != FLI_FRAME)
        {
            pos += fsize;                         /* prefix or unknown block: skip it */
            continue;
        }
        for (i = 0; i < nchunks && fend - p >= 6; ++i)
        {
            uint32_t csize = rd32(p);
            int ctype = rd16(p + 4);
            const uint8_t *cend = p + csize;
            if (csize < 6 || csize > (uint32_t) (fend - p))
                cend = fend;
            switch (ctype)
            {
            case FLI_FLC_COLOR: do_color(p + 6, cend, pal, 0); break;
            case FLI_COLOR:     do_color(p + 6, cend, pal, 1); break;
            case FLI_BRUN:      do_brun(p + 6, cend, px, f->width, f->height); break;
            case FLI_LC:        do_lc(p + 6, cend, px, f->width, f->height); break;
            case FLI_FLC_DELTA: do_ss2(p + 6, cend, px, f->width, f->height); break;
            case FLI_BLACK:     memset(px, 0, (size_t) f->width * f->height); break;
            case FLI_COPY:
            {
                size_t n = (size_t) f->width * f->height;
                if ((size_t) (cend - p - 6) < n)
                    n = (size_t) (cend - p - 6);
                memcpy(px, p + 6, n);
                break;
            }
            default:                              /* postage stamp and anything else */
                break;
            }
            p = cend;
        }
        f->frames[f->nFrames].pixels = malloc((size_t) f->width * f->height);
        if (!f->frames[f->nFrames].pixels)
            break;
        memcpy(f->frames[f->nFrames].pixels, px, (size_t) f->width * f->height);
        memcpy(f->frames[f->nFrames].palette, pal, 768);
        f->nFrames++;
        pos += fsize;
    }
    free(px);
    free(data);
    if (f->nFrames == 0)
    {
        fli_free(f);
        seterr(err, errlen, "no frames in the file");
        return NULL;
    }
    return f;
}

void fli_free(FLIFile *f)
{
    int i;
    if (!f)
        return;
    for (i = 0; i < f->nFrames; ++i)
        free(f->frames[i].pixels);
    free(f->frames);
    free(f);
}

/* ---------- writing ---------- */

typedef struct
{
    uint8_t *p;
    size_t n, cap;
    int bad;
} buf;

static void put(buf *b, const void *d, size_t n)
{
    if (b->bad)
        return;
    if (b->n + n > b->cap)
    {
        size_t c = b->cap ? b->cap : 4096;
        uint8_t *q;
        while (b->n + n > c)
            c *= 2;
        q = realloc(b->p, c);
        if (!q)
        {
            b->bad = 1;
            return;
        }
        b->p = q;
        b->cap = c;
    }
    memcpy(b->p + b->n, d, n);
    b->n += n;
}
static void put8(buf *b, int v) { uint8_t c = (uint8_t) v; put(b, &c, 1); }
static void put16(buf *b, int v) { put8(b, v & 255); put8(b, (v >> 8) & 255); }
static void put32(buf *b, uint32_t v) { put16(b, (int) (v & 0xFFFF)); put16(b, (int) (v >> 16)); }
static void set32(buf *b, size_t at, uint32_t v)
{
    if (!b->bad)
    {
        b->p[at] = (uint8_t) v;
        b->p[at + 1] = (uint8_t) (v >> 8);
        b->p[at + 2] = (uint8_t) (v >> 16);
        b->p[at + 3] = (uint8_t) (v >> 24);
    }
}

/* BYTE_RUN: per line an (obsolete) packet count, then runs (n > 0: repeat) or literals (n < 0: copy). */
static void enc_brun(buf *b, const uint8_t *px, int w, int h)
{
    int y;
    for (y = 0; y < h; ++y)
    {
        const uint8_t *row = px + (size_t) y * w;
        size_t countAt = b->n;
        int x = 0, packets = 0;
        put8(b, 0);
        while (x < w)
        {
            int run = 1;
            while (x + run < w && run < 127 && row[x + run] == row[x])
                run++;
            if (run >= 3 || x + run == w)
            {
                put8(b, run);
                put8(b, row[x]);
                x += run;
            }
            else
            {
                int start = x, lit = 0;
                while (x < w && lit < 127)
                {
                    if (x + 2 < w && row[x] == row[x + 1] && row[x] == row[x + 2])
                        break;
                    x++;
                    lit++;
                }
                put8(b, -lit);
                put(b, row + start, lit);
            }
            packets++;
        }
        if (!b->bad)
            b->p[countAt] = (uint8_t) (packets > 255 ? 255 : packets);
    }
}

/* DELTA_FLC (SS2): word-oriented differences from the previous frame. Returns the number of
   lines written; 0 means the frames are the same. */
static int enc_ss2(buf *b, const uint8_t *prev, const uint8_t *cur, int w, int h)
{
    int y, lines = 0, skip = 0, words = w / 2, odd = w & 1;
    size_t linesAt = b->n;
    put16(b, 0);                                  /* line count, filled in below */
    for (y = 0; y < h; ++y)
    {
        const uint8_t *a = prev + (size_t) y * w, *c = cur + (size_t) y * w;
        int lastChanged = odd && a[w - 1] != c[w - 1], wi, packets = 0;
        size_t countAt;
        if (memcmp(a, c, (size_t) w) == 0)
        {
            skip++;
            continue;
        }
        while (skip > 0)                          /* line skip words: -n, high bits 11 */
        {
            int k = skip > 16384 ? 16384 : skip;
            put16(b, (-k) & 0xFFFF);
            skip -= k;
        }
        if (lastChanged)
            put16(b, 0x8000 | c[w - 1]);
        countAt = b->n;
        put16(b, 0);
        wi = 0;
        while (wi < words)
        {
            int gap = 0, n, rep;
            while (wi < words && a[2 * wi] == c[2 * wi] && a[2 * wi + 1] == c[2 * wi + 1])
            {
                wi++;
                gap++;
            }
            if (wi >= words)
                break;
            while (gap * 2 > 254)                 /* column skip is one byte: empty packets */
            {
                put8(b, 254);
                put8(b, 0);
                packets++;
                gap -= 127;
            }
            rep = 1;                              /* equal words in a row? */
            while (wi + rep < words && rep < 127 && c[2 * (wi + rep)] == c[2 * wi] && c[2 * (wi + rep) + 1] == c[2 * wi + 1])
                rep++;
            put8(b, gap * 2);
            if (rep >= 3)
            {
                put8(b, -rep);
                put8(b, c[2 * wi]);
                put8(b, c[2 * wi + 1]);
                wi += rep;
            }
            else                                  /* literal words up to the next unchanged word or run */
            {
                int start = wi;
                n = 0;
                while (wi < words && n < 127)
                {
                    if (a[2 * wi] == c[2 * wi] && a[2 * wi + 1] == c[2 * wi + 1])
                        break;
                    if (wi + 2 < words && c[2 * wi] == c[2 * wi + 2] && c[2 * wi + 1] == c[2 * wi + 3]
                        && c[2 * wi] == c[2 * wi + 4] && c[2 * wi + 1] == c[2 * wi + 5] && n > 0)
                        break;
                    wi++;
                    n++;
                }
                put8(b, n);
                put(b, c + 2 * start, (size_t) n * 2);
            }
            packets++;
        }
        if (!b->bad)
        {
            b->p[countAt] = (uint8_t) (packets & 0xFF);
            b->p[countAt + 1] = (uint8_t) ((packets >> 8) & 0x3F);
        }
        lines++;
    }
    if (!b->bad)
    {
        b->p[linesAt] = (uint8_t) lines;
        b->p[linesAt + 1] = (uint8_t) (lines >> 8);
    }
    return lines;
}

/* DELTA_FLI (LC): byte-oriented differences, used for odd widths. SS2 can only set the last pixel of
   an odd-width line with its "last byte" word, which some decoders (ffmpeg) put in the wrong place.
   Returns the number of lines in the chunk; 0 means the frames are the same. */
static int enc_lc(buf *b, const uint8_t *prev, const uint8_t *cur, int w, int h)
{
    int first = -1, last = -1, y;
    for (y = 0; y < h; ++y)
        if (memcmp(prev + (size_t) y * w, cur + (size_t) y * w, (size_t) w) != 0)
        {
            if (first < 0)
                first = y;
            last = y;
        }
    if (first < 0)
        return 0;
    put16(b, first);                              /* lines to skip */
    put16(b, last - first + 1);                   /* lines that follow */
    for (y = first; y <= last; ++y)
    {
        const uint8_t *a = prev + (size_t) y * w, *c = cur + (size_t) y * w;
        size_t countAt = b->n;
        int x = 0, packets = 0;
        put8(b, 0);
        while (x < w)
        {
            int gap = 0, rep;
            while (x < w && a[x] == c[x] && packets < 250)
            {
                x++;
                gap++;
            }
            if (x >= w)
                break;
            while (gap > 255)                     /* the skip is one byte: empty packets */
            {
                put8(b, 255);
                put8(b, 0);
                packets++;
                gap -= 255;
            }
            put8(b, gap);
            rep = 1;
            while (x + rep < w && rep < 127 && c[x + rep] == c[x])
                rep++;
            if (rep >= 3)
            {
                put8(b, -rep);                    /* negative: repeat one byte */
                put8(b, c[x]);
                x += rep;
            }
            else                                  /* positive: copy bytes; after 250 packets, copy the rest */
            {
                int start = x, n = 0;
                while (x < w && n < 127)
                {
                    if (packets < 250 && a[x] == c[x])
                        break;
                    if (packets < 250 && n > 0 && x + 2 < w && c[x] == c[x + 1] && c[x] == c[x + 2])
                        break;
                    x++;
                    n++;
                }
                put8(b, n);
                put(b, c + start, (size_t) n);
            }
            packets++;
        }
        if (!b->bad)
            b->p[countAt] = (uint8_t) packets;
    }
    return last - first + 1;
}

/* One frame: COLOR_256 if the palette changed, then the picture as BRUN (first) or SS2. */
static void enc_frame(buf *b, const uint8_t *prevPx, const uint8_t *prevPal, const FLIFrame *fr, int w, int h)
{
    size_t frameAt = b->n, chunkAt;
    int chunks = 0;
    put32(b, 0);
    put16(b, FLI_FRAME);
    put16(b, 0);
    put32(b, 0);
    put32(b, 0);
    if (!prevPal || memcmp(prevPal, fr->palette, 768) != 0)
    {
        chunkAt = b->n;
        put32(b, 0);
        put16(b, FLI_FLC_COLOR);
        put16(b, 1);                              /* one packet: skip 0, 256 colours */
        put8(b, 0);
        put8(b, 0);
        put(b, fr->palette, 768);
        set32(b, chunkAt, (uint32_t) (b->n - chunkAt));
        chunks++;
    }
    chunkAt = b->n;
    if (!prevPx)
    {
        put32(b, 0);
        put16(b, FLI_BRUN);
        enc_brun(b, fr->pixels, w, h);
        if ((b->n - chunkAt) & 1)
            put8(b, 0);                           /* keep chunks an even length */
        set32(b, chunkAt, (uint32_t) (b->n - chunkAt));
        chunks++;
    }
    else
    {
        int odd = w & 1;
        put32(b, 0);
        put16(b, odd ? FLI_LC : FLI_FLC_DELTA);
        if ((odd ? enc_lc(b, prevPx, fr->pixels, w, h) : enc_ss2(b, prevPx, fr->pixels, w, h)) == 0)
        {
            b->n = chunkAt;                       /* nothing changed: no chunk at all */
        }
        else
        {
            if ((b->n - chunkAt) & 1)
                put8(b, 0);
            set32(b, chunkAt, (uint32_t) (b->n - chunkAt));
            chunks++;
        }
    }
    set32(b, frameAt, (uint32_t) (b->n - frameAt));
    if (!b->bad)
    {
        b->p[frameAt + 6] = (uint8_t) chunks;
        b->p[frameAt + 7] = (uint8_t) (chunks >> 8);
    }
}

int fli_write_flc(const char *path, const FLIFile *f, char *err, size_t errlen)
{
    buf b = { NULL, 0, 0, 0 };
    FILE *fp;
    int i;
    size_t frame2At = 0;

    if (f->nFrames < 1 || f->width <= 0 || f->height <= 0 || f->nFrames > 65535)
    {
        seterr(err, errlen, "nothing to write");
        return 0;
    }
    /* 128-byte header (layout of Brian's Fli_head) */
    put32(&b, 0);                                 /* size, filled in at the end */
    put16(&b, FLC_MAGIC);
    put16(&b, f->nFrames);
    put16(&b, f->width);
    put16(&b, f->height);
    put16(&b, 8);                                 /* bits a pixel */
    put16(&b, 3);                                 /* flags: written and closed properly */
    put32(&b, (uint32_t) f->delayMs);
    put16(&b, 0);                                 /* reserved */
    put32(&b, 0); put32(&b, 0);                   /* created, creator */
    put32(&b, 0); put32(&b, 0);                   /* updated, updater */
    put16(&b, 1); put16(&b, 1);                   /* aspect x, y */
    while (b.n < 80)
        put8(&b, 0);                              /* reserved2 */
    put32(&b, 128);                               /* oframe1 */
    put32(&b, 0);                                 /* oframe2, filled in below */
    while (b.n < 128)
        put8(&b, 0);                              /* reserved3 */

    for (i = 0; i < f->nFrames; ++i)
    {
        if (i == 1)
            frame2At = b.n;
        enc_frame(&b, i ? f->frames[i - 1].pixels : NULL, i ? f->frames[i - 1].palette : NULL,
                  &f->frames[i], f->width, f->height);
    }
    if (f->nFrames == 1)
        frame2At = b.n;
    /* the ring frame: from the last frame back to the first, so players can loop smoothly */
    enc_frame(&b, f->frames[f->nFrames - 1].pixels, f->frames[f->nFrames - 1].palette, &f->frames[0],
              f->width, f->height);
    set32(&b, 0, (uint32_t) b.n);
    set32(&b, 84, (uint32_t) frame2At);
    if (b.bad)
    {
        free(b.p);
        seterr(err, errlen, "out of memory");
        return 0;
    }
    fp = fopen(path, "wb");
    if (!fp || fwrite(b.p, 1, b.n, fp) != b.n || fclose(fp) != 0)
    {
        free(b.p);
        seterr(err, errlen, "cannot write the file");
        return 0;
    }
    free(b.p);
    return 1;
}

/*
 * gif.c - GIF reader, compositor and writer. See gif.h.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gif.h"
#include "lzw.h"

static void seterr(char *err, size_t errlen, const char *msg)
{
    if (err && errlen)
    {
        strncpy(err, msg, errlen - 1);
        err[errlen - 1] = 0;
    }
}

/* ---------- reading ---------- */

typedef struct
{
    const uint8_t *p;
    size_t n, pos;
    int bad;
} rd;

static int get8(rd *r)
{
    if (r->pos >= r->n)
    {
        r->bad = 1;
        return 0;
    }
    return r->p[r->pos++];
}

static int get16(rd *r)
{
    int a = get8(r);
    return a | get8(r) << 8;     /* GIF is little-endian */
}

/* Collect a chain of sub-blocks (size byte, data, ... , 0) into one buffer. */
static uint8_t *read_subblocks(rd *r, size_t *len)
{
    size_t cap = 4096, n = 0;
    uint8_t *buf = malloc(cap);
    int size;
    if (!buf)
        return NULL;
    while ((size = get8(r)) != 0 && !r->bad)
    {
        if (r->pos + (size_t) size > r->n)        /* file cut short: keep what is there */
        {
            size = (int) (r->n - r->pos);
            r->bad = 1;
        }
        if (n + size > cap)
        {
            uint8_t *q;
            while (n + size > cap)
                cap *= 2;
            q = realloc(buf, cap);
            if (!q)
            {
                free(buf);
                return NULL;
            }
            buf = q;
        }
        memcpy(buf + n, r->p + r->pos, size);
        n += size;
        r->pos += size;
        if (r->bad)
            break;
    }
    *len = n;
    return buf;
}

static void skip_subblocks(rd *r)
{
    int size;
    while ((size = get8(r)) != 0 && !r->bad)
        r->pos += size;
}

/* Interlaced row order: Brian's interlace class (every 8th from 0, every 8th from 4,
   every 4th from 2, every 2nd from 1). Returns the image row of the n-th stored row. */
static int interlace_row(int n, int height)
{
    int pass1 = (height + 7) / 8, pass2 = (height + 3) / 8, pass3 = (height + 1) / 4;
    if (n < pass1)
        return n * 8;
    n -= pass1;
    if (n < pass2)
        return 4 + n * 8;
    n -= pass2;
    if (n < pass3)
        return 2 + n * 4;
    n -= pass3;
    return 1 + n * 2;
}

GIFFile *gif_read(const char *path, char *err, size_t errlen)
{
    FILE *fp = fopen(path, "rb");
    GIFFile *g;
    uint8_t *data;
    long size;
    rd r;
    int packed, cap = 16;
    int gceDelay = 0, gceDisposal = 0, gceTransparent = -1;

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
    r.p = data;
    r.n = (size_t) size;
    r.pos = 0;
    r.bad = 0;

    if (size < 13 || memcmp(data, "GIF", 3) != 0 || (memcmp(data + 3, "87a", 3) != 0 && memcmp(data + 3, "89a", 3) != 0))
    {
        free(data);
        seterr(err, errlen, "not a GIF file");
        return NULL;
    }
    g = calloc(1, sizeof(GIFFile));
    g->frames = calloc(cap, sizeof(GIFFrame));
    g->version89 = data[4] == '9';
    g->loopCount = -1;
    r.pos = 6;

    /* logical screen descriptor */
    g->width = get16(&r);
    g->height = get16(&r);
    packed = get8(&r);
    g->background = get8(&r);
    get8(&r);                                     /* pixel aspect ratio */
    if (packed & 0x80)                            /* global colour table */
    {
        g->ncolors = 1 << ((packed & 7) + 1);
        if (r.pos + 3 * (size_t) g->ncolors > r.n)
            r.bad = 1;
        else
            memcpy(g->palette, data + r.pos, 3 * g->ncolors);
        r.pos += 3 * g->ncolors;
    }

    while (!r.bad)
    {
        int type = get8(&r);
        if (r.bad || type == 0x3B)                /* trailer */
            break;
        if (type == 0x21)                         /* extension */
        {
            int label = get8(&r);
            if (label == 0xF9)                    /* graphic control */
            {
                int bs = get8(&r), pk = get8(&r);
                gceDelay = get16(&r);
                gceTransparent = get8(&r);
                if (!(pk & 1))
                    gceTransparent = -1;
                gceDisposal = (pk >> 2) & 7;
                r.pos += bs > 4 ? bs - 4 : 0;
                skip_subblocks(&r);
            }
            else if (label == 0xFF)               /* application: NETSCAPE2.0 loop count */
            {
                int bs = get8(&r);
                int netscape = bs == 11 && r.pos + 11 <= r.n && memcmp(data + r.pos, "NETSCAPE2.0", 11) == 0;
                size_t len;
                uint8_t *d;
                r.pos += bs;
                d = read_subblocks(&r, &len);
                if (netscape && d && len >= 3 && d[0] == 1)
                    g->loopCount = d[1] | d[2] << 8;
                free(d);
            }
            else if (label == 0xFE && !g->comment[0])   /* comment */
            {
                size_t len;
                uint8_t *d = read_subblocks(&r, &len);
                if (d)
                {
                    size_t n = len < sizeof g->comment - 1 ? len : sizeof g->comment - 1;
                    memcpy(g->comment, d, n);
                    g->comment[n] = 0;
                    free(d);
                }
            }
            else                                  /* plain text, other comments, unknown: skip */
            {
                skip_subblocks(&r);
            }
        }
        else if (type == 0x2C)                    /* image descriptor */
        {
            GIFFrame *f;
            int minCode, row;
            size_t len, npix;
            uint8_t *codes, *tmp;
            long got;

            if (g->nFrames == cap)
            {
                GIFFrame *q = realloc(g->frames, 2 * cap * sizeof(GIFFrame));
                if (!q)
                    break;
                g->frames = q;
                memset(g->frames + cap, 0, cap * sizeof(GIFFrame));
                cap *= 2;
            }
            f = &g->frames[g->nFrames];
            f->left = get16(&r);
            f->top = get16(&r);
            f->width = get16(&r);
            f->height = get16(&r);
            packed = get8(&r);
            f->interlaced = (packed & 0x40) != 0;
            if (packed & 0x80)                    /* local colour table */
            {
                f->ncolors = 1 << ((packed & 7) + 1);
                if (r.pos + 3 * (size_t) f->ncolors > r.n)
                {
                    r.bad = 1;
                    break;
                }
                memcpy(f->palette, data + r.pos, 3 * f->ncolors);
                r.pos += 3 * f->ncolors;
            }
            f->delay = gceDelay;
            f->disposal = gceDisposal;
            f->transparent = gceTransparent;
            gceDelay = 0;                         /* a graphic control block applies to one image */
            gceDisposal = 0;
            gceTransparent = -1;

            minCode = get8(&r);
            codes = read_subblocks(&r, &len);
            if (!codes || f->width <= 0 || f->height <= 0 || (r.bad && len == 0))
            {
                free(codes);
                r.bad = 1;
                break;
            }
            npix = (size_t) f->width * f->height;
            tmp = calloc(npix, 1);
            f->pixels = calloc(npix, 1);
            got = tmp && f->pixels ? lzw_gif_decode(codes, len, minCode, tmp, npix) : -1;
            free(codes);
            if (got < 0)
            {
                free(tmp);
                seterr(err, errlen, "corrupt LZW data");
                g->nFrames++;
                gif_free(g);
                free(data);
                return NULL;
            }
            for (row = 0; row < f->height; ++row) /* undo the interlace */
            {
                int y = f->interlaced ? interlace_row(row, f->height) : row;
                memcpy(f->pixels + (size_t) y * f->width, tmp + (size_t) row * f->width, f->width);
            }
            free(tmp);
            g->nFrames++;
            if (r.bad)                            /* the file was cut short in this image: keep it, stop */
            {
                g->truncated = 1;
                break;
            }
        }
        else
        {
            break;                                /* unknown block: stop, keep what we have */
        }
    }
    free(data);
    if (g->nFrames == 0)
    {
        gif_free(g);
        seterr(err, errlen, "no images in the file");
        return NULL;
    }
    return g;
}

void gif_free(GIFFile *g)
{
    int i;
    if (!g)
        return;
    for (i = 0; i < g->nFrames; ++i)
        free(g->frames[i].pixels);
    free(g->frames);
    free(g);
}

/* ---------- compositing ---------- */

uint8_t *gif_composite(const GIFFile *g, int upTo)
{
    size_t n = (size_t) g->width * g->height * 4;
    uint8_t *canvas = calloc(n ? n : 1, 1);       /* starts fully transparent */
    uint8_t *saved = malloc(n ? n : 1);
    int i, x, y;

    if (!canvas || !saved)
    {
        free(canvas);
        free(saved);
        return NULL;
    }
    if (upTo >= g->nFrames)
        upTo = g->nFrames - 1;
    for (i = 0; i <= upTo; ++i)
    {
        const GIFFrame *f = &g->frames[i];
        const uint8_t *pal = f->ncolors ? f->palette : g->palette;
        int ncol = f->ncolors ? f->ncolors : g->ncolors;

        /* the previous frame's disposal */
        if (i > 0)
        {
            const GIFFrame *p = &g->frames[i - 1];
            if (p->disposal == 2)                 /* restore to background: transparent */
            {
                for (y = p->top; y < p->top + p->height && y < g->height; ++y)
                    for (x = p->left; x < p->left + p->width && x < g->width; ++x)
                        memset(canvas + ((size_t) y * g->width + x) * 4, 0, 4);
            }
            else if (p->disposal == 3)            /* restore to what was there before it */
            {
                memcpy(canvas, saved, n);
            }
        }
        if (f->disposal == 3)
            memcpy(saved, canvas, n);

        for (y = 0; y < f->height; ++y)
        {
            int cy = f->top + y;
            if (cy >= g->height)
                break;
            for (x = 0; x < f->width; ++x)
            {
                int cx = f->left + x, idx = f->pixels[(size_t) y * f->width + x];
                uint8_t *px;
                if (cx >= g->width)
                    break;
                if (idx == f->transparent)
                    continue;
                px = canvas + ((size_t) cy * g->width + cx) * 4;
                if (idx < ncol)
                {
                    px[0] = pal[3 * idx];
                    px[1] = pal[3 * idx + 1];
                    px[2] = pal[3 * idx + 2];
                }
                else
                {
                    px[0] = px[1] = px[2] = 0;    /* index beyond the palette: black */
                }
                px[3] = 255;
            }
        }
    }
    free(saved);
    return canvas;
}

/* ---------- writing ---------- */

static int bits_for(int ncolors)                  /* Brian's get_bitPerPixel */
{
    int b = 1;
    while ((1 << b) < ncolors && b < 8)
        b++;
    return b;
}

static void put16f(FILE *fp, int v)
{
    fputc(v & 255, fp);
    fputc((v >> 8) & 255, fp);
}

static void put_palette(FILE *fp, const uint8_t *pal, int ncolors, int bits)
{
    int i;
    for (i = 0; i < (1 << bits); ++i)             /* pad to a power of two with black */
    {
        if (i < ncolors)
            fwrite(pal + 3 * i, 1, 3, fp);
        else
        {
            fputc(0, fp);
            fputc(0, fp);
            fputc(0, fp);
        }
    }
}

int gif_write(const char *path, const GIFFile *g, char *err, size_t errlen)
{
    FILE *fp = fopen(path, "wb");
    int gbits = g->ncolors ? bits_for(g->ncolors) : 0, i;

    if (!fp)
    {
        seterr(err, errlen, "cannot create the file");
        return 0;
    }
    fwrite("GIF89a", 1, 6, fp);
    put16f(fp, g->width);
    put16f(fp, g->height);
    /* global table | colour resolution 8 bits | not sorted | size (was always 0x80|0x70|bpp-1) */
    fputc(g->ncolors ? 0x80 | 0x70 | (gbits - 1) : 0x70, fp);
    fputc(g->background, fp);
    fputc(0, fp);                                 /* pixel aspect ratio */
    if (g->ncolors)
        put_palette(fp, g->palette, g->ncolors, gbits);

    if (g->loopCount >= 0 && g->nFrames > 1)      /* NETSCAPE2.0 loop count */
    {
        fputc(0x21, fp);
        fputc(0xFF, fp);
        fputc(11, fp);
        fwrite("NETSCAPE2.0", 1, 11, fp);
        fputc(3, fp);
        fputc(1, fp);
        put16f(fp, g->loopCount);
        fputc(0, fp);
    }
    if (g->comment[0])                            /* comment, in sub-blocks of up to 255 */
    {
        size_t len = strlen(g->comment), p = 0;
        fputc(0x21, fp);
        fputc(0xFE, fp);
        while (p < len)
        {
            size_t k = len - p > 255 ? 255 : len - p;
            fputc((int) k, fp);
            fwrite(g->comment + p, 1, k, fp);
            p += k;
        }
        fputc(0, fp);
    }

    for (i = 0; i < g->nFrames; ++i)
    {
        const GIFFrame *f = &g->frames[i];
        int ncol = f->ncolors ? f->ncolors : g->ncolors;
        int bits = bits_for(ncol), minCode = bits < 2 ? 2 : bits;   /* GIF needs at least 2 */
        size_t npix = (size_t) f->width * f->height, clen, p = 0;
        uint8_t *codes;

        if (ncol == 0)
        {
            fclose(fp);
            seterr(err, errlen, "a frame has no palette");
            return 0;
        }
        /* graphic control extension: disposal, transparency, delay */
        fputc(0x21, fp);
        fputc(0xF9, fp);
        fputc(4, fp);
        fputc(((f->disposal & 7) << 2) | (f->transparent >= 0 ? 1 : 0), fp);
        put16f(fp, f->delay);
        fputc(f->transparent >= 0 ? f->transparent : 0, fp);
        fputc(0, fp);

        /* image descriptor (never interlaced on output) */
        fputc(0x2C, fp);
        put16f(fp, f->left);
        put16f(fp, f->top);
        put16f(fp, f->width);
        put16f(fp, f->height);
        fputc(f->ncolors ? 0x80 | (bits - 1) : 0, fp);   /* was always 0x87 */
        if (f->ncolors)
            put_palette(fp, f->palette, f->ncolors, bits);

        fputc(minCode, fp);
        codes = lzw_gif_encode(f->pixels, npix, minCode, &clen);
        if (!codes)
        {
            fclose(fp);
            seterr(err, errlen, "out of memory");
            return 0;
        }
        while (p < clen)                          /* sub-blocks of up to 255 bytes */
        {
            size_t k = clen - p > 255 ? 255 : clen - p;
            fputc((int) k, fp);
            fwrite(codes + p, 1, k, fp);
            p += k;
        }
        fputc(0, fp);
        free(codes);
    }
    fputc(0x3B, fp);                              /* trailer */
    if (fclose(fp) != 0)
    {
        seterr(err, errlen, "write failed");
        return 0;
    }
    return 1;
}

/*
 * gtwrite.c - write a GeoTIFF. See gt_write in geotiff.h.
 *
 * File layout: header (8 bytes), the strips, then the values of tags too big to fit in a
 * directory entry, then the Image File Directory last; the header points at it. Always
 * little-endian ("II"), written byte by byte so the result is the same on any machine.
 */
#include <stdlib.h>
#include <string.h>
#include "geotiff.h"
#include "lzw.h"

#define MAXTAGS 32

typedef struct
{
    uint16_t id, type;
    uint32_t count;
    uint8_t *data;      /* little-endian bytes */
    uint32_t size;
} WTag;

typedef struct
{
    WTag tags[MAXTAGS];
    int  n;
} TagList;

static void seterr(char *err, size_t errlen, const char *msg)
{
    if (err && errlen)
    {
        strncpy(err, msg, errlen - 1);
        err[errlen - 1] = 0;
    }
}

static void put16(uint8_t *p, uint16_t v) { p[0] = (uint8_t) v; p[1] = (uint8_t) (v >> 8); }
static void put32(uint8_t *p, uint32_t v) { put16(p, (uint16_t) v); put16(p + 2, (uint16_t) (v >> 16)); }
static void put64(uint8_t *p, double d)
{
    uint64_t v;
    int i;
    memcpy(&v, &d, 8);
    for (i = 0; i < 8; ++i)
        p[i] = (uint8_t) (v >> (8 * i));
}

static int hostIsBig(void)
{
    uint16_t x = 1;
    return *(uint8_t *) &x == 0;
}

static WTag *add_tag(TagList *t, uint16_t id, uint16_t type, uint32_t count, uint32_t size)
{
    WTag *w;
    if (t->n >= MAXTAGS)
        return NULL;
    w = &t->tags[t->n++];
    w->id = id;
    w->type = type;
    w->count = count;
    w->size = size;
    w->data = calloc(size ? size : 1, 1);
    return w->data ? w : NULL;
}

static int add_shorts(TagList *t, uint16_t id, const uint16_t *v, uint32_t n)
{
    WTag *w = add_tag(t, id, TIF_SHORT, n, 2 * n);
    uint32_t i;
    if (!w)
        return 0;
    for (i = 0; i < n; ++i)
        put16(w->data + 2 * i, v[i]);
    return 1;
}

static int add_short(TagList *t, uint16_t id, uint16_t v) { return add_shorts(t, id, &v, 1); }

static int add_longs(TagList *t, uint16_t id, const uint32_t *v, uint32_t n)
{
    WTag *w = add_tag(t, id, TIF_LONG, n, 4 * n);
    uint32_t i;
    if (!w)
        return 0;
    for (i = 0; i < n; ++i)
        put32(w->data + 4 * i, v[i]);
    return 1;
}

static int add_doubles(TagList *t, uint16_t id, const double *v, uint32_t n)
{
    WTag *w = add_tag(t, id, TIF_DOUBLE, n, 8 * n);
    uint32_t i;
    if (!w)
        return 0;
    for (i = 0; i < n; ++i)
        put64(w->data + 8 * i, v[i]);
    return 1;
}

static int add_ascii(TagList *t, uint16_t id, const char *s)
{
    uint32_t n = (uint32_t) strlen(s) + 1;
    WTag *w = add_tag(t, id, TIF_ASCII, n, n);
    if (!w)
        return 0;
    memcpy(w->data, s, n);
    return 1;
}

static int cmp_tags(const void *a, const void *b)
{
    return (int) ((const WTag *) a)->id - (int) ((const WTag *) b)->id;
}

/* PackBits: runs of 3 or more equal bytes become a repeat, the rest literal runs of up to 128. */
static uint8_t *packbits_encode(const uint8_t *in, size_t n, size_t *outlen)
{
    uint8_t *out = malloc(n + n / 128 + 2);
    size_t i = 0, o = 0;
    if (!out)
        return NULL;
    while (i < n)
    {
        size_t run = 1;
        while (i + run < n && run < 128 && in[i + run] == in[i])
            run++;
        if (run >= 3)
        {
            out[o++] = (uint8_t) (int8_t) (1 - (int) run);
            out[o++] = in[i];
            i += run;
        }
        else
        {
            size_t start = i, lit = 0;
            while (i < n && lit < 128)
            {
                if (i + 2 < n && in[i] == in[i + 1] && in[i] == in[i + 2])
                    break;              /* a run starts here */
                i++;
                lit++;
            }
            out[o++] = (uint8_t) (lit - 1);
            memcpy(out + o, in + start, lit);
            o += lit;
        }
    }
    *outlen = o;
    return out;
}

/* Horizontal differencing (Predictor 2) on one strip, host byte order, right to left. */
static void apply_predictor(uint8_t *buf, uint32_t rows, uint32_t width, int spp, int bytes)
{
    size_t rowSamples = (size_t) width * spp, i;
    uint32_t r;
    for (r = 0; r < rows; ++r)
    {
        if (bytes == 1)
        {
            uint8_t *p = buf + r * rowSamples;
            for (i = rowSamples - 1; i >= (size_t) spp; --i)
                p[i] = (uint8_t) (p[i] - p[i - spp]);
        }
        else if (bytes == 2)
        {
            uint16_t *p = (uint16_t *) buf + r * rowSamples;
            for (i = rowSamples - 1; i >= (size_t) spp; --i)
                p[i] = (uint16_t) (p[i] - p[i - spp]);
        }
        else
        {
            uint32_t *p = (uint32_t *) buf + r * rowSamples;
            for (i = rowSamples - 1; i >= (size_t) spp; --i)
                p[i] = p[i] - p[i - spp];
        }
    }
}

/* Host order to little-endian, in place. */
static void to_little(uint8_t *p, size_t nvalues, int bytes)
{
    size_t i;
    int a, b;
    if (bytes == 1 || !hostIsBig())
        return;
    for (i = 0; i < nvalues; ++i, p += bytes)
        for (a = 0, b = bytes - 1; a < b; ++a, --b)
        {
            uint8_t t = p[a];
            p[a] = p[b];
            p[b] = t;
        }
}

static int write_at(FILE *fp, long offset, const void *buf, size_t n)
{
    return fseek(fp, offset, SEEK_SET) == 0 && fwrite(buf, 1, n, fp) == n;
}

int gt_write(const char *path, const uint8_t *pixels, uint32_t width, uint32_t height,
             uint16_t spp, uint16_t bitsPerSample, const GTWriteOptions *o, char *err, size_t errlen)
{
    GTWriteOptions dflt;
    TagList tl;
    FILE *fp;
    int bytes = bitsPerSample / 8, i, ok = 0;
    size_t rowBytes = (size_t) width * spp * bytes;
    uint32_t rps, nStrips, s, *offsets = NULL, *counts = NULL, pos, ifd;
    uint8_t h[8], *strip = NULL;
    uint16_t bps[4], photometric;

    memset(&tl, 0, sizeof tl);
    if (!o)
    {
        memset(&dflt, 0, sizeof dflt);
        o = &dflt;
    }
    if (width == 0 || height == 0 || spp < 1 || spp > 4 || (bytes != 1 && bytes != 2 && bytes != 4)
        || bitsPerSample % 8)
    {
        seterr(err, errlen, "need 1-4 samples per pixel of 8, 16 or 32 bits");
        return 0;
    }
    if (o->compression != TIF_COMP_NONE && o->compression != TIF_COMP_LZW && o->compression != TIF_COMP_PACKBITS
        && o->compression != 0)
    {
        seterr(err, errlen, "can write uncompressed, LZW or PackBits");
        return 0;
    }

    rps = o->rowsPerStrip ? o->rowsPerStrip : (uint32_t) (8192 / rowBytes);
    if (rps < 1)
        rps = 1;
    if (rps > height)
        rps = height;
    nStrips = (height + rps - 1) / rps;
    offsets = calloc(nStrips, 4);
    counts = calloc(nStrips, 4);
    strip = malloc(rowBytes * rps);
    fp = fopen(path, "wb");
    if (!offsets || !counts || !strip || !fp)
    {
        seterr(err, errlen, fp ? "out of memory" : "cannot create the file");
        goto done;
    }

    /* header; the IFD offset is filled in at the end */
    put16(h, TIF_INTEL);
    put16(h + 2, TIF_VERSION);
    put32(h + 4, 0);
    if (!write_at(fp, 0, h, 8))
        goto werr;
    pos = 8;

    /* strips */
    for (s = 0; s < nStrips; ++s)
    {
        uint32_t rows = s == nStrips - 1 ? height - s * rps : rps;
        size_t n = rowBytes * rows, outn = n;
        uint8_t *packed = strip;
        memcpy(strip, pixels + (size_t) s * rps * rowBytes, n);
        if (o->predictor == TIF_PRED_HORIZONTAL)
            apply_predictor(strip, rows, width, spp, bytes);
        to_little(strip, n / bytes, bytes);
        if (o->compression == TIF_COMP_LZW)
            packed = lzw_tiff_encode(strip, n, &outn);
        else if (o->compression == TIF_COMP_PACKBITS)
            packed = packbits_encode(strip, n, &outn);
        if (!packed)
        {
            seterr(err, errlen, "out of memory");
            goto done;
        }
        if (!write_at(fp, pos, packed, outn))
        {
            if (packed != strip)
                free(packed);
            goto werr;
        }
        offsets[s] = pos;
        counts[s] = (uint32_t) outn;
        pos += (uint32_t) outn;
        if (packed != strip)
            free(packed);
    }

    /* tags */
    for (i = 0; i < spp; ++i)
        bps[i] = bitsPerSample;
    photometric = spp >= 3 ? 2 : 1;     /* RGB, or grey with 0 = black */
    if (!add_longs(&tl, TIF_IMAGEWIDTH, &width, 1) || !add_longs(&tl, TIF_IMAGELENGTH, &height, 1)
        || !add_shorts(&tl, TIF_BITSPERSAMPLE, bps, spp)
        || !add_short(&tl, TIF_COMPRESSION, o->compression ? o->compression : TIF_COMP_NONE)
        || !add_short(&tl, TIF_PHOTOMETRICINTERPRETAION, photometric)
        || !add_longs(&tl, TIF_STRIPOFFSETS, offsets, nStrips)
        || !add_short(&tl, TIF_SAMPLESPERPIXEL, spp)
        || !add_longs(&tl, TIF_ROWSPERSTRIP, &rps, 1)
        || !add_longs(&tl, TIF_STRIPBYTECOUNTS, counts, nStrips)
        || !add_short(&tl, TIF_PLANARCONFIGURATION, 1))
        goto nomem;
    if (spp == 2 || spp == 4)           /* the last sample is alpha */
        if (!add_short(&tl, TIF_EXTRASAMPLES, 2))
            goto nomem;
    if (o->software && !add_ascii(&tl, TIF_SOFTWARE, o->software))
        goto nomem;
    if (o->predictor == TIF_PRED_HORIZONTAL && !add_short(&tl, TIF_PREDICTOR, TIF_PRED_HORIZONTAL))
        goto nomem;
    if (o->sampleFormat > 1)
    {
        uint16_t sf[4];
        for (i = 0; i < spp; ++i)
            sf[i] = o->sampleFormat;
        if (!add_shorts(&tl, TIF_SAMPLEFORMAT, sf, spp))
            goto nomem;
    }

    /* georeferencing */
    if (o->hasTransform)
    {
        double g[6];
        memcpy(g, o->gt, sizeof g);
        if (o->pixelIsPoint)            /* tie the pixel centre, not its corner */
        {
            g[0] += 0.5 * g[1] + 0.5 * g[2];
            g[3] += 0.5 * g[4] + 0.5 * g[5];
        }
        if (g[2] == 0 && g[4] == 0)
        {
            double scale[3] = { g[1], -g[5], 0 }, tie[6] = { 0, 0, 0, g[0], g[3], 0 };
            if (!add_doubles(&tl, TIF_MODELPIXELSCALE, scale, 3) || !add_doubles(&tl, TIF_MODELTIEPOINT, tie, 6))
                goto nomem;
        }
        else                            /* rotated or sheared: the full matrix */
        {
            double m[16] = { g[1], g[2], 0, g[0], g[4], g[5], 0, g[3], 0, 0, 0, 0, 0, 0, 0, 1 };
            if (!add_doubles(&tl, TIF_MODELTRANSFORMATION, m, 16))
                goto nomem;
        }
    }
    if (o->hasTransform || o->epsg)
    {
        uint16_t keys[4 + 4 * 4];
        int nk = 0;
        char cit[256];
        uint16_t citLen = 0;
        if (o->citation)
        {
            size_t L = strlen(o->citation);
            if (L > sizeof cit - 2)
                L = sizeof cit - 2;
            memcpy(cit, o->citation, L);
            cit[L] = '|';               /* GeoAsciiParams strings end with '|' */
            cit[L + 1] = 0;
            citLen = (uint16_t) (L + 1);
        }
#define KEY(id, loc, cnt, val) do { keys[4 + 4 * nk] = (id); keys[5 + 4 * nk] = (loc); \
                                    keys[6 + 4 * nk] = (cnt); keys[7 + 4 * nk] = (val); nk++; } while (0)
        KEY(GK_GTModelType, 0, 1, o->geographic ? 2 : 1);
        KEY(GK_GTRasterType, 0, 1, o->pixelIsPoint ? 2 : 1);
        if (citLen)
            KEY(GK_GTCitation, TIF_GEOASCIIPARAMS, citLen, 0);
        if (o->epsg)
            KEY(o->geographic ? GK_GeographicType : GK_ProjectedCSType, 0, 1, (uint16_t) o->epsg);
#undef KEY
        keys[0] = 1;                    /* KeyDirectoryVersion */
        keys[1] = 1;                    /* KeyRevision 1.1 */
        keys[2] = 1;                    /* MinorRevision */
        keys[3] = (uint16_t) nk;
        if (!add_shorts(&tl, TIF_GEOKEYDIRECTORY, keys, (uint32_t) (4 + 4 * nk)))
            goto nomem;
        if (citLen && !add_ascii(&tl, TIF_GEOASCIIPARAMS, cit))
            goto nomem;
    }

    /* values that do not fit in 4 bytes go after the strips, each on an even offset */
    qsort(tl.tags, tl.n, sizeof(WTag), cmp_tags);
    for (i = 0; i < tl.n; ++i)
    {
        WTag *w = &tl.tags[i];
        if (w->size > 4)
        {
            if (pos & 1)
            {
                uint8_t z = 0;
                if (!write_at(fp, pos, &z, 1))
                    goto werr;
                pos++;
            }
            if (!write_at(fp, pos, w->data, w->size))
                goto werr;
            put32(w->data, pos);         /* reuse the first 4 bytes to remember the offset */
            pos += w->size;
        }
    }

    /* the IFD */
    if (pos & 1)
    {
        uint8_t z = 0;
        if (!write_at(fp, pos, &z, 1))
            goto werr;
        pos++;
    }
    ifd = pos;
    {
        uint8_t e[12];
        put16(e, (uint16_t) tl.n);
        if (!write_at(fp, pos, e, 2))
            goto werr;
        pos += 2;
        for (i = 0; i < tl.n; ++i)
        {
            WTag *w = &tl.tags[i];
            put16(e, w->id);
            put16(e + 2, w->type);
            put32(e + 4, w->count);
            memset(e + 8, 0, 4);
            memcpy(e + 8, w->data, w->size > 4 ? 4 : w->size);   /* the value, or its offset */
            if (!write_at(fp, pos, e, 12))
                goto werr;
            pos += 12;
        }
        put32(e, 0);                     /* no next IFD */
        if (!write_at(fp, pos, e, 4))
            goto werr;
    }
    put32(h + 4, ifd);
    if (!write_at(fp, 4, h + 4, 4))
        goto werr;
    ok = 1;
    goto done;

nomem:
    seterr(err, errlen, "out of memory");
    goto done;
werr:
    seterr(err, errlen, "write failed");
done:
    if (fp && fclose(fp) != 0 && ok)
    {
        seterr(err, errlen, "write failed");
        ok = 0;
    }
    for (i = 0; i < tl.n; ++i)
        free(tl.tags[i].data);
    free(offsets);
    free(counts);
    free(strip);
    return ok;
}

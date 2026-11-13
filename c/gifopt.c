/*
 * gifopt.c - lossless GIF optimizer, for WinFli's banner work.
 *
 * Grew from WinFli 98's bmimage::optimize (drop unused and duplicate palette entries). This goes
 * further, and the result always looks exactly like the original, frame for frame:
 *   - every frame is rendered the way a viewer shows it, then re-cut against what is already on
 *     the screen: only the rectangle that changed is stored;
 *   - inside that rectangle, pixels that did not change may become transparent, which usually
 *     gives LZW long runs; both ways are encoded and the smaller one is kept;
 *   - one global palette with exactly the colours used, when the whole animation has 256 or fewer,
 *     else a small local palette per frame; the transparent index is any slot the frame does not use;
 *   - frames identical to the one before are merged into it (their delays are added);
 *   - when a pixel has to go from coloured back to transparent, the frame before is given
 *     disposal 2 (restore to background), widened to the whole screen if it has to be.
 * Comments and other extensions are dropped; the loop count is kept.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gif.h"
#include "lzw.h"
#include "quant.h"

/* ---------- a tiny colour table: 24-bit colour -> index ---------- */

typedef struct
{
    uint32_t key[1024];        /* colour | 0x1000000, 0 = empty */
    int16_t  val[1024];
    int      n;
} CHash;

static void ch_clear(CHash *h)
{
    memset(h->key, 0, sizeof h->key);
    h->n = 0;
}

static int ch_get(const CHash *h, uint32_t rgb)
{
    uint32_t k = rgb | 0x1000000u, i = (rgb * 2654435761u) >> 22;
    while (h->key[i])
    {
        if (h->key[i] == k)
            return h->val[i];
        i = (i + 1) & 1023;
    }
    return -1;
}

/* Add if new. Returns the index, or -1 when the table already holds max colours. */
static int ch_add(CHash *h, uint32_t rgb, int max)
{
    uint32_t k = rgb | 0x1000000u, i = (rgb * 2654435761u) >> 22;
    while (h->key[i])
    {
        if (h->key[i] == k)
            return h->val[i];
        i = (i + 1) & 1023;
    }
    if (h->n >= max)
        return -1;
    h->key[i] = k;
    h->val[i] = (int16_t) h->n;
    return h->n++;
}

static int cmp_key(const void *a, const void *b)
{
    uint64_t x = pal_sort_key(*(const uint32_t *) a), y = pal_sort_key(*(const uint32_t *) b);
    return x < y ? -1 : x > y;
}

/* Renumber the colours of a table in palette order (greys dark to light, then by hue). */
static void ch_sort(CHash *h)
{
    uint32_t col[256];
    int i, n = 0;
    for (i = 0; i < 1024; ++i)
        if (h->key[i])
            col[n++] = h->key[i] & 0xFFFFFF;
    qsort(col, (size_t) n, sizeof(uint32_t), cmp_key);
    ch_clear(h);
    for (i = 0; i < n; ++i)
        ch_add(h, col[i], 256);
}

/* ---------- rendering the source, one frame at a time ---------- */

typedef struct
{
    const GIFFile *g;
    uint8_t *canvas, *saved;
    int next;                  /* the frame to draw next */
} Stepper;

static int step_init(Stepper *s, const GIFFile *g)
{
    size_t n = (size_t) g->width * g->height * 4;
    s->g = g;
    s->next = 0;
    s->canvas = calloc(n ? n : 1, 1);
    s->saved = malloc(n ? n : 1);
    return s->canvas && s->saved;
}

static void step_free(Stepper *s)
{
    free(s->canvas);
    free(s->saved);
}

/* Draw the next frame (same rules as gif_composite). The canvas then shows frame s->next - 1. */
static void step(Stepper *s)
{
    const GIFFile *g = s->g;
    int i = s->next++, x, y;
    const GIFFrame *f = &g->frames[i];
    const uint8_t *pal = f->ncolors ? f->palette : g->palette;
    int ncol = f->ncolors ? f->ncolors : g->ncolors;
    size_t n = (size_t) g->width * g->height * 4;

    if (i > 0)
    {
        const GIFFrame *p = &g->frames[i - 1];
        if (p->disposal == 2)
        {
            for (y = p->top; y < p->top + p->height && y < g->height; ++y)
                for (x = p->left; x < p->left + p->width && x < g->width; ++x)
                    memset(s->canvas + ((size_t) y * g->width + x) * 4, 0, 4);
        }
        else if (p->disposal == 3)
            memcpy(s->canvas, s->saved, n);
    }
    if (f->disposal == 3)
        memcpy(s->saved, s->canvas, n);
    for (y = 0; y < f->height && f->top + y < g->height; ++y)
        for (x = 0; x < f->width && f->left + x < g->width; ++x)
        {
            int idx = f->pixels[(size_t) y * f->width + x];
            uint8_t *px = s->canvas + ((size_t) (f->top + y) * g->width + f->left + x) * 4;
            if (idx == f->transparent)
                continue;
            if (idx < ncol)
            {
                px[0] = pal[3 * idx];
                px[1] = pal[3 * idx + 1];
                px[2] = pal[3 * idx + 2];
            }
            else
                px[0] = px[1] = px[2] = 0;
            px[3] = 255;
        }
}

/* ---------- building output frames ---------- */

#define RGB(p) (((uint32_t) (p)[0] << 16) | ((uint32_t) (p)[1] << 8) | (p)[2])

static int same(const uint8_t *a, const uint8_t *b)
{
    if (a[3] == 0 && b[3] == 0)
        return 1;
    return a[3] && b[3] && a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}

typedef struct
{
    int     width, height;
    int     global;            /* 1: one global palette in gpal / gmap */
    CHash   gmap;
    uint8_t gpal[768];
    int     gcount, gslots;    /* colours, and palette slots (a power of two) */
    int     reserve;           /* 1: some pixel is transparent, keep a slot free for it */
} Opt;

static int bits_of(int n)
{
    int b = 1;
    while ((1 << b) < n && b < 8)
        b++;
    return b;
}

/* Encode one way of cutting the frame. mode 0: unchanged pixels keep their colour; 1: they become
   transparent. Fills f (pixels, palette, transparent) and returns its cost in bytes, or -1. */
static long try_cut(Opt *o, const uint8_t *T, const uint8_t *P, int L, int Tp, int W, int H, int mode, GIFFrame *f)
{
    CHash local;
    uint8_t used[256];
    int x, y, ncol, trans = -1, needT = 0, bits;
    size_t clen;
    uint8_t *codes, *px = malloc((size_t) W * H);
    long cost;

    if (!px)
        return -1;
    ch_clear(&local);
    memset(used, 0, sizeof used);
    /* pass 1: which colours are written, and is a transparent index needed */
    for (y = 0; y < H; ++y)
        for (x = 0; x < W; ++x)
        {
            size_t k = ((size_t) (Tp + y) * o->width + L + x) * 4;
            int keep = mode == 1 && same(T + k, P + k);
            if (keep || T[k + 3] == 0)
            {
                needT = 1;
                continue;
            }
            if (o->global)
                used[ch_get(&o->gmap, RGB(T + k))] = 1;
            else if (ch_add(&local, RGB(T + k), 256) < 0)
            {
                free(px);
                return -1;
            }
        }
    if (!o->global)
        ch_sort(&local);
    if (o->global)
    {
        ncol = o->gslots;
        if (needT)
        {
            for (x = 0; x < o->gslots; ++x)
                if (!used[x])
                {
                    trans = x;
                    break;
                }
            if (trans < 0)
            {
                free(px);
                return -1;
            }
        }
    }
    else
    {
        if (needT)
        {
            if (local.n >= 256)
            {
                free(px);
                return -1;
            }
            trans = local.n;
        }
        ncol = local.n + (needT ? 1 : 0);
        if (ncol < 1)
            ncol = 1;
    }
    /* pass 2: the indices */
    for (y = 0; y < H; ++y)
        for (x = 0; x < W; ++x)
        {
            size_t k = ((size_t) (Tp + y) * o->width + L + x) * 4;
            int keep = mode == 1 && same(T + k, P + k);
            if (keep || T[k + 3] == 0)
                px[(size_t) y * W + x] = (uint8_t) trans;
            else
                px[(size_t) y * W + x] = (uint8_t) (o->global ? ch_get(&o->gmap, RGB(T + k)) : ch_get(&local, RGB(T + k)));
        }
    bits = bits_of(ncol);
    codes = lzw_gif_encode_best(px, (size_t) W * H, bits < 2 ? 2 : bits, &clen);
    if (!codes)
    {
        free(px);
        return -1;
    }
    free(codes);
    cost = (long) clen + (long) clen / 255 + 1;
    memset(f, 0, sizeof *f);
    f->left = L;
    f->top = Tp;
    f->width = W;
    f->height = H;
    f->transparent = trans;
    f->pixels = px;
    if (!o->global)
    {
        int i;
        for (i = 0; i < 1024; ++i)
            if (local.key[i])
            {
                uint32_t c = local.key[i] & 0xFFFFFF;
                int v = local.val[i];
                f->palette[3 * v] = (uint8_t) (c >> 16);
                f->palette[3 * v + 1] = (uint8_t) (c >> 8);
                f->palette[3 * v + 2] = (uint8_t) c;
            }
        f->ncolors = ncol;
        cost += 3L << bits;
    }
    return cost;
}

/* The output frame that turns screen P into screen T: the changed rectangle (or the whole screen),
   cut whichever way is smaller. Returns 1, or 0 on failure. */
static int make_frame(Opt *o, const uint8_t *T, const uint8_t *P, int whole, GIFFrame *out)
{
    int x, y, x0 = o->width, y0 = o->height, x1 = -1, y1 = -1, m;
    long best = -1;
    GIFFrame cand;

    if (whole)
    {
        x0 = y0 = 0;
        x1 = o->width - 1;
        y1 = o->height - 1;
    }
    else
        for (y = 0; y < o->height; ++y)
            for (x = 0; x < o->width; ++x)
            {
                size_t k = ((size_t) y * o->width + x) * 4;
                if (!same(T + k, P + k))
                {
                    if (x < x0) x0 = x;
                    if (x > x1) x1 = x;
                    if (y < y0) y0 = y;
                    if (y > y1) y1 = y;
                }
            }
    if (x1 < 0)                                   /* nothing to draw: one transparent pixel */
        x0 = x1 = y0 = y1 = 0;
    for (m = 0; m < 2; ++m)
    {
        long c = try_cut(o, T, P, x0, y0, x1 - x0 + 1, y1 - y0 + 1, m, &cand);
        if (c < 0)
            continue;
        if (best < 0 || c < best)
        {
            if (best >= 0)
                free(out->pixels);
            *out = cand;
            best = c;
        }
        else
            free(cand.pixels);
    }
    return best >= 0;
}

GIFFile *gif_optimize(const GIFFile *src, char *err, size_t errlen)
{
    Opt *o = calloc(1, sizeof(Opt));
    Stepper s;
    GIFFile *g = calloc(1, sizeof(GIFFile));
    size_t n = (size_t) src->width * src->height * 4;
    uint8_t *P = calloc(n ? n : 1, 1), *Tprev = calloc(n ? n : 1, 1), *Pprev = calloc(n ? n : 1, 1);
    int i, k, ok = 1;

    err[0] = 0;
    if (!o || !g || !P || !Tprev || !Pprev || src->nFrames < 1 || !step_init(&s, src))
    {
        snprintf(err, errlen, "out of memory or empty file");
        free(o); free(g); free(P); free(Tprev); free(Pprev);
        return NULL;
    }
    o->width = src->width;
    o->height = src->height;

    /* pass 1: every colour shown; one global palette if there are 256 or fewer (255 when some
       pixel is ever transparent: the transparent index needs a slot of its own) */
    ch_clear(&o->gmap);
    o->global = 1;
    {
        int anyClear = 0;
        for (i = 0; i < src->nFrames && o->global; ++i)
        {
            step(&s);
            for (k = 0; k < (int) (n / 4); ++k)
            {
                if (!s.canvas[4 * k + 3])
                    anyClear = 1;
                else if (ch_add(&o->gmap, RGB(s.canvas + 4 * k), 256) < 0)
                {
                    o->global = 0;
                    break;
                }
            }
        }
        if (o->global && anyClear && o->gmap.n >= 256)
            o->global = 0;
        o->reserve = anyClear;
    }
    if (o->global)
    {
        ch_sort(&o->gmap);
        for (k = 0; k < 1024; ++k)
            if (o->gmap.key[k])
            {
                uint32_t c = o->gmap.key[k] & 0xFFFFFF;
                int v = o->gmap.val[k];
                o->gpal[3 * v] = (uint8_t) (c >> 16);
                o->gpal[3 * v + 1] = (uint8_t) (c >> 8);
                o->gpal[3 * v + 2] = (uint8_t) c;
            }
        o->gcount = o->gmap.n ? o->gmap.n : 1;
        o->gslots = 1 << bits_of(o->gcount + (o->reserve ? 1 : 0));
        g->ncolors = o->gslots;
        memcpy(g->palette, o->gpal, 768);
    }
    step_free(&s);

    /* pass 2: the frames */
    g->width = src->width;
    g->height = src->height;
    g->version89 = 1;
    g->loopCount = src->loopCount;
    g->frames = calloc((size_t) src->nFrames, sizeof(GIFFrame));
    if (!g->frames || !step_init(&s, src))
    {
        snprintf(err, errlen, "out of memory");
        ok = 0;
    }
    for (i = 0; ok && i < src->nFrames; ++i)
    {
        const uint8_t *T;
        int needClear = 0;
        step(&s);
        T = s.canvas;
        if (g->nFrames == 0)
            memset(P, 0, n);
        else
        {
            GIFFrame *last = &g->frames[g->nFrames - 1];
            memcpy(P, Tprev, n);                  /* last frame left on screen (disposal 1) */
            for (k = 0; k < (int) (n / 4) && !needClear; ++k)
                needClear = T[4 * k + 3] == 0 && P[4 * k + 3] != 0;
            if (needClear)
            {
                /* first try: clear the last frame's rectangle afterwards */
                int x, y, still = 0;
                for (y = last->top; y < last->top + last->height; ++y)
                    for (x = last->left; x < last->left + last->width; ++x)
                        memset(P + ((size_t) y * o->width + x) * 4, 0, 4);
                for (k = 0; k < (int) (n / 4) && !still; ++k)
                    still = T[4 * k + 3] == 0 && P[4 * k + 3] != 0;
                if (still)
                {
                    /* else: redo the last frame over the whole screen, then clear all of it */
                    GIFFrame redo;
                    if (!make_frame(o, Tprev, Pprev, 1, &redo))
                    {
                        ok = 0;
                        break;
                    }
                    redo.delay = last->delay;
                    free(last->pixels);
                    *last = redo;
                    memset(P, 0, n);
                }
                last->disposal = 2;
            }
            else
            {
                int changed = 0;
                for (k = 0; k < (int) n && !changed; k += 4)
                    changed = !same(T + k, P + k);
                if (!changed)                     /* identical to the last frame: merge */
                {
                    last->delay += src->frames[i].delay;
                    continue;
                }
            }
        }
        {
            GIFFrame *f = &g->frames[g->nFrames];
            if (!make_frame(o, T, P, 0, f))
            {
                ok = 0;
                break;
            }
            f->delay = src->frames[i].delay;
            f->disposal = 1;
            g->nFrames++;
            memcpy(Pprev, P, n);
            memcpy(Tprev, T, n);
        }
    }
    step_free(&s);
    free(P);
    free(Tprev);
    free(Pprev);
    free(o);
    if (!ok)
    {
        if (!err[0])
            snprintf(err, errlen, "a frame needs more than 255 colours plus transparency");
        gif_free(g);
        return NULL;
    }
    return g;
}

/* ---------- checking: do two GIFs look the same? ---------- */

typedef struct
{
    Stepper s;
    uint8_t *state;            /* the picture being shown */
    int      have;             /* s.canvas holds a stepped-ahead frame not yet used */
} Player;

/* The next distinct picture and how long it stays up. 0 when the file is finished. */
static int next_look(Player *p, size_t n, long *delay)
{
    const GIFFile *g = p->s.g;
    if (!p->have)
    {
        if (p->s.next >= g->nFrames)
            return 0;
        step(&p->s);
    }
    memcpy(p->state, p->s.canvas, n);
    *delay = g->frames[p->s.next - 1].delay;
    p->have = 0;
    while (p->s.next < g->nFrames)
    {
        size_t k;
        int diff = 0;
        step(&p->s);
        for (k = 0; k < n && !diff; k += 4)
            diff = !same(p->state + k, p->s.canvas + k);
        if (diff)
        {
            p->have = 1;
            break;
        }
        *delay += g->frames[p->s.next - 1].delay;
    }
    return 1;
}

int gif_same_look(const GIFFile *a, const GIFFile *b, char *why, size_t whylen)
{
    Player pa, pb;
    size_t n = (size_t) a->width * a->height * 4, k;
    int look = 0, ra, rb, result = 1;
    long da, db;

    why[0] = 0;
    if (a->width != b->width || a->height != b->height)
    {
        snprintf(why, whylen, "screen size differs");
        return 0;
    }
    memset(&pa, 0, sizeof pa);
    memset(&pb, 0, sizeof pb);
    pa.state = malloc(n ? n : 1);
    pb.state = malloc(n ? n : 1);
    if (!pa.state || !pb.state || !step_init(&pa.s, a) || !step_init(&pb.s, b))
    {
        snprintf(why, whylen, "out of memory");
        return 0;
    }
    for (;;)
    {
        ra = next_look(&pa, n, &da);
        rb = next_look(&pb, n, &db);
        if (!ra || !rb)
        {
            if (ra != rb)
            {
                snprintf(why, whylen, "different number of pictures (after %d)", look);
                result = 0;
            }
            break;
        }
        ++look;
        for (k = 0; k < n; k += 4)
            if (!same(pa.state + k, pb.state + k))
            {
                snprintf(why, whylen, "picture %d differs at pixel %zu", look, k / 4);
                result = 0;
                break;
            }
        if (!result)
            break;
        if (da != db)
        {
            snprintf(why, whylen, "picture %d shows for %ld vs %ld", look, da, db);
            result = 0;
            break;
        }
    }
    step_free(&pa.s);
    step_free(&pb.s);
    free(pa.state);
    free(pb.state);
    if (result)
        snprintf(why, whylen, "%d pictures identical", look);
    return result;
}

/* ---------- quantizing: at most k colours over the whole animation ---------- */

typedef struct
{
    uint32_t *key;             /* colour | 0x1000000, 0 = empty */
    int      *val;
    uint32_t  cap;
    int       n;
} BigHash;

static int bh_find(BigHash *h, uint32_t rgb, int add)
{
    uint32_t k = rgb | 0x1000000u, i = (rgb * 2654435761u) & (h->cap - 1);
    while (h->key[i])
    {
        if (h->key[i] == k)
            return h->val[i];
        i = (i + 1) & (h->cap - 1);
    }
    if (!add)
        return -1;
    if ((uint32_t) (h->n + 1) * 2 > h->cap)      /* grow, then insert */
    {
        BigHash g;
        uint32_t j;
        g.cap = h->cap * 2;
        g.n = 0;
        g.key = calloc(g.cap, sizeof(uint32_t));
        g.val = malloc(g.cap * sizeof(int));
        if (!g.key || !g.val)
        {
            free(g.key);
            free(g.val);
            return -2;
        }
        for (j = 0; j < h->cap; ++j)
            if (h->key[j])
            {
                uint32_t c = h->key[j] & 0xFFFFFF, q = (c * 2654435761u) & (g.cap - 1);
                while (g.key[q])
                    q = (q + 1) & (g.cap - 1);
                g.key[q] = h->key[j];
                g.val[q] = h->val[j];
                g.n++;
            }
        free(h->key);
        free(h->val);
        *h = g;
        return bh_find(h, rgb, 1);
    }
    h->key[i] = k;
    h->val[i] = h->n;
    return h->n++;
}

int gif_quantize(GIFFile *g, int k, char *err, size_t errlen)
{
    BigHash h;
    Stepper s;
    uint32_t *rgb = NULL, *cnt = NULL, pal[256];
    int *map = NULL, i, m = -1, cap = 4096, anyClear = 0;
    size_t n = (size_t) g->width * g->height * 4, q;

    err[0] = 0;
    if (k < 2 || k > 256 || g->nFrames < 1)
    {
        snprintf(err, errlen, "colours must be 2 to 256");
        return -1;
    }
    h.cap = 4096;
    h.n = 0;
    h.key = calloc(h.cap, sizeof(uint32_t));
    h.val = malloc(h.cap * sizeof(int));
    rgb = malloc(cap * sizeof(uint32_t));
    cnt = malloc(cap * sizeof(uint32_t));
    if (!h.key || !h.val || !rgb || !cnt || !step_init(&s, g))
    {
        snprintf(err, errlen, "out of memory");
        goto done;
    }
    /* the super palette: every colour shown, with how many pixels show it (frame after frame) */
    for (i = 0; i < g->nFrames; ++i)
    {
        step(&s);
        for (q = 0; q < n; q += 4)
            if (!s.canvas[q + 3])
                anyClear = 1;
            else
            {
                uint32_t c = RGB(s.canvas + q);
                int before = h.n, v = bh_find(&h, c, 1);
                if (v < 0)
                {
                    snprintf(err, errlen, "out of memory");
                    step_free(&s);
                    goto done;
                }
                if (h.n > before)
                {
                    if (h.n > cap)
                    {
                        cap *= 2;
                        rgb = realloc(rgb, cap * sizeof(uint32_t));
                        cnt = realloc(cnt, cap * sizeof(uint32_t));
                        if (!rgb || !cnt)
                        {
                            snprintf(err, errlen, "out of memory");
                            step_free(&s);
                            goto done;
                        }
                    }
                    rgb[v] = c;
                    cnt[v] = 0;
                }
                cnt[v]++;
            }
    }
    step_free(&s);
    map = malloc((h.n ? h.n : 1) * sizeof(int));
    if (!map)
    {
        snprintf(err, errlen, "out of memory");
        goto done;
    }
    m = quant_build(rgb, cnt, h.n, anyClear ? k - 1 : k, pal, map);   /* the transparent index takes a slot */
    if (m < 0)
    {
        snprintf(err, errlen, "out of memory");
        goto done;
    }
    /* every palette entry becomes the colour its colour maps to */
    {
        int f, e;
        for (f = -1; f < g->nFrames; ++f)
        {
            uint8_t *p = f < 0 ? g->palette : g->frames[f].palette;
            int nc = f < 0 ? g->ncolors : g->frames[f].ncolors;
            for (e = 0; e < nc; ++e)
            {
                int v = bh_find(&h, ((uint32_t) p[3 * e] << 16) | ((uint32_t) p[3 * e + 1] << 8) | p[3 * e + 2], 0);
                if (v >= 0)
                {
                    uint32_t c = pal[map[v]];
                    p[3 * e] = (uint8_t) (c >> 16);
                    p[3 * e + 1] = (uint8_t) (c >> 8);
                    p[3 * e + 2] = (uint8_t) c;
                }
            }
        }
    }
done:
    free(h.key);
    free(h.val);
    free(rgb);
    free(cnt);
    free(map);
    return m;
}

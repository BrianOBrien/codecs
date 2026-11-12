/*
 * inflate.c - Deflate decoding. See inflate.h.
 */
#include <string.h>
#include "inflate.h"

#define MAXBITS   15     /* longest Huffman code */
#define MAXLCODES 286    /* literal/length codes */
#define MAXDCODES 30     /* distance codes */
#define FIXLCODES 288    /* fixed table has 288 entries */

typedef struct
{
    const uint8_t *in;
    size_t   inlen, incnt;
    uint32_t bitbuf;     /* bits not yet used, least significant first */
    int      bitcnt;
    uint8_t *out;
    size_t   outlen, outcnt;
    int      err;        /* set on corrupt data or running out of input */
    int      full;       /* the output buffer is full: stop quietly */
} state;

typedef struct
{
    short count[MAXBITS + 1];   /* number of codes of each length */
    short symbol[FIXLCODES];    /* symbols in canonical order */
} huffman;

/* Deflate packs bits least significant first (TIFF LZW is the opposite). */
static int bits(state *s, int need)
{
    uint32_t val = s->bitbuf;
    while (s->bitcnt < need)
    {
        if (s->incnt >= s->inlen)
        {
            s->err = 1;
            return 0;
        }
        val |= (uint32_t) s->in[s->incnt++] << s->bitcnt;
        s->bitcnt += 8;
    }
    s->bitbuf = val >> need;
    s->bitcnt -= need;
    return (int) (val & ((1u << need) - 1));
}

static void put(state *s, uint8_t c)
{
    if (s->outcnt < s->outlen)
        s->out[s->outcnt++] = c;
    else
        s->full = 1;
}

/* Block type 0: LEN, NLEN, then LEN raw bytes. */
static void stored(state *s)
{
    unsigned len;
    s->bitbuf = 0;
    s->bitcnt = 0;                       /* skip to a byte boundary */
    if (s->incnt + 4 > s->inlen)
    {
        s->err = 1;
        return;
    }
    len = s->in[s->incnt] | (unsigned) s->in[s->incnt + 1] << 8;
    if ((s->in[s->incnt + 2] | (unsigned) s->in[s->incnt + 3] << 8) != (~len & 0xffff))
    {
        s->err = 1;
        return;
    }
    s->incnt += 4;
    if (s->incnt + len > s->inlen)
    {
        s->err = 1;
        return;
    }
    while (len-- && !s->full)
        put(s, s->in[s->incnt++]);
}

/* Build a canonical Huffman table from code lengths. Returns <0 if over-subscribed. */
static int construct(huffman *h, const short *length, int n)
{
    int symbol, len, left;
    short offs[MAXBITS + 1];

    for (len = 0; len <= MAXBITS; len++)
        h->count[len] = 0;
    for (symbol = 0; symbol < n; symbol++)
        h->count[length[symbol]]++;
    if (h->count[0] == n)
        return 0;                        /* no codes: complete, but decode will fail */
    left = 1;
    for (len = 1; len <= MAXBITS; len++)
    {
        left <<= 1;
        left -= h->count[len];
        if (left < 0)
            return left;
    }
    offs[1] = 0;
    for (len = 1; len < MAXBITS; len++)
        offs[len + 1] = offs[len] + h->count[len];
    for (symbol = 0; symbol < n; symbol++)
        if (length[symbol] != 0)
            h->symbol[offs[length[symbol]]++] = (short) symbol;
    return left;                         /* 0 complete, >0 incomplete */
}

/* Decode one symbol, one bit at a time. */
static int decode(state *s, const huffman *h)
{
    int len, code = 0, first = 0, index = 0, count;
    for (len = 1; len <= MAXBITS; len++)
    {
        code |= bits(s, 1);
        if (s->err)
            return -1;
        count = h->count[len];
        if (code - count < first)
            return h->symbol[index + (code - first)];
        index += count;
        first += count;
        first <<= 1;
        code <<= 1;
    }
    s->err = 1;                          /* ran out of codes */
    return -1;
}

/* Literals and length/distance pairs until the end-of-block code (256). */
static void codes(state *s, const huffman *lencode, const huffman *distcode)
{
    static const short lbase[29] = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                     35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
    static const short lext[29] = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
    static const short dbase[30] = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                     257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                                     8193, 12289, 16385, 24577 };
    static const short dext[30] = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                    7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
    int symbol, len;
    unsigned dist;

    for (;;)
    {
        symbol = decode(s, lencode);
        if (s->err || s->full)
            return;
        if (symbol < 256)
        {
            put(s, (uint8_t) symbol);
        }
        else if (symbol == 256)
        {
            return;                      /* end of block */
        }
        else
        {
            symbol -= 257;
            if (symbol >= 29)
            {
                s->err = 1;
                return;
            }
            len = lbase[symbol] + bits(s, lext[symbol]);
            symbol = decode(s, distcode);
            if (s->err || symbol < 0 || symbol >= 30)
            {
                s->err = 1;
                return;
            }
            dist = (unsigned) (dbase[symbol] + bits(s, dext[symbol]));
            if (s->err || dist > s->outcnt)
            {
                s->err = 1;              /* reaches back before the start */
                return;
            }
            while (len-- && !s->full)    /* byte by byte: the copy may overlap itself */
                put(s, s->out[s->outcnt - dist]);
        }
    }
}

/* Block type 1: the fixed tables from RFC 1951. */
static void fixed(state *s)
{
    static huffman lencode, distcode;
    static int built = 0;
    if (!built)
    {
        short lengths[FIXLCODES];
        int symbol;
        for (symbol = 0; symbol < 144; symbol++) lengths[symbol] = 8;
        for (; symbol < 256; symbol++)           lengths[symbol] = 9;
        for (; symbol < 280; symbol++)           lengths[symbol] = 7;
        for (; symbol < FIXLCODES; symbol++)     lengths[symbol] = 8;
        construct(&lencode, lengths, FIXLCODES);
        for (symbol = 0; symbol < MAXDCODES; symbol++) lengths[symbol] = 5;
        construct(&distcode, lengths, MAXDCODES);
        built = 1;
    }
    codes(s, &lencode, &distcode);
}

/* Block type 2: the tables are sent first, themselves Huffman-coded. */
static void dynamic(state *s)
{
    static const short order[19] = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
    short lengths[MAXLCODES + MAXDCODES];
    huffman lencode, distcode;
    int nlen, ndist, ncode, index, err;

    nlen = bits(s, 5) + 257;
    ndist = bits(s, 5) + 1;
    ncode = bits(s, 4) + 4;
    if (s->err || nlen > MAXLCODES || ndist > MAXDCODES)
    {
        s->err = 1;
        return;
    }
    for (index = 0; index < ncode; index++)
        lengths[order[index]] = (short) bits(s, 3);
    for (; index < 19; index++)
        lengths[order[index]] = 0;
    if (s->err || construct(&lencode, lengths, 19) != 0)
    {
        s->err = 1;                      /* code-length code must be complete */
        return;
    }

    index = 0;
    while (index < nlen + ndist)
    {
        int symbol = decode(s, &lencode), len = 0, repeat;
        if (s->err)
            return;
        if (symbol < 16)
        {
            lengths[index++] = (short) symbol;
            continue;
        }
        if (symbol == 16)                /* repeat the previous length 3-6 times */
        {
            if (index == 0)
            {
                s->err = 1;
                return;
            }
            len = lengths[index - 1];
            repeat = 3 + bits(s, 2);
        }
        else if (symbol == 17)           /* 3-10 zeros */
            repeat = 3 + bits(s, 3);
        else                             /* 11-138 zeros */
            repeat = 11 + bits(s, 7);
        if (s->err || index + repeat > nlen + ndist)
        {
            s->err = 1;
            return;
        }
        while (repeat--)
            lengths[index++] = (short) len;
    }
    if (lengths[256] == 0)
    {
        s->err = 1;                      /* no end-of-block code */
        return;
    }
    err = construct(&lencode, lengths, nlen);
    if (err < 0 || (err > 0 && nlen - lencode.count[0] != 1))
    {
        s->err = 1;
        return;
    }
    err = construct(&distcode, lengths + nlen, ndist);
    if (err < 0 || (err > 0 && ndist - distcode.count[0] != 1))
    {
        s->err = 1;
        return;
    }
    codes(s, &lencode, &distcode);
}

long raw_inflate(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen)
{
    state s;
    int last, type;
    memset(&s, 0, sizeof s);
    s.in = in;
    s.inlen = inlen;
    s.out = out;
    s.outlen = outlen;
    do
    {
        last = bits(&s, 1);
        type = bits(&s, 2);
        if (s.err)
            break;
        if (type == 0)
            stored(&s);
        else if (type == 1)
            fixed(&s);
        else if (type == 2)
            dynamic(&s);
        else
            s.err = 1;
    } while (!last && !s.err && !s.full);
    if (s.err && !s.full)
        return -1;
    return (long) s.outcnt;
}

long zlib_inflate(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen)
{
    if (inlen < 2 || (in[0] & 0x0f) != 8 || ((in[0] << 8) | in[1]) % 31 != 0)
        return -1;                       /* not a zlib header for deflate */
    if (in[1] & 0x20)
        return -1;                       /* preset dictionary: not used by TIFF */
    return raw_inflate(in + 2, inlen - 2, out, outlen);
}

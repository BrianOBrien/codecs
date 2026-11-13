/*
 * lzw.c - TIFF LZW decoding. See lzw.h for where it comes from and what changed.
 *
 *  Read OLD_CODE, output it
 *  While there are codes:
 *     Read NEW_CODE
 *     if NEW_CODE is in the table:   STRING = translation of NEW_CODE
 *     else (the KwKwK case):         STRING = translation of OLD_CODE + CHARACTER
 *     output STRING
 *     CHARACTER = first character of STRING
 *     add OLD_CODE + CHARACTER to the table
 *     OLD_CODE = NEW_CODE
 */
#include <stdlib.h>
#include "lzw.h"

#define LZW_CLEAR   256
#define LZW_EOI     257
#define LZW_FIRST   258   /* first free table entry */
#define LZW_MAXBITS 12
#define LZW_TABLE   4096

typedef struct
{
    int16_t prefix;   /* code of the string without its last character, -1 for a root */
    uint8_t c;        /* last character of the string */
} code;

typedef struct
{
    const uint8_t *buffer;
    size_t         bytesInBuffer;
    uint32_t       accume;        /* bit accumulator */
    int            bitsInAccume;
} bsread;

/* Read nbits, most significant bit first (the GIF version took the low bits first). */
static int bs_read(bsread *bs, int nbits, int *codeOut)
{
    while (bs->bitsInAccume < nbits)
    {
        if (bs->bytesInBuffer == 0)
            return 0;                       /* out of data */
        bs->accume = (bs->accume << 8) | *bs->buffer++;
        bs->bytesInBuffer--;
        bs->bitsInAccume += 8;
    }
    *codeOut = (int) ((bs->accume >> (bs->bitsInAccume - nbits)) & ((1u << nbits) - 1));
    bs->bitsInAccume -= nbits;
    return 1;
}

long lzw_tiff_decode(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen)
{
    static code    table[LZW_TABLE];
    static uint8_t stack[LZW_TABLE];
    bsread bs = { in, inlen, 0, 0 };
    size_t nout = 0;
    int nEntries = LZW_FIRST, codeSize = 9;
    int old_code = -1, new_code, i;
    uint8_t C = 0;

    for (i = 0; i < 256; ++i)
    {
        table[i].prefix = -1;
        table[i].c = (uint8_t) i;
    }

    while (bs_read(&bs, codeSize, &new_code))
    {
        int stackptr = -1, s;

        if (new_code == LZW_EOI)
            break;
        if (new_code == LZW_CLEAR)
        {
            nEntries = LZW_FIRST;
            codeSize = 9;
            old_code = -1;
            continue;
        }

        if (old_code == -1)                 /* first code after a Clear: a root */
        {
            if (new_code > 255)
                return -1;
            if (nout < outlen)
                out[nout++] = (uint8_t) new_code;
            C = (uint8_t) new_code;
            old_code = new_code;
            continue;
        }

        if (new_code < nEntries)            /* buildString(new_code) */
        {
            s = new_code;
        }
        else if (new_code == nEntries)      /* KwKwK: old string + its own first char */
        {
            stack[++stackptr] = C;
            s = old_code;
        }
        else
        {
            return -1;                      /* forward reference: corrupt */
        }
        while (s != -1)
        {
            if (stackptr >= LZW_TABLE - 1)
                return -1;
            stack[++stackptr] = table[s].c;
            s = table[s].prefix;
        }
        C = stack[stackptr];                /* first character of STRING */

        while (stackptr >= 0)               /* output STRING */
        {
            if (nout < outlen)
                out[nout++] = stack[stackptr];
            stackptr--;
        }

        if (nEntries < LZW_TABLE)           /* add OLD_CODE + CHARACTER */
        {
            table[nEntries].prefix = (int16_t) old_code;
            table[nEntries].c = C;
            nEntries++;
            /* TIFF early change: widen when the NEXT code would need it, one sooner than GIF
               (GIF version: if ((nEntries+1) > (1 << codeSize)) ++codeSize;) */
            if (nEntries >= (1 << codeSize) - 1 && codeSize < LZW_MAXBITS)
                codeSize++;
        }
        old_code = new_code;
    }
    return (long) nout;
}

/* ---------- encoder ---------- */

#define HSIZE 9001          /* hash table size (prime), as libtiff */

typedef struct
{
    uint8_t *out;
    size_t   n, cap;
    uint32_t accume;
    int      bitsInAccume;
} bitstream;

/* Write nbits, most significant bit first (the GIF bitstream::write put the low bits first). */
static int bs_write(bitstream *bs, int code, int nbits)
{
    bs->accume = (bs->accume << nbits) | (uint32_t) code;
    bs->bitsInAccume += nbits;
    while (bs->bitsInAccume >= 8)
    {
        if (bs->n >= bs->cap)
        {
            uint8_t *p = realloc(bs->out, bs->cap * 2);
            if (!p)
                return 0;
            bs->out = p;
            bs->cap *= 2;
        }
        bs->out[bs->n++] = (uint8_t) (bs->accume >> (bs->bitsInAccume - 8));
        bs->bitsInAccume -= 8;
    }
    return 1;
}

uint8_t *lzw_tiff_encode(const uint8_t *in, size_t inlen, size_t *outlen)
{
    static int32_t htab[HSIZE];     /* key: (c << 12) | prefix, -1 = empty */
    static int16_t codetab[HSIZE];  /* the code for that key */
    bitstream bs;
    int nbits = 9, maxcode = 511, free_ent = LZW_FIRST, ent = -1, i;
    size_t k;

    bs.cap = inlen / 2 + 64;
    bs.out = malloc(bs.cap);
    bs.n = 0;
    bs.accume = 0;
    bs.bitsInAccume = 0;
    if (!bs.out)
        return NULL;
    for (i = 0; i < HSIZE; ++i)
        htab[i] = -1;
    if (!bs_write(&bs, LZW_CLEAR, nbits))
        goto fail;

    for (k = 0; k < inlen; ++k)
    {
        int c = in[k], h;
        int32_t key;
        if (ent == -1)
        {
            ent = c;                                /* P = c */
            continue;
        }
        key = (int32_t) c << 12 | ent;
        h = (int) (((uint32_t) c << 8 ^ (uint32_t) ent) % HSIZE);
        while (htab[h] != -1 && htab[h] != key)    /* is Pc in the table? */
            h = (h + 1) % HSIZE;
        if (htab[h] == key)
        {
            ent = codetab[h];                       /* yes: P = Pc */
            continue;
        }
        if (!bs_write(&bs, ent, nbits))             /* no: output the code for P */
            goto fail;
        ent = c;                                    /* P = c */
        htab[h] = key;                              /* add Pc to the string table */
        codetab[h] = (int16_t) free_ent++;
        if (free_ent == LZW_TABLE - 2)              /* full (4094): Clear and start again */
        {
            if (!bs_write(&bs, LZW_CLEAR, nbits))
                goto fail;
            for (i = 0; i < HSIZE; ++i)
                htab[i] = -1;
            nbits = 9;
            maxcode = 511;
            free_ent = LZW_FIRST;
        }
        else if (free_ent > maxcode)                /* early change, matching the decoder */
        {
            nbits++;
            maxcode = (1 << nbits) - 1;
        }
    }
    if (ent != -1)
    {
        if (!bs_write(&bs, ent, nbits))
            goto fail;
        free_ent++;
        if (free_ent == LZW_TABLE - 2)
        {
            if (!bs_write(&bs, LZW_CLEAR, nbits))
                goto fail;
            nbits = 9;
        }
        else if (free_ent > maxcode)
            nbits++;
    }
    if (!bs_write(&bs, LZW_EOI, nbits))
        goto fail;
    if (bs.bitsInAccume > 0)                        /* pad the last byte with zeros */
        if (!bs_write(&bs, 0, 8 - bs.bitsInAccume))
            goto fail;
    *outlen = bs.n;
    return bs.out;
fail:
    free(bs.out);
    return NULL;
}

/* ---------- GIF flavour ----------
 * Decoder: the loop of Brian's lzw_decompress::read (Readgif, 1999); encoder: lzw::write and
 * bitstream::write (Writegif, 1998-99), whose rules are kept: the width grows in put() when the
 * table has passed 2^n entries, and a Clear is sent when it reaches 4096. */

long lzw_gif_decode(const uint8_t *in, size_t inlen, int minCodeSize, uint8_t *out, size_t outlen)
{
    static code    table[LZW_TABLE];
    static uint8_t stack[LZW_TABLE];
    size_t pos = 0, nout = 0;
    uint32_t accume = 0;
    int bitsInAccume = 0, i;
    int clearCode, eofCode, nEntries, codeSize, old_code = -1, new_code;
    uint8_t C = 0;

    if (minCodeSize < 1 || minCodeSize > 8)      /* 1 is not legal GIF, but WinFLI's 1998 writer */
        return -1;                               /* used it for 2-colour images: read it anyway */
    clearCode = 1 << minCodeSize;
    eofCode = clearCode + 1;
    nEntries = clearCode + 2;
    codeSize = minCodeSize + 1;
    for (i = 0; i < clearCode; ++i)
    {
        table[i].prefix = -1;
        table[i].c = (uint8_t) i;
    }

    for (;;)
    {
        int stackptr = -1, s;
        while (bitsInAccume < codeSize)          /* least significant bit first, as bsread::read */
        {
            if (pos >= inlen)
                return (long) nout;              /* ran out: many files end without EOI */
            accume |= (uint32_t) in[pos++] << bitsInAccume;
            bitsInAccume += 8;
        }
        new_code = (int) (accume & ((1u << codeSize) - 1));
        accume >>= codeSize;
        bitsInAccume -= codeSize;

        if (new_code == eofCode)
            break;
        if (new_code == clearCode)
        {
            nEntries = clearCode + 2;
            codeSize = minCodeSize + 1;
            old_code = -1;
            continue;
        }
        if (old_code == -1)
        {
            if (new_code >= clearCode)
                return -1;
            if (nout < outlen)
                out[nout++] = (uint8_t) new_code;
            C = (uint8_t) new_code;
            old_code = new_code;
            if (nEntries >= (1 << codeSize) && codeSize < LZW_MAXBITS)
                codeSize++;                      /* code size 1: the table starts full (as ffmpeg) */
            continue;
        }
        if (new_code < nEntries)
            s = new_code;
        else if (new_code == nEntries)
        {
            stack[++stackptr] = C;
            s = old_code;
        }
        else
            return -1;
        while (s != -1)
        {
            if (stackptr >= LZW_TABLE - 1)
                return -1;
            stack[++stackptr] = table[s].c;
            s = table[s].prefix;
        }
        C = stack[stackptr];
        while (stackptr >= 0)
        {
            if (nout < outlen)
                out[nout++] = stack[stackptr];
            stackptr--;
        }
        if (nEntries < LZW_TABLE)                /* addcode(old_code, C) */
        {
            table[nEntries].prefix = (int16_t) old_code;
            table[nEntries].c = C;
            nEntries++;
        }
        if (nEntries >= (1 << codeSize) && codeSize < LZW_MAXBITS)   /* Brian's (nEntries+1) > 2^n, */
            codeSize++;                          /* checked after every code, not only after an add */
        old_code = new_code;
    }
    return (long) nout;
}

/* LSB-first bit writer: bitstream::write without the sub-blocks */
static int gbs_write(bitstream *bs, int code, int nbits)
{
    bs->accume |= (uint32_t) code << bs->bitsInAccume;
    bs->bitsInAccume += nbits;
    while (bs->bitsInAccume >= 8)
    {
        if (bs->n >= bs->cap)
        {
            uint8_t *p = realloc(bs->out, bs->cap * 2);
            if (!p)
                return 0;
            bs->out = p;
            bs->cap *= 2;
        }
        bs->out[bs->n++] = (uint8_t) bs->accume;
        bs->accume >>= 8;
        bs->bitsInAccume -= 8;
    }
    return 1;
}

uint8_t *lzw_gif_encode(const uint8_t *in, size_t inlen, int minCodeSize, size_t *outlen)
{
    static int32_t htab[HSIZE];
    static int16_t codetab[HSIZE];
    bitstream bs;
    int clearCode = 1 << minCodeSize, eofCode = clearCode + 1;
    int nEntries = clearCode + 2, codeSize = minCodeSize + 1, prefix = -1, i;
    size_t k;

    if (minCodeSize < 2 || minCodeSize > 8)
        return NULL;
    bs.cap = inlen / 2 + 64;
    bs.out = malloc(bs.cap);
    bs.n = 0;
    bs.accume = 0;
    bs.bitsInAccume = 0;
    if (!bs.out)
        return NULL;
    for (i = 0; i < HSIZE; ++i)
        htab[i] = -1;

#define PUT(cd) do { if (nEntries > (1 << codeSize)) ++codeSize; if (!gbs_write(&bs, (cd), codeSize)) goto fail; } while (0)
    if (!gbs_write(&bs, clearCode, codeSize))    /* the constructor's put(clearCode) */
        goto fail;
    for (k = 0; k < inlen; ++k)
    {
        int c = in[k] & (clearCode - 1), h;
        int32_t key;
        if (prefix == -1)                         /* current.prefix == -1: c is a root */
        {
            prefix = c;
            continue;
        }
        key = (int32_t) c << 12 | prefix;
        h = (int) (((uint32_t) c << 8 ^ (uint32_t) prefix) % HSIZE);
        while (htab[h] != -1 && htab[h] != key)
            h = (h + 1) % HSIZE;
        if (htab[h] == key)
        {
            prefix = codetab[h];                  /* in the table: P = Pc */
            continue;
        }
        PUT(prefix);                              /* put(current.prefix) */
        if (nEntries == LZW_TABLE)                /* table full: Clear and start again */
        {
            PUT(clearCode);
            for (i = 0; i < HSIZE; ++i)
                htab[i] = -1;
            nEntries = clearCode + 2;
            codeSize = minCodeSize + 1;
        }
        else
        {
            htab[h] = key;
            codetab[h] = (int16_t) nEntries++;
        }
        prefix = c;
    }
    if (prefix != -1)
        PUT(prefix);                              /* the destructor: flush the current string */
    PUT(eofCode);                                 /* and the end code */
#undef PUT
    if (bs.bitsInAccume > 0)
        if (!gbs_write(&bs, 0, 8 - bs.bitsInAccume))
            goto fail;
    *outlen = bs.n;
    return bs.out;
fail:
    free(bs.out);
    return NULL;
}

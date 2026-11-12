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

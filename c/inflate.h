/*
 * inflate.h - Deflate decoding (TIFF compression 8 and 32946: a zlib stream).
 *
 * Deflate = LZ77 back-references ("copy LENGTH bytes from DISTANCE back", up to 32 KB)
 * + Huffman coding of literals, lengths and distances, with fixed or per-block tables.
 * Written from RFC 1950/1951, structured like Mark Adler's puff.c (zlib's reference
 * inflater): decode one code a bit at a time from canonical code-length counts. Small and
 * easy to port; not the fastest.
 */
#ifndef INFLATE_H
#define INFLATE_H

#include <stddef.h>
#include <stdint.h>

/* Inflate a zlib-wrapped stream (2-byte header, deflate data, Adler-32 not checked).
 * Returns bytes written to out (at most outlen), or -1 on corrupt data. */
long zlib_inflate(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen);

/* Inflate raw deflate data (no zlib header). */
long raw_inflate(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen);

#endif

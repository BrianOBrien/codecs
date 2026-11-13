/*
 * lzw.h - TIFF LZW decoding (compression 5).
 *
 * Adapted from Brian O'Brien's GIF LZW decoder (github.com/BrianOBrien/lzw,
 * decompress/lzw_decompress.cpp, MIT licence). Same string table (prefix + char),
 * same stack-based string building. Changed for TIFF:
 *   - bits are packed most significant bit first (GIF: least significant first);
 *   - no 255-byte sub-blocks, the strip is one plain run of bytes;
 *   - "early change": the code width grows one code sooner than in GIF;
 *   - always 8-bit roots: Clear = 256, EndOfInformation = 257, codes 9..12 bits;
 *   - one call decodes one whole strip or tile.
 */
#ifndef LZW_H
#define LZW_H

#include <stddef.h>
#include <stdint.h>

/* Decode one TIFF LZW strip or tile.
 * Returns the number of bytes written to out (at most outlen), or -1 on corrupt data. */
long lzw_tiff_decode(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen);

/* Encode one strip or tile as TIFF LZW. Returns a malloc'd buffer (caller frees) and its
 * length in *outlen, or NULL if out of memory. Follows the loop of Brian's lzw::write
 * (compress/Lzw.cpp); width and Clear rules as TIFF 6.0 / libtiff: Clear first, early
 * change, Clear when the table reaches 4094, EndOfInformation last. */
uint8_t *lzw_tiff_encode(const uint8_t *in, size_t inlen, size_t *outlen);


/* ---------- GIF flavour (Brian's 1998 Readgif/Writegif LZW) ----------
 * Codes are packed least significant bit first; the width grows when the table reaches 2^n
 * (no early change); roots are 2^minCodeSize, Clear = 2^m, EndOfInformation = 2^m + 1.
 * These work on the code bytes alone: the 255-byte sub-blocks are removed / added by gif.c. */

/* Decode GIF LZW codes. Returns the bytes written to out (at most outlen), or -1 on corrupt data. */
long lzw_gif_decode(const uint8_t *in, size_t inlen, int minCodeSize, uint8_t *out, size_t outlen);

/* Encode pixel indices (each < 2^minCodeSize) as GIF LZW codes. Returns a malloc'd buffer. */
uint8_t *lzw_gif_encode(const uint8_t *in, size_t inlen, int minCodeSize, size_t *outlen);
/* deferClear 0: send a Clear when the table reaches 4096 (Writegif's rule); 1: keep coding with the
   full table and add nothing ("deferred clear", legal GIF: decoders must handle it). */
uint8_t *lzw_gif_encode_mode(const uint8_t *in, size_t inlen, int minCodeSize, int deferClear, size_t *outlen);
/* Both ways, the shorter one. */
uint8_t *lzw_gif_encode_best(const uint8_t *in, size_t inlen, int minCodeSize, size_t *outlen);

#endif

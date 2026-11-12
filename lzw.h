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

#endif

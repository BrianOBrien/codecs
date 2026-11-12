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

#endif

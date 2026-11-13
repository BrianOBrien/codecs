/*
 * quant.h - colour quantizer (weighted k-means in OKLab) and the palette order.
 */
#ifndef QUANT_H
#define QUANT_H

#include <stdint.h>

/* rgb[n] distinct colours (0xRRGGBB) used by cnt[n] pixels each. Fills pal (at most k colours,
   each one of the input colours) and map[n] (the palette entry each input colour becomes).
   Returns the number of palette colours, or -1 when out of memory. */
int quant_build(const uint32_t *rgb, const uint32_t *cnt, int n, int k, uint32_t *pal, int *map);

/* Sort key for writing palettes: greys dark to light, then colours by hue, each dark to light. */
uint64_t pal_sort_key(uint32_t rgb);

#endif

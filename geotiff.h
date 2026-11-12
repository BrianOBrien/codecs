/*
 * geotiff.h - a small GeoTIFF reader in plain C.
 *
 * Reads the first image of a TIFF file: tags, pixels (uncompressed or LZW, with or
 * without the horizontal predictor, strips or tiles) and the GeoTIFF georeferencing
 * (pixel scale + tie point, or the full transformation matrix, plus GeoKeys).
 * No dependencies beyond the C library. Written as the reference for a Xojo port.
 */
#ifndef GEOTIFF_H
#define GEOTIFF_H

#include <stdint.h>
#include <stdio.h>
#include "tiff.h"

typedef struct
{
    uint16_t id;
    uint16_t type;
    uint32_t count;
    uint8_t *data;      /* count values, converted to this machine's byte order */
} GTTag;

typedef struct
{
    uint16_t id;        /* GeoKey id, e.g. GK_ProjectedCSType */
    uint16_t location;  /* 0 = value is in valueOrIndex, else TIF_GEODOUBLEPARAMS / TIF_GEOASCIIPARAMS */
    uint16_t count;
    uint16_t valueOrIndex;
} GTGeoKey;

typedef struct
{
    FILE     *fp;
    int       bigEndian;          /* file is "MM" */
    uint32_t  ifdOffset;
    int       nImages;            /* IFDs in the file (overviews etc. after the first) */
    int       nTags;
    GTTag    *tags;

    /* image description, from the tags */
    uint32_t  width, height;
    uint16_t  bitsPerSample, samplesPerPixel, sampleFormat;
    uint16_t  compression, photometric, planar, predictor;
    int       tiled;
    uint32_t  rowsPerStrip, tileWidth, tileLength;

    /* georeferencing */
    int       hasTransform;       /* raster -> model: X = t[0] + t[1]*col + t[2]*row, Y = t[3] + t[4]*col + t[5]*row */
    double    gt[6];              /* same layout as GDAL's geotransform */
    int       nKeys;
    GTGeoKey *keys;
} GTFile;

/* Open a file and read its first IFD. Returns NULL and fills err (if not NULL) on failure. */
GTFile *gt_open(const char *path, char *err, size_t errlen);
void    gt_close(GTFile *f);

/* Tags */
const GTTag *gt_find(const GTFile *f, uint16_t id);
double       gt_tag_number(const GTTag *t, uint32_t i);   /* any numeric type, as a double */
const char  *gt_tag_name(uint16_t id);
const char  *gt_type_name(uint16_t type);
int          gt_type_size(uint16_t type);

/* Pixels: width*height*samplesPerPixel samples, interleaved, in this machine's byte order.
   Returns a malloc'd buffer (caller frees) or NULL with err filled. */
uint8_t *gt_read_image(GTFile *f, size_t *nbytes, char *err, size_t errlen);

/* GeoKeys */
const GTGeoKey *gt_key(const GTFile *f, uint16_t id);
const char     *gt_key_name(uint16_t id);
int             gt_key_int(const GTFile *f, uint16_t id, int dflt);
int             gt_key_string(const GTFile *f, uint16_t id, char *out, size_t outlen);  /* ASCII keys */
int             gt_key_double(const GTFile *f, uint16_t id, double *out);               /* DOUBLE keys */

/* Raster (column, row: 0,0 = top-left corner of the top-left pixel) to model coordinates. */
int gt_pixel_to_model(const GTFile *f, double col, double row, double *x, double *y);

#endif

/*
 * gtcopy - read a GeoTIFF with our reader and write it again with our writer.
 *
 *   gtcopy [-c none|lzw|packbits] [-p] [-rows N] in.tif out.tif
 *      -c     compression (default lzw)
 *      -p     horizontal predictor
 *      -rows  rows per strip (default about 8 KB per strip)
 *
 * Keeps the pixels, the georeferencing, the coordinate system (EPSG code) and PixelIsPoint.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "geotiff.h"

int main(int argc, char *argv[])
{
    const char *in = NULL, *out = NULL;
    GTWriteOptions o;
    GTFile *f;
    uint8_t *px;
    size_t n;
    char err[200], cit[256];
    int i, model;

    memset(&o, 0, sizeof o);
    o.compression = TIF_COMP_LZW;
    o.predictor = TIF_PRED_NONE;
    for (i = 1; i < argc; ++i)
    {
        if (!strcmp(argv[i], "-c") && i + 1 < argc)
        {
            const char *c = argv[++i];
            o.compression = !strcmp(c, "none") ? TIF_COMP_NONE : !strcmp(c, "packbits") ? TIF_COMP_PACKBITS
                          : !strcmp(c, "lzw") ? TIF_COMP_LZW : 0;
            if (!o.compression)
            {
                fprintf(stderr, "gtcopy: unknown compression %s\n", c);
                return 2;
            }
        }
        else if (!strcmp(argv[i], "-p"))
            o.predictor = TIF_PRED_HORIZONTAL;
        else if (!strcmp(argv[i], "-rows") && i + 1 < argc)
            o.rowsPerStrip = (uint32_t) atol(argv[++i]);
        else if (!in)
            in = argv[i];
        else
            out = argv[i];
    }
    if (!in || !out)
    {
        fprintf(stderr, "usage: gtcopy [-c none|lzw|packbits] [-p] [-rows N] in.tif out.tif\n");
        return 2;
    }

    f = gt_open(in, err, sizeof err);
    if (!f)
    {
        fprintf(stderr, "gtcopy: %s: %s\n", in, err);
        return 1;
    }
    px = gt_read_image(f, &n, err, sizeof err);
    if (!px)
    {
        fprintf(stderr, "gtcopy: %s: %s\n", in, err);
        gt_close(f);
        return 1;
    }

    o.hasTransform = f->hasTransform;
    memcpy(o.gt, f->gt, sizeof o.gt);
    model = gt_key_int(f, GK_GTModelType, 0);
    o.geographic = model == 2;
    o.epsg = o.geographic ? gt_key_int(f, GK_GeographicType, 0) : gt_key_int(f, GK_ProjectedCSType, 0);
    o.pixelIsPoint = gt_key_int(f, GK_GTRasterType, 1) == 2;
    o.sampleFormat = f->sampleFormat;
    if (gt_key_string(f, GK_GTCitation, cit, sizeof cit))
        o.citation = cit;
    o.software = "geotiff gtcopy";

    if (!gt_write(out, px, f->width, f->height, f->samplesPerPixel, f->bitsPerSample, &o, err, sizeof err))
    {
        fprintf(stderr, "gtcopy: %s: %s\n", out, err);
        free(px);
        gt_close(f);
        return 1;
    }
    free(px);
    gt_close(f);
    return 0;
}

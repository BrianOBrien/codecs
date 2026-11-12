/*
 * gtinfo - print what is inside a (Geo)TIFF, like a small gdalinfo.
 *
 *   gtinfo file.tif              header, tags, GeoKeys, corner coordinates
 *   gtinfo -raw out.raw file.tif also decode the pixels and write them raw
 *                                (interleaved, this machine's byte order)
 *   gtinfo -corners file.tif     just the four corners and the centre, one per line
 *   gtinfo -geotransform file.tif the 6 numbers of the raster-to-model transform (GDAL order)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "geotiff.h"

static void print_value(const GTTag *t)
{
    uint32_t i, n = t->count;
    if (t->type == TIF_ASCII)
    {
        printf("\"%.*s\"", (int) (n && t->data[n - 1] == 0 ? n - 1 : n), (const char *) t->data);
        return;
    }
    for (i = 0; i < n && i < 8; ++i)
        printf("%s%.10g", i ? ", " : "", gt_tag_number(t, i));
    if (n > 8)
        printf(", ... (%u values)", n);
}

static void corner(const GTFile *f, const char *name, double col, double row)
{
    double x, y;
    if (gt_pixel_to_model(f, col, row, &x, &y))
        printf("%-12s (%14.6f, %14.6f)\n", name, x, y);
}

int main(int argc, char *argv[])
{
    const char *path = NULL, *rawOut = NULL;
    int cornersOnly = 0, gtOnly = 0, i;
    char err[200], s[256];
    double d;
    GTFile *f;

    for (i = 1; i < argc; ++i)
    {
        if (!strcmp(argv[i], "-raw") && i + 1 < argc)
            rawOut = argv[++i];
        else if (!strcmp(argv[i], "-corners"))
            cornersOnly = 1;
        else if (!strcmp(argv[i], "-geotransform"))
            gtOnly = 1;
        else
            path = argv[i];
    }
    if (!path)
    {
        fprintf(stderr, "usage: gtinfo [-corners | -geotransform] [-raw out.raw] file.tif\n");
        return 2;
    }

    f = gt_open(path, err, sizeof err);
    if (!f)
    {
        fprintf(stderr, "gtinfo: %s: %s\n", path, err);
        return 1;
    }

    if (gtOnly)
    {
        if (f->hasTransform)
            printf("%.17g %.17g %.17g %.17g %.17g %.17g\n", f->gt[0], f->gt[1], f->gt[2], f->gt[3], f->gt[4], f->gt[5]);
        gt_close(f);
        return f->hasTransform ? 0 : 1;
    }
    if (cornersOnly)
    {
        corner(f, "UpperLeft", 0, 0);
        corner(f, "LowerLeft", 0, f->height);
        corner(f, "UpperRight", f->width, 0);
        corner(f, "LowerRight", f->width, f->height);
        corner(f, "Center", f->width / 2.0, f->height / 2.0);
        gt_close(f);
        return 0;
    }

    printf("File: %s\n", path);
    printf("Byte order: %s, first IFD at %u, %d image(s) in the file\n",
           f->bigEndian ? "MM (big-endian)" : "II (little-endian)", f->ifdOffset, f->nImages);
    printf("Size: %u x %u, %u sample(s) of %u bits, %s, compression %u, predictor %u\n",
           f->width, f->height, f->samplesPerPixel, f->bitsPerSample,
           f->tiled ? "tiled" : "stripped", f->compression, f->predictor);

    printf("\nTags (%d):\n", f->nTags);
    for (i = 0; i < f->nTags; ++i)
    {
        const GTTag *t = &f->tags[i];
        printf("  %5u %-26s %-9s x%-5u ", t->id, gt_tag_name(t->id), gt_type_name(t->type), t->count);
        print_value(t);
        printf("\n");
    }

    if (f->nKeys)
    {
        printf("\nGeoKeys (%d):\n", f->nKeys);
        for (i = 0; i < f->nKeys; ++i)
        {
            const GTGeoKey *k = &f->keys[i];
            printf("  %5u %-20s ", k->id, gt_key_name(k->id));
            if (k->location == 0)
                printf("%u\n", k->valueOrIndex);
            else if (k->location == TIF_GEOASCIIPARAMS && gt_key_string(f, k->id, s, sizeof s))
                printf("\"%s\"\n", s);
            else if (k->location == TIF_GEODOUBLEPARAMS && gt_key_double(f, k->id, &d))
                printf("%.10g\n", d);
            else
                printf("(in tag %u, index %u, count %u)\n", k->location, k->valueOrIndex, k->count);
        }
    }

    if (f->hasTransform)
    {
        printf("\nOrigin = (%.15g, %.15g)\n", f->gt[0], f->gt[3]);
        printf("Pixel Size = (%.15g, %.15g)\n", f->gt[1], f->gt[5]);
        printf("Corner Coordinates:\n");
        corner(f, "Upper Left", 0, 0);
        corner(f, "Lower Left", 0, f->height);
        corner(f, "Upper Right", f->width, 0);
        corner(f, "Lower Right", f->width, f->height);
        corner(f, "Center", f->width / 2.0, f->height / 2.0);
    }
    else
    {
        printf("\nNo georeferencing (no ModelTransformation, or ModelTiepoint + ModelPixelScale).\n");
    }

    if (rawOut)
    {
        size_t n;
        uint8_t *img = gt_read_image(f, &n, err, sizeof err);
        FILE *o;
        if (!img)
        {
            fprintf(stderr, "gtinfo: cannot decode pixels: %s\n", err);
            gt_close(f);
            return 1;
        }
        o = fopen(rawOut, "wb");
        if (!o || fwrite(img, 1, n, o) != n)
        {
            fprintf(stderr, "gtinfo: cannot write %s\n", rawOut);
            free(img);
            gt_close(f);
            return 1;
        }
        fclose(o);
        printf("\nPixels: %zu bytes decoded to %s\n", n, rawOut);
        free(img);
    }
    gt_close(f);
    return 0;
}

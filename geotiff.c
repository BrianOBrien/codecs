/*
 * geotiff.c - a small GeoTIFF reader in plain C. See geotiff.h.
 *
 * The IFD walk follows Brian O'Brien's rast2tif.c (2000): header, then the Image File
 * Directory, then each tag. Unlike that version, every field is read one value at a
 * time in the file's byte order, values of 4 bytes or less are taken from the tag
 * itself (TIFF stores them in the offset field), and RATIONAL is 8 bytes.
 */
#include <stdlib.h>
#include <string.h>
#include "geotiff.h"
#include "lzw.h"

static void seterr(char *err, size_t errlen, const char *msg)
{
    if (err && errlen)
    {
        strncpy(err, msg, errlen - 1);
        err[errlen - 1] = 0;
    }
}

/* ---------- byte order ---------- */

static uint16_t get16(const uint8_t *p, int big)
{
    return big ? (uint16_t) (p[0] << 8 | p[1]) : (uint16_t) (p[1] << 8 | p[0]);
}

static uint32_t get32(const uint8_t *p, int big)
{
    return big ? ((uint32_t) p[0] << 24 | (uint32_t) p[1] << 16 | (uint32_t) p[2] << 8 | p[3])
               : ((uint32_t) p[3] << 24 | (uint32_t) p[2] << 16 | (uint32_t) p[1] << 8 | p[0]);
}

static int hostIsBig(void)
{
    uint16_t x = 1;
    return *(uint8_t *) &x == 0;
}

/* Reverse the bytes of n values of size sz (2, 4 or 8) in place. */
static void swab_values(uint8_t *p, size_t n, int sz)
{
    size_t i;
    int a, b;
    for (i = 0; i < n; ++i, p += sz)
        for (a = 0, b = sz - 1; a < b; ++a, --b)
        {
            uint8_t t = p[a];
            p[a] = p[b];
            p[b] = t;
        }
}

static int read_at(FILE *fp, uint32_t offset, void *buf, size_t n)
{
    if (fseek(fp, (long) offset, SEEK_SET) != 0)
        return 0;
    return fread(buf, 1, n, fp) == n;
}

/* ---------- names ---------- */

int gt_type_size(uint16_t type)
{
    switch (type)
    {
    case TIF_BYTE: case TIF_ASCII: case TIF_SBYTE: case TIF_UNDEFINE: return 1;
    case TIF_SHORT: case TIF_SSHORT:                                  return 2;
    case TIF_LONG: case TIF_SLONG: case TIF_FLOAT:                    return 4;
    case TIF_RATIONAL: case TIF_SRATIONAL: case TIF_DOUBLE:           return 8;
    default:                                                          return 0;
    }
}

const char *gt_type_name(uint16_t type)
{
    static const char *names[] = { "?", "Byte", "Ascii", "Short", "Long", "Rational", "SByte",
                                   "Undefined", "SShort", "SLong", "SRational", "Float", "Double" };
    return type <= 12 ? names[type] : "?";
}

const char *gt_tag_name(uint16_t id)
{
    switch (id)
    {
    case TIF_NEWSUBFILE:               return "NewSubfileType";
    case TIF_IMAGEWIDTH:               return "ImageWidth";
    case TIF_IMAGELENGTH:              return "ImageLength";
    case TIF_BITSPERSAMPLE:            return "BitsPerSample";
    case TIF_COMPRESSION:              return "Compression";
    case TIF_PHOTOMETRICINTERPRETAION: return "PhotometricInterpretation";
    case TIF_IMAGEDESCRIPTION:         return "ImageDescription";
    case TIF_STRIPOFFSETS:             return "StripOffsets";
    case TIF_ORIENTATION:              return "Orientation";
    case TIF_SAMPLESPERPIXEL:          return "SamplesPerPixel";
    case TIF_ROWSPERSTRIP:             return "RowsPerStrip";
    case TIF_STRIPBYTECOUNTS:          return "StripByteCounts";
    case TIF_XRESOLUTION:              return "XResolution";
    case TIF_YRESOLUTION:              return "YResolution";
    case TIF_PLANARCONFIGURATION:      return "PlanarConfiguration";
    case TIF_RESOLUTIONUNIT:           return "ResolutionUnit";
    case TIF_SOFTWARE:                 return "Software";
    case TIF_DATETIME:                 return "DateTime";
    case TIF_ARTIST:                   return "Artist";
    case TIF_HOSTCOMPUTER:             return "HostComputer";
    case TIF_PREDICTOR:                return "Predictor";
    case TIF_COLORMAP:                 return "ColorMap";
    case TIF_TILEWIDTH:                return "TileWidth";
    case TIF_TILELENGTH:               return "TileLength";
    case TIF_TILEOFFSETS:              return "TileOffsets";
    case TIF_TILEBYTECOUNTS:           return "TileByteCounts";
    case TIF_EXTRASAMPLES:             return "ExtraSamples";
    case TIF_SAMPLEFORMAT:             return "SampleFormat";
    case TIF_MODELPIXELSCALE:          return "ModelPixelScale";
    case TIF_MODELTIEPOINT:            return "ModelTiepoint";
    case TIF_MODELTRANSFORMATION:      return "ModelTransformation";
    case TIF_GEOKEYDIRECTORY:          return "GeoKeyDirectory";
    case TIF_GEODOUBLEPARAMS:          return "GeoDoubleParams";
    case TIF_GEOASCIIPARAMS:           return "GeoAsciiParams";
    case TIF_GDAL_METADATA:            return "GDAL_Metadata";
    case TIF_GDAL_NODATA:              return "GDAL_NoData";
    default:                           return "Unknown";
    }
}

const char *gt_key_name(uint16_t id)
{
    switch (id)
    {
    case GK_GTModelType:       return "GTModelType";
    case GK_GTRasterType:      return "GTRasterType";
    case GK_GTCitation:        return "GTCitation";
    case GK_GeographicType:    return "GeographicType";
    case GK_GeogCitation:      return "GeogCitation";
    case GK_GeogGeodeticDatum: return "GeogGeodeticDatum";
    case GK_GeogAngularUnits:  return "GeogAngularUnits";
    case GK_GeogEllipsoid:     return "GeogEllipsoid";
    case GK_GeogSemiMajorAxis: return "GeogSemiMajorAxis";
    case GK_GeogInvFlattening: return "GeogInvFlattening";
    case GK_ProjectedCSType:   return "ProjectedCSType";
    case GK_PCSCitation:       return "PCSCitation";
    case GK_Projection:        return "Projection";
    case GK_ProjCoordTrans:    return "ProjCoordTrans";
    case GK_ProjLinearUnits:   return "ProjLinearUnits";
    case GK_VerticalCSType:    return "VerticalCSType";
    case GK_VerticalUnits:     return "VerticalUnits";
    default:                   return "Unknown";
    }
}

/* ---------- tags ---------- */

const GTTag *gt_find(const GTFile *f, uint16_t id)
{
    int i;
    for (i = 0; i < f->nTags; ++i)
        if (f->tags[i].id == id)
            return &f->tags[i];
    return NULL;
}

double gt_tag_number(const GTTag *t, uint32_t i)
{
    const uint8_t *p;
    if (!t || i >= t->count)
        return 0;
    p = t->data + (size_t) i * gt_type_size(t->type);
    switch (t->type)
    {
    case TIF_BYTE: case TIF_UNDEFINE: return *p;
    case TIF_SBYTE:                   return *(const int8_t *) p;
    case TIF_SHORT:                   return *(const uint16_t *) p;
    case TIF_SSHORT:                  return *(const int16_t *) p;
    case TIF_LONG:                    return *(const uint32_t *) p;
    case TIF_SLONG:                   return *(const int32_t *) p;
    case TIF_FLOAT:                   return *(const float *) p;
    case TIF_DOUBLE:                  return *(const double *) p;
    case TIF_RATIONAL:  { const uint32_t *r = (const uint32_t *) p; return r[1] ? (double) r[0] / r[1] : 0; }
    case TIF_SRATIONAL: { const int32_t  *r = (const int32_t  *) p; return r[1] ? (double) r[0] / r[1] : 0; }
    default:                          return 0;
    }
}

static uint32_t tag_uint(const GTFile *f, uint16_t id, uint32_t i, uint32_t dflt)
{
    const GTTag *t = gt_find(f, id);
    return t && i < t->count ? (uint32_t) gt_tag_number(t, i) : dflt;
}

/* Read one IFD's entries; tag values fetched and converted to host byte order. */
static int read_ifd(GTFile *f, char *err, size_t errlen)
{
    uint8_t b[12];
    int i, big = f->bigEndian, swap = f->bigEndian != hostIsBig();

    if (!read_at(f->fp, f->ifdOffset, b, 2))
    {
        seterr(err, errlen, "cannot read the IFD entry count");
        return 0;
    }
    f->nTags = get16(b, big);
    f->tags = calloc(f->nTags, sizeof(GTTag));
    if (!f->tags)
        return 0;

    for (i = 0; i < f->nTags; ++i)
    {
        GTTag *t = &f->tags[i];
        uint32_t size, offset;
        int sz;

        if (!read_at(f->fp, f->ifdOffset + 2 + 12 * i, b, 12))
        {
            seterr(err, errlen, "cannot read a tag");
            return 0;
        }
        t->id = get16(b, big);
        t->type = get16(b + 2, big);
        t->count = get32(b + 4, big);
        sz = gt_type_size(t->type);
        size = (uint32_t) sz * t->count;
        t->data = malloc(size ? size : 1);
        if (!t->data)
            return 0;
        if (size <= 4)
        {
            memcpy(t->data, b + 8, size);   /* the value lives in the offset field */
        }
        else
        {
            offset = get32(b + 8, big);
            if (!read_at(f->fp, offset, t->data, size))
            {
                seterr(err, errlen, "cannot read tag data");
                return 0;
            }
        }
        if (swap && sz > 1)
        {
            if (t->type == TIF_RATIONAL || t->type == TIF_SRATIONAL)
                swab_values(t->data, (size_t) t->count * 2, 4);
            else
                swab_values(t->data, t->count, sz);
        }
    }
    return 1;
}

GTFile *gt_open(const char *path, char *err, size_t errlen)
{
    uint8_t h[8];
    GTFile *f = calloc(1, sizeof(GTFile));
    const GTTag *t;
    uint32_t next;

    if (!f)
        return NULL;
    f->fp = fopen(path, "rb");
    if (!f->fp)
    {
        seterr(err, errlen, "cannot open the file");
        free(f);
        return NULL;
    }
    if (!read_at(f->fp, 0, h, 8))
    {
        seterr(err, errlen, "file too short for a TIFF header");
        gt_close(f);
        return NULL;
    }
    if (get16(h, 0) == TIF_INTEL)
        f->bigEndian = 0;
    else if (get16(h, 0) == TIF_MOTOROLA)
        f->bigEndian = 1;
    else
    {
        seterr(err, errlen, "not a TIFF file (no II or MM)");
        gt_close(f);
        return NULL;
    }
    if (get16(h + 2, f->bigEndian) != TIF_VERSION)
    {
        seterr(err, errlen, get16(h + 2, f->bigEndian) == 43 ? "BigTIFF is not supported yet"
                                                             : "not a TIFF file (version is not 42)");
        gt_close(f);
        return NULL;
    }
    f->ifdOffset = get32(h + 4, f->bigEndian);
    if (!read_ifd(f, err, errlen))
    {
        gt_close(f);
        return NULL;
    }

    /* count the IFDs (only the first is decoded) */
    f->nImages = 1;
    next = f->ifdOffset;
    for (;;)
    {
        uint8_t b[4];
        uint16_t n;
        if (!read_at(f->fp, next, b, 2))
            break;
        n = get16(b, f->bigEndian);
        if (!read_at(f->fp, next + 2 + 12u * n, b, 4))
            break;
        next = get32(b, f->bigEndian);
        if (next == 0 || f->nImages > 1000)
            break;
        f->nImages++;
    }

    /* image description */
    f->width = tag_uint(f, TIF_IMAGEWIDTH, 0, 0);
    f->height = tag_uint(f, TIF_IMAGELENGTH, 0, 0);
    f->bitsPerSample = (uint16_t) tag_uint(f, TIF_BITSPERSAMPLE, 0, 1);
    f->samplesPerPixel = (uint16_t) tag_uint(f, TIF_SAMPLESPERPIXEL, 0, 1);
    f->sampleFormat = (uint16_t) tag_uint(f, TIF_SAMPLEFORMAT, 0, 1);
    f->compression = (uint16_t) tag_uint(f, TIF_COMPRESSION, 0, TIF_COMP_NONE);
    f->photometric = (uint16_t) tag_uint(f, TIF_PHOTOMETRICINTERPRETAION, 0, 1);
    f->planar = (uint16_t) tag_uint(f, TIF_PLANARCONFIGURATION, 0, 1);
    f->predictor = (uint16_t) tag_uint(f, TIF_PREDICTOR, 0, TIF_PRED_NONE);
    f->tiled = gt_find(f, TIF_TILEOFFSETS) != NULL;
    f->rowsPerStrip = tag_uint(f, TIF_ROWSPERSTRIP, 0, f->height);
    if (f->rowsPerStrip == 0 || f->rowsPerStrip > f->height)
        f->rowsPerStrip = f->height;
    f->tileWidth = tag_uint(f, TIF_TILEWIDTH, 0, 0);
    f->tileLength = tag_uint(f, TIF_TILELENGTH, 0, 0);

    /* georeferencing: the transformation matrix, or tie point + pixel scale */
    if ((t = gt_find(f, TIF_MODELTRANSFORMATION)) && t->count >= 16)
    {
        f->hasTransform = 1;
        f->gt[0] = gt_tag_number(t, 3);  f->gt[1] = gt_tag_number(t, 0);  f->gt[2] = gt_tag_number(t, 1);
        f->gt[3] = gt_tag_number(t, 7);  f->gt[4] = gt_tag_number(t, 4);  f->gt[5] = gt_tag_number(t, 5);
    }
    else if ((t = gt_find(f, TIF_MODELTIEPOINT)) && t->count >= 6 && gt_find(f, TIF_MODELPIXELSCALE))
    {
        const GTTag *s = gt_find(f, TIF_MODELPIXELSCALE);
        double I = gt_tag_number(t, 0), J = gt_tag_number(t, 1), X = gt_tag_number(t, 3), Y = gt_tag_number(t, 4);
        double sx = gt_tag_number(s, 0), sy = gt_tag_number(s, 1);
        f->hasTransform = 1;
        f->gt[1] = sx;  f->gt[2] = 0;  f->gt[0] = X - I * sx;
        f->gt[4] = 0;   f->gt[5] = -sy; f->gt[3] = Y + J * sy;
    }

    /* GeoKeys: header (version, revision, minor, count), then 4 shorts per key */
    if ((t = gt_find(f, TIF_GEOKEYDIRECTORY)) && t->count >= 4)
    {
        int i, n = (int) gt_tag_number(t, 3);
        if (4 + 4 * n > (int) t->count)
            n = ((int) t->count - 4) / 4;
        f->keys = calloc(n > 0 ? n : 1, sizeof(GTGeoKey));
        f->nKeys = n;
        for (i = 0; i < n; ++i)
        {
            f->keys[i].id = (uint16_t) gt_tag_number(t, 4 + 4 * i);
            f->keys[i].location = (uint16_t) gt_tag_number(t, 5 + 4 * i);
            f->keys[i].count = (uint16_t) gt_tag_number(t, 6 + 4 * i);
            f->keys[i].valueOrIndex = (uint16_t) gt_tag_number(t, 7 + 4 * i);
        }
    }

    /* PixelIsPoint: the tie point names a pixel centre. Shift by half a pixel so the
       transform, like GDAL's, maps (0,0) to the corner of the top-left pixel. */
    if (f->hasTransform && gt_key_int(f, GK_GTRasterType, 1) == 2)
    {
        f->gt[0] -= 0.5 * f->gt[1] + 0.5 * f->gt[2];
        f->gt[3] -= 0.5 * f->gt[4] + 0.5 * f->gt[5];
    }
    return f;
}

void gt_close(GTFile *f)
{
    int i;
    if (!f)
        return;
    if (f->fp)
        fclose(f->fp);
    for (i = 0; i < f->nTags; ++i)
        free(f->tags[i].data);
    free(f->tags);
    free(f->keys);
    free(f);
}

/* ---------- GeoKeys ---------- */

const GTGeoKey *gt_key(const GTFile *f, uint16_t id)
{
    int i;
    for (i = 0; i < f->nKeys; ++i)
        if (f->keys[i].id == id)
            return &f->keys[i];
    return NULL;
}

int gt_key_int(const GTFile *f, uint16_t id, int dflt)
{
    const GTGeoKey *k = gt_key(f, id);
    return k && k->location == 0 ? k->valueOrIndex : dflt;
}

int gt_key_string(const GTFile *f, uint16_t id, char *out, size_t outlen)
{
    const GTGeoKey *k = gt_key(f, id);
    const GTTag *t = gt_find(f, TIF_GEOASCIIPARAMS);
    size_t n;
    if (!k || k->location != TIF_GEOASCIIPARAMS || !t || outlen == 0)
        return 0;
    if ((uint32_t) k->valueOrIndex + k->count > t->count)
        return 0;
    n = k->count < outlen ? k->count : outlen - 1;
    memcpy(out, t->data + k->valueOrIndex, n);
    out[n] = 0;
    if (n && out[n - 1] == '|')         /* strings end with a '|' separator */
        out[n - 1] = 0;
    return 1;
}

int gt_key_double(const GTFile *f, uint16_t id, double *out)
{
    const GTGeoKey *k = gt_key(f, id);
    const GTTag *t = gt_find(f, TIF_GEODOUBLEPARAMS);
    if (!k || k->location != TIF_GEODOUBLEPARAMS || !t || k->valueOrIndex >= t->count)
        return 0;
    *out = gt_tag_number(t, k->valueOrIndex);
    return 1;
}

int gt_pixel_to_model(const GTFile *f, double col, double row, double *x, double *y)
{
    if (!f->hasTransform)
        return 0;
    *x = f->gt[0] + f->gt[1] * col + f->gt[2] * row;
    *y = f->gt[3] + f->gt[4] * col + f->gt[5] * row;
    return 1;
}

/* ---------- pixels ---------- */

/* Undo horizontal differencing (Predictor 2) on rows of `width` pixels, host byte order. */
static void undo_predictor(uint8_t *buf, uint32_t rows, uint32_t width, int spp, int bytes)
{
    uint32_t r, i;
    size_t rowSamples = (size_t) width * spp;
    for (r = 0; r < rows; ++r)
    {
        if (bytes == 1)
        {
            uint8_t *p = buf + r * rowSamples;
            for (i = spp; i < rowSamples; ++i)
                p[i] = (uint8_t) (p[i] + p[i - spp]);
        }
        else if (bytes == 2)
        {
            uint16_t *p = (uint16_t *) buf + r * rowSamples;
            for (i = spp; i < rowSamples; ++i)
                p[i] = (uint16_t) (p[i] + p[i - spp]);
        }
        else if (bytes == 4)
        {
            uint32_t *p = (uint32_t *) buf + r * rowSamples;
            for (i = spp; i < rowSamples; ++i)
                p[i] = p[i] + p[i - spp];
        }
    }
}

uint8_t *gt_read_image(GTFile *f, size_t *nbytes, char *err, size_t errlen)
{
    const GTTag *offs, *counts;
    int bytes = f->bitsPerSample / 8, spp = f->samplesPerPixel;
    int swap = f->bigEndian != hostIsBig() && bytes > 1;
    uint32_t blockW, blockH, across, down, nBlocks, b;
    size_t pixelBytes = (size_t) bytes * spp, blockBytes, total;
    uint8_t *image, *block = NULL, *packed = NULL;

    if (f->bitsPerSample % 8 != 0 || bytes < 1 || bytes > 4)
    {
        seterr(err, errlen, "only 8, 16 and 32-bit samples are supported");
        return NULL;
    }
    if (f->planar != 1 && spp > 1)
    {
        seterr(err, errlen, "separate planes (PlanarConfiguration 2) are not supported yet");
        return NULL;
    }
    if (f->compression != TIF_COMP_NONE && f->compression != TIF_COMP_LZW)
    {
        seterr(err, errlen, "only uncompressed and LZW images are supported");
        return NULL;
    }
    if (f->predictor == TIF_PRED_FLOAT)
    {
        seterr(err, errlen, "the floating-point predictor (3) is not supported yet");
        return NULL;
    }

    if (f->tiled)
    {
        offs = gt_find(f, TIF_TILEOFFSETS);
        counts = gt_find(f, TIF_TILEBYTECOUNTS);
        blockW = f->tileWidth;
        blockH = f->tileLength;
    }
    else
    {
        offs = gt_find(f, TIF_STRIPOFFSETS);
        counts = gt_find(f, TIF_STRIPBYTECOUNTS);
        blockW = f->width;
        blockH = f->rowsPerStrip;
    }
    if (!offs || !counts || blockW == 0 || blockH == 0)
    {
        seterr(err, errlen, "missing strip or tile layout");
        return NULL;
    }
    across = (f->width + blockW - 1) / blockW;
    down = (f->height + blockH - 1) / blockH;
    nBlocks = across * down;
    if (offs->count < nBlocks || counts->count < nBlocks)
    {
        seterr(err, errlen, "fewer strips or tiles than the image needs");
        return NULL;
    }

    total = (size_t) f->width * f->height * pixelBytes;
    blockBytes = (size_t) blockW * blockH * pixelBytes;
    image = calloc(total ? total : 1, 1);
    block = malloc(blockBytes);
    if (!image || !block)
    {
        free(image);
        free(block);
        seterr(err, errlen, "out of memory");
        return NULL;
    }

    for (b = 0; b < nBlocks; ++b)
    {
        uint32_t offset = (uint32_t) gt_tag_number(offs, b), count = (uint32_t) gt_tag_number(counts, b);
        uint32_t bx = (b % across) * blockW, by = (b / across) * blockH, r, rows;
        size_t got;

        memset(block, 0, blockBytes);
        packed = realloc(packed, count ? count : 1);
        if (!packed || (count && !read_at(f->fp, offset, packed, count)))
        {
            seterr(err, errlen, "cannot read a strip or tile");
            free(image);
            free(block);
            free(packed);
            return NULL;
        }
        if (f->compression == TIF_COMP_LZW)
        {
            long n = lzw_tiff_decode(packed, count, block, blockBytes);
            if (n < 0)
            {
                seterr(err, errlen, "corrupt LZW data");
                free(image);
                free(block);
                free(packed);
                return NULL;
            }
            got = (size_t) n;
        }
        else
        {
            got = count < blockBytes ? count : blockBytes;
            memcpy(block, packed, got);
        }
        (void) got;

        /* a last strip may be short */
        rows = blockH;
        if (!f->tiled && by + rows > f->height)
            rows = f->height - by;

        if (swap)
            swab_values(block, (size_t) blockW * rows * spp, bytes);
        if (f->predictor == TIF_PRED_HORIZONTAL)
            undo_predictor(block, rows, blockW, spp, bytes);

        /* copy into place, clipping tiles at the right and bottom edges */
        for (r = 0; r < rows && by + r < f->height; ++r)
        {
            uint32_t w = bx + blockW > f->width ? f->width - bx : blockW;
            memcpy(image + ((size_t) (by + r) * f->width + bx) * pixelBytes,
                   block + (size_t) r * blockW * pixelBytes, (size_t) w * pixelBytes);
        }
    }
    free(block);
    free(packed);
    if (nbytes)
        *nbytes = total;
    return image;
}

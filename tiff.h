/*
 * tiff.h - TIFF and GeoTIFF constants.
 *
 * Started from Brian O'Brien's tiff.h (IDC software, March 2000). Names kept;
 * types changed to fixed-width so the layout is the same on every compiler,
 * tag 278 renamed RowsPerStrip (was RowsPerPixel), and the tags a GeoTIFF
 * reader needs added.
 *
 * The 2000 code read these structs straight from the file with fread. That only
 * works on a little-endian machine whose "unsigned long" is 4 bytes; on a 64-bit
 * Pi it is 8. geotiff.c reads every field one at a time instead, and byte-swaps
 * for big-endian ("MM") files. The structs are kept to describe the format.
 */
#ifndef TIFF_H
#define TIFF_H

#include <stdint.h>

#define U16BIT uint16_t
#define U32BIT uint32_t

typedef struct _TiffHeader
{
    U16BIT Identifier;   /* Byte-order identifier: "II" Intel, "MM" Motorola */
    U16BIT Version;      /* TIFF version number (always 42 = 0x2A)            */
    U32BIT IFDOffset;    /* Offset of the first Image File Directory          */
} TIFHEAD;               /* 8 bytes in the file                               */

typedef struct _TifTag
{
    U16BIT TagId;        /* The tag identifier                                */
    U16BIT DataType;     /* The scalar type of the data items                 */
    U32BIT DataCount;    /* The number of items in the tag data               */
    U32BIT DataOffset;   /* Offset to the data, OR the data itself when it    */
                         /* fits in 4 bytes (left-justified in this field)    */
} TIFTAG;                /* 12 bytes in the file                              */

typedef struct _TifIfd
{
    U16BIT NumDirEntries; /* Number of tags in the IFD */
    TIFTAG *TagList;      /* Array of tags             */
    U32BIT NextIFDOffset; /* Offset to next IFD, 0 = last */
} TIFIFD;

/* Byte-order identifiers */
#define TIF_INTEL      0x4949   /* "II" little-endian */
#define TIF_MOTOROLA   0x4D4D   /* "MM" big-endian    */
#define TIF_VERSION    42

/* Data types and their sizes in bytes */
#define TIF_BYTE       1   /* 1 */
#define TIF_ASCII      2   /* 1 */
#define TIF_SHORT      3   /* 2 */
#define TIF_LONG       4   /* 4 */
#define TIF_RATIONAL   5   /* 8: two LONGs, numerator / denominator (was 4 in 2000) */
#define TIF_SBYTE      6   /* 1 */
#define TIF_UNDEFINE   7   /* 1 */
#define TIF_SSHORT     8   /* 2 */
#define TIF_SLONG      9   /* 4 */
#define TIF_SRATIONAL 10   /* 8 */
#define TIF_FLOAT     11   /* 4 */
#define TIF_DOUBLE    12   /* 8 */

/* Baseline and extension tags */
#define TIF_NEWSUBFILE                254
#define TIF_IMAGEWIDTH                256
#define TIF_IMAGELENGTH               257
#define TIF_BITSPERSAMPLE             258
#define TIF_COMPRESSION               259
#define TIF_PHOTOMETRICINTERPRETAION  262   /* spelling kept from 2000 */
#define TIF_IMAGEDESCRIPTION          270
#define TIF_STRIPOFFSETS              273
#define TIF_ORIENTATION               274
#define TIF_SAMPLESPERPIXEL           277
#define TIF_ROWSPERSTRIP              278   /* was TIF_ROWSPERPIXEL */
#define TIF_STRIPBYTECOUNTS           279
#define TIF_XRESOLUTION               282
#define TIF_YRESOLUTION               283
#define TIF_PLANARCONFIGURATION       284
#define TIF_RESOLUTIONUNIT            296
#define TIF_SOFTWARE                  305
#define TIF_DATETIME                  306
#define TIF_ARTIST                    315
#define TIF_HOSTCOMPUTER              316
#define TIF_PREDICTOR                 317
#define TIF_COLORMAP                  320
#define TIF_TILEWIDTH                 322
#define TIF_TILELENGTH                323
#define TIF_TILEOFFSETS               324
#define TIF_TILEBYTECOUNTS            325
#define TIF_EXTRASAMPLES              338
#define TIF_SAMPLEFORMAT              339

/* GeoTIFF tags (OGC GeoTIFF 1.1) */
#define TIF_MODELPIXELSCALE         33550   /* DOUBLE x3: ScaleX, ScaleY, ScaleZ        */
#define TIF_MODELTIEPOINT           33922   /* DOUBLE x6n: I,J,K, X,Y,Z per tie point   */
#define TIF_MODELTRANSFORMATION     34264   /* DOUBLE x16: 4x4 raster-to-model matrix   */
#define TIF_GEOKEYDIRECTORY         34735   /* SHORT x4(n+1): header + n keys           */
#define TIF_GEODOUBLEPARAMS         34736   /* DOUBLE values referenced by keys         */
#define TIF_GEOASCIIPARAMS          34737   /* ASCII values referenced by keys, '|'-separated */
#define TIF_GDAL_METADATA           42112
#define TIF_GDAL_NODATA             42113

/* Compression values */
#define TIF_COMP_NONE        1
#define TIF_COMP_CCITT       2
#define TIF_COMP_LZW         5
#define TIF_COMP_OJPEG       6
#define TIF_COMP_JPEG        7
#define TIF_COMP_DEFLATE     8
#define TIF_COMP_PACKBITS    32773
#define TIF_COMP_DEFLATE_OLD 32946

/* Predictor values */
#define TIF_PRED_NONE        1
#define TIF_PRED_HORIZONTAL  2
#define TIF_PRED_FLOAT       3

/* Some GeoKeys (GeoKeyDirectory key ids) */
#define GK_GTModelType           1024   /* 1 projected, 2 geographic, 3 geocentric */
#define GK_GTRasterType          1025   /* 1 PixelIsArea, 2 PixelIsPoint           */
#define GK_GTCitation            1026
#define GK_GeographicType        2048   /* e.g. 4326 = WGS 84                       */
#define GK_GeogCitation          2049
#define GK_GeogGeodeticDatum     2050
#define GK_GeogAngularUnits      2054
#define GK_GeogEllipsoid         2056
#define GK_GeogSemiMajorAxis     2057
#define GK_GeogInvFlattening     2059
#define GK_ProjectedCSType       3072   /* e.g. 32607 = WGS 84 / UTM zone 7N        */
#define GK_PCSCitation           3073
#define GK_Projection            3074
#define GK_ProjCoordTrans        3075
#define GK_ProjLinearUnits       3076
#define GK_VerticalCSType        4096
#define GK_VerticalUnits         4099

#endif

# geotiff

A small GeoTIFF reader in plain C, no dependencies. It is the reference implementation for a
Xojo port (FlightOverview), and it is checked byte for byte against GDAL.

It grew from two older pieces of Brian O'Brien's code:
- `rast2tif.c` / `tiff.h` (IDC software, 2000): the TIFF header and IFD walk. `tiff.h` keeps its names.
- [BrianOBrien/lzw](https://github.com/BrianOBrien/lzw) (GIF LZW): the decoder's string table and stack,
  changed for TIFF (most-significant-bit-first codes, no sub-blocks, early change).

## What it reads
- Classic TIFF, Intel (II) or Motorola (MM) byte order; the first image (later IFDs are counted)
- Strips or tiles; uncompressed or LZW; horizontal predictor (2); 8, 16 and 32-bit samples, interleaved
- GeoTIFF: ModelPixelScale + ModelTiepoint, or ModelTransformation; GeoKeyDirectory with its
  double and ASCII parameters; PixelIsPoint handled like GDAL (half-pixel shift)

Not yet: BigTIFF, Deflate/JPEG/PackBits, separate planes, the floating-point predictor, projections
(it reports the EPSG codes; turning UTM into lat/long comes later). Writing comes next.

## Use
```
make            # builds gtinfo
./gtinfo file.tif                    # tags, GeoKeys, origin, pixel size, corners
./gtinfo -corners file.tif           # the four corners and the centre
./gtinfo -geotransform file.tif      # 6 numbers, GDAL order
./gtinfo -raw out.raw file.tif       # also decode the pixels (interleaved, host byte order)
make test       # needs gdal-bin
```

## Tests
`tests/run_tests.sh` makes GeoTIFFs with GDAL from FlightOverview's map (`tests/map.png`), georeferenced
at 68.17 N 139.37 W, in 13 layouts: uncompressed, LZW, LZW + predictor, tiled, big-endian, grey,
16-bit, one row per strip, one strip for the whole image, UTM zone 7N, PixelIsPoint. For each one the
geotransform must match GDAL's and the decoded pixels must match GDAL's byte for byte.

## API (geotiff.h)
`gt_open`, `gt_close`, `gt_find`, `gt_tag_number`, `gt_read_image`, `gt_key_int`, `gt_key_string`,
`gt_key_double`, `gt_pixel_to_model`.

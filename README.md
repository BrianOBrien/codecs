# geotiff

A small GeoTIFF reader and writer in plain C, no dependencies. It is the reference implementation for a
Xojo port (FlightOverview), and it is checked byte for byte against GDAL.

It grew from two older pieces of Brian O'Brien's code:
- `rast2tif.c` / `tiff.h` (IDC software, 2000): the TIFF header and IFD walk. `tiff.h` keeps its names.
- [BrianOBrien/lzw](https://github.com/BrianOBrien/lzw) (GIF LZW): the decoder's string table and stack,
  changed for TIFF (most-significant-bit-first codes, no sub-blocks, early change).

`inflate.c` (Deflate) is written from RFC 1950/1951 and structured like Mark Adler's `puff.c`;
PackBits is TIFF's run-length coding.

## What it reads
- Classic TIFF, Intel (II) or Motorola (MM) byte order; the first image (later IFDs are counted)
- Strips or tiles; uncompressed, LZW, Deflate (8 and 32946) or PackBits; horizontal predictor (2);
  8, 16 and 32-bit samples, interleaved
- GeoTIFF: ModelPixelScale + ModelTiepoint, or ModelTransformation; GeoKeyDirectory with its
  double and ASCII parameters; PixelIsPoint handled like GDAL (half-pixel shift)

## What it writes
- Classic TIFF, little-endian, strips; uncompressed, LZW or PackBits; horizontal predictor
- 1-4 samples of 8, 16 or 32 bits (grey, grey + alpha, RGB, RGBA)
- GeoTIFF: ModelPixelScale + ModelTiepoint (or ModelTransformation when rotated), GeoKeys
  GTModelType, GTRasterType, GTCitation, and the EPSG code as GeographicType or ProjectedCSType
- The LZW encoder follows the loop of Brian's `lzw::write` (compress/Lzw.cpp), with TIFF's
  bit order, early change and Clear at 4094; its output is within 0.01% of libtiff's size.

Not yet: BigTIFF, JPEG, CCITT fax (Huffman, compression 2/3/4), separate planes, the floating-point
predictor, projections (it reports the EPSG codes; turning UTM into lat/long comes later), writing
Deflate or tiles.

## Use
```
make            # builds gtinfo
./gtinfo file.tif                    # tags, GeoKeys, origin, pixel size, corners
./gtinfo -corners file.tif           # the four corners and the centre
./gtinfo -geotransform file.tif      # 6 numbers, GDAL order
./gtinfo -raw out.raw file.tif       # also decode the pixels (interleaved, host byte order)
./gtcopy [-c none|lzw|packbits] [-p] [-rows N] in.tif out.tif   # read, then write again
make test       # needs gdal-bin and libtiff-tools
```

## Tests
`tests/run_tests.sh` makes GeoTIFFs with GDAL from FlightOverview's map (`tests/map.png`), georeferenced
at 68.17 N 139.37 W, in 20 layouts: uncompressed, LZW, Deflate (levels 1 and 9), PackBits, each with
predictor / tiles / big-endian / 16-bit variations, one row per strip, one strip for the whole image,
UTM zone 7N, PixelIsPoint. For each one the geotransform must match GDAL's and the decoded pixels
must match GDAL's byte for byte. Then about 200 cut-short and corrupted copies must give an error,
never a crash.

`tests/run_write_tests.sh` copies 8 of those files 6 ways each with `gtcopy` (none, PackBits, LZW,
LZW + predictor, one row per strip, one strip). Every copy must read cleanly in libtiff and give
GDAL the same geotransform, EPSG code, AREA_OR_POINT and pixels as the source: 48 of 48 pass.

## API (geotiff.h)
`gt_open`, `gt_close`, `gt_find`, `gt_tag_number`, `gt_read_image`, `gt_key_int`, `gt_key_string`,
`gt_key_double`, `gt_pixel_to_model`, `gt_write` (with `GTWriteOptions`).

## Xojo port (`xojo/`)
The same library in Xojo (2026r3.1, API 2), file for file:

| C | Xojo |
|---|---|
| `tiff.h` | module `TIFF` (same constant names) |
| `lzw.c` | module `LZW` (`Decode`, `Encode`) |
| `inflate.c` | classes `Inflater`, `HuffTable` |
| PackBits in `geotiff.c` / `gtwrite.c` | module `PackBits` |
| `geotiff.c` | classes `GTFile`, `GTTag`, `GTGeoKey` |
| `gtwrite.c` | module `GTWriter`, classes `GTWriteOptions`, `GTOutTag` |
| `gtinfo`, `gtcopy` | console app `xgt` (`xgt -geotransform`, `xgt -raw`, `xgt copy`) |

```
Var err As String
Var f As GTFile = GTFile.Open("/path/map.tif", err)
Var pixels As MemoryBlock = f.ReadImage(err)      // interleaved, this machine's byte order
Var o As New GTWriteOptions                       // LZW by default
o.HasTransform = f.HasTransform
...
Call GTWriter.Write("/path/copy.tif", pixels, f.Width, f.Height, f.SamplesPerPixel, f.BitsPerSample, o, err)
```

`xojo/build.sh` builds `xgt` through the Xojo IDE's scripting socket (`xojo/tools/`); `make test-xojo`
then runs the C test suites against it: 21/21 reader tests and 48/48 writer tests pass, and the Xojo
writer's image data is byte-identical to the C writer's.

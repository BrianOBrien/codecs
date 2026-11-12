# codecs

Image codecs in three layers:

```
consumers       FlightOverview, a WinFLI revival, DICOM tools, command-line tools ...
                    | use
xojo/           pure Xojo modules, one folder per codec (no plug-ins, any platform)
                    | ported line for line from, tested against
c/              small plain-C reference codecs, no dependencies
                    | checked against
tests/          GDAL, libtiff, ffmpeg, Pillow
```

Each codec has a C reference that is short enough to read and is checked against independent tools.
Its Xojo port must pass the same tests, driven through the console test app `xgt`. Consumers live
in their own repos and copy in, or link to, only the Xojo folders they need.

| Codec | C | Xojo | Status |
|---|---|---|---|
| LZW (TIFF flavour) | `c/lzw.c` | `xojo/LZWCodec` | decode + encode |
| Deflate | `c/inflate.c` | `xojo/InflateCodec` | decode |
| PackBits | in `c/geotiff.c`, `c/gtwrite.c` | `xojo/PackBitsCodec` | decode + encode |
| TIFF / GeoTIFF | `c/geotiff.c`, `c/gtwrite.c` | `xojo/TIFFCodec` | read + write |
| GIF (with GIF-flavour LZW) | `c/gif.c`, `c/lzw.c` | next | read, composite, write |
| FLI / FLC | | | then (from Brian's Readfli; a new writer) |

History: this repo started as [geotiff](https://github.com/BrianOBrien/geotiff), whose commits it
keeps. The code grew from Brian O'Brien's `rast2tif.c` / `tiff.h` (2000) and his GIF LZW
([lzw](https://github.com/BrianOBrien/lzw)); Deflate is written from RFC 1950/1951, structured
like Mark Adler's `puff.c`.

## Build and test
```
make              # C tools: c/gtinfo, c/gtcopy
make test         # needs gdal-bin, libtiff-tools, ffmpeg, python3-pil
tools/build-xgt.sh   # builds the Xojo test app through the Xojo IDE scripting socket
make test-xojo    # the same tests on the Xojo build
```

## GIF
From Brian's `Readgif` (1999) and `Writegif` (1998-99, the GIF export of WinFLI 4.0), with fixes: the
writer's colour table was filled backwards; 1-bit images need LZW code size 2; the table size flag now
matches what is written; unknown extensions are skipped. The LZW is the GIF flavour of Brian's
`lzw_decompress` / `lzw::write` (least significant bit first, no early change, 255-byte sub-blocks).

Reads GIF87a/89a: every frame with its rectangle, local or global palette, interlace, delay, disposal,
transparency; NETSCAPE loop count; comments. `gif_composite` renders a frame as a viewer shows it.
Writes GIF89a with palettes, loop count, comment, delay, disposal and transparency.

`giftool file.gif` (summary), `giftool -rgba out.raw file.gif` (every rendered frame),
`giftool copy in.gif out.gif`.

Tests (`tests/gif/`): 13 GIFs from Pillow, ffmpeg and a hand-made true 1-bit file (2-colour table,
LZW code size 2): palettes of 2-256 colours, interlace, animations with global and local palettes,
sub-rectangles, transparency, disposal 1/2/3. Every rendered frame must equal ffmpeg's and Pillow's
pixel for pixel, and every copy made by our writer must decode in ffmpeg exactly like its source.
130 damaged files: no crash.

## TIFF / GeoTIFF
Reads classic TIFF (II or MM), strips or tiles, uncompressed, LZW, Deflate or PackBits, horizontal
predictor, 8/16/32-bit samples, GeoTIFF tie point + scale or transformation, GeoKeys, PixelIsPoint.
Writes little-endian strips, uncompressed, LZW or PackBits, predictor, geo tags and EPSG.
Not yet: BigTIFF, JPEG, CCITT fax, separate planes, float predictor, projections, Deflate/tile writing.

C tools: `gtinfo [-corners | -geotransform] [-raw out.raw] file.tif`,
`gtcopy [-c none|lzw|packbits] [-p] [-rows N] in.tif out.tif`.

Xojo:
```
Var err As String
Var f As GTFile = GTFile.Open("/path/map.tif", err)
Var pixels As MemoryBlock = f.ReadImage(err)      // interleaved, this machine's byte order
Var o As New GTWriteOptions                       // LZW by default
o.HasTransform = f.HasTransform
...
Call GTWriter.Write("/path/copy.tif", pixels, f.Width, f.Height, f.SamplesPerPixel, f.BitsPerSample, o, err)
```


Tests (`tests/geotiff/`): 20 GDAL-made layouts must match GDAL pixel for pixel and in georeferencing;
about 200 damaged files must give an error, never a crash or exception; 48 copies (8 sources x 6 write
modes) must read cleanly in libtiff and match their source in GDAL. C and Xojo both pass all of them,
and the two writers produce byte-identical image data.

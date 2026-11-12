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
| GIF (with GIF-flavour LZW) | `c/gif.c`, `c/lzw.c` | `xojo/GIFCodec`, `LZW.GIFDecode/GIFEncode` | read, composite, write |
| FLI / FLC | `c/fli.c` | next | read FLI + FLC, write FLC |

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
`giftool copy in.gif out.gif`. Xojo: `GIFFile.Read(path, err)`, `.Frames()`, `.Composite(i)`, `.Write(path, err)`;
the test app runs it as `xgt gif ...`.

Tests (`tests/gif/`): 13 GIFs from Pillow, ffmpeg and a hand-made true 1-bit file (2-colour table,
LZW code size 2): palettes of 2-256 colours, interlace, animations with global and local palettes,
sub-rectangles, transparency, disposal 1/2/3. Every rendered frame must equal ffmpeg's and Pillow's
pixel for pixel, and every copy made by our writer must decode in ffmpeg exactly like its source.
130 damaged files: no crash. C and Xojo both pass, and their copies are byte-identical.

## FLI / FLC
The reader follows Brian's `Readfli` (1998-2000), the core of WinFLI 98: FLI and FLC headers, and the
chunks COLOR_256, COLOR_64, LC, SS2, BLACK, BYTE_RUN, COPY and postage stamp. Fixes: COLOR chunks with
several packets now move past each packet; FLC speed is milliseconds (FLI: 1/70 s); BYTE_RUN lines are
decoded to the image width (FLC spec); 64-level colours map 63 to 255; chunk sizes are trusted for
stepping, and prefix/unknown chunks are skipped.

WinFLI only ever saved GIFs, so the FLC writer is new: BYTE_RUN first frame, SS2 deltas (LC deltas for
odd widths: ffmpeg puts SS2's "last byte" word in the wrong column), COLOR_256 when the palette changes,
and the ring frame back to the start.

`flitool file.fli`, `flitool -rgba out.raw file.fli`, `flitool copy in.fli out.flc`,
`flitool pattern out.flc W H N` (a test animation of any size).

Tests (`tests/fli/`): ten real FLI/FLC files from Brian's drive (3D Studio 3 and others, 1993-2002;
fetched from the WD into `tests/fli/corpus/`, not committed), 516 frames: every frame equals ffmpeg's
decoder pixel for pixel (one file, which ffmpeg refuses, is checked through its copy). Each is copied as
an FLC with our writer and must decode the same in ffmpeg and in our reader; so must generated patterns
of 640x203, 641x203, 2x300 and 1x1. 140 damaged files: no crash.

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

#!/bin/bash
# Make GeoTIFFs with GDAL in many layouts, read each with gtinfo, and check against GDAL:
#   - corner coordinates (to 1e-6)
#   - every decoded pixel byte (md5 of gtinfo -raw vs GDAL's raw ENVI output)
# Needs: gdal-bin. Source picture: tests/map.png (FlightOverview's Map.png).
set -u
cd "$(dirname "$0")"
OUT=out; mkdir -p $OUT
GT=../gtinfo
SRC=map.png
pass=0; fail=0

# The FlightOverview map: 509 x 574 px at 16.6667 px/mi, centred on 68.1666667 N, 139.3741667 W
ULLR="-139.96664 68.41613 -138.78169 67.91720"

# Base files: 8-bit RGB in lat/long (EPSG:4326), and the same warped to UTM zone 7N (EPSG:32607)
gdal_translate -q -of GTiff -a_srs EPSG:4326 -a_ullr $ULLR $SRC $OUT/base_ll.tif
gdalwarp -q -overwrite -t_srs EPSG:32607 -r near $OUT/base_ll.tif $OUT/base_utm.tif

make_case() {  # name source creation-options...
  local name=$1 src=$2; shift 2
  gdal_translate -q "$@" $src $OUT/$name.tif
}
make_case none_strip     $OUT/base_ll.tif  -co COMPRESS=NONE
make_case lzw_strip      $OUT/base_ll.tif  -co COMPRESS=LZW
make_case lzw_pred       $OUT/base_ll.tif  -co COMPRESS=LZW -co PREDICTOR=2
make_case lzw_tiled      $OUT/base_ll.tif  -co COMPRESS=LZW -co TILED=YES -co BLOCKXSIZE=128 -co BLOCKYSIZE=128
make_case lzw_tiled_pred $OUT/base_ll.tif  -co COMPRESS=LZW -co TILED=YES -co PREDICTOR=2
make_case bigendian      $OUT/base_ll.tif  -co COMPRESS=LZW -co ENDIANNESS=BIG
make_case gray8          $OUT/base_ll.tif  -b 1 -co COMPRESS=LZW
make_case u16_pred       $OUT/base_ll.tif  -ot UInt16 -scale 0 255 0 65535 -co COMPRESS=LZW -co PREDICTOR=2
make_case u16_big        $OUT/base_ll.tif  -ot UInt16 -scale 0 255 0 65535 -co COMPRESS=LZW -co ENDIANNESS=BIG -co PREDICTOR=2
make_case one_strip_row  $OUT/base_ll.tif  -co COMPRESS=LZW -co BLOCKYSIZE=1
make_case one_big_strip  $OUT/base_ll.tif  -co COMPRESS=LZW -co BLOCKYSIZE=574   # fills the LZW table: 12-bit codes and Clear codes
make_case utm_lzw        $OUT/base_utm.tif -co COMPRESS=LZW
make_case pixelispoint   $OUT/base_ll.tif  -co COMPRESS=LZW --config GTIFF_POINT_GEO_IGNORE FALSE -mo AREA_OR_POINT=Point

check() {  # name
  local f=$OUT/$1.tif ok=1 msg=""
  # georeferencing: GDAL's geotransform vs gtinfo's, relative difference
  local g=$(gdalinfo -json $f | python3 -c 'import json,sys; print(*json.load(sys.stdin)["geoTransform"])')
  local m=$($GT -geotransform $f)
  local d=$(python3 -c "a=[float(v) for v in '$g'.split()]; b=[float(v) for v in '$m'.split()]; print('%.2g' % max(abs(x-y)/max(1.0,abs(x)) for x,y in zip(a,b)) if len(b)==6 else 'missing')")
  if [ "$d" = missing ] || ! awk -v d="$d" 'BEGIN{exit !(d < 1e-12)}'; then ok=0; msg="geotransform differs ($d)"; fi
  # pixels: GDAL raw (band interleaved by pixel) vs gtinfo -raw
  gdal_translate -q -of ENVI -co INTERLEAVE=BIP $f $OUT/$1.gdal.raw
  if $GT -raw $OUT/$1.gt.raw $f >/dev/null 2>$OUT/$1.err; then
    if [ "$(md5sum < $OUT/$1.gdal.raw)" != "$(md5sum < $OUT/$1.gt.raw)" ]; then ok=0; msg="$msg pixels differ"; fi
  else
    ok=0; msg="$msg $(cat $OUT/$1.err)"
  fi
  if [ $ok = 1 ]; then pass=$((pass+1)); printf "PASS  %-16s geotransform within %s, pixels identical\n" $1 "$d"
  else fail=$((fail+1)); printf "FAIL  %-16s %s\n" $1 "$msg"; fi
}

for c in none_strip lzw_strip lzw_pred lzw_tiled lzw_tiled_pred bigendian gray8 u16_pred u16_big one_strip_row one_big_strip utm_lzw pixelispoint; do
  check $c
done
echo "$pass passed, $fail failed"
[ $fail = 0 ]

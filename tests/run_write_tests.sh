#!/bin/bash
# Writer tests. Needs run_tests.sh to have made tests/out/*.tif (the reader tests do).
# Each source is copied by gtcopy (our reader -> our writer) in several modes; then:
#   - libtiff (tiffinfo -D) must read it with no errors or warnings
#   - GDAL must see the same geotransform, EPSG code, AREA_OR_POINT and pixels as in the source
set -u
cd "$(dirname "$0")"
OUT=out; mkdir -p $OUT/w
CP=../gtcopy
pass=0; fail=0

gdal_gt()   { gdalinfo -json "$1" | python3 -c 'import json,sys; print(*json.load(sys.stdin).get("geoTransform",[]))'; }
gdal_epsg() { gdalsrsinfo -o epsg "$1" 2>/dev/null | tr -d '\n '; }
gdal_aop()  { gdalinfo "$1" | grep -o 'AREA_OR_POINT=[A-Za-z]*'; }
gdal_md5()  { gdal_translate -q -of ENVI -co INTERLEAVE=BIP "$1" "$2" && md5sum < "$2" | cut -d' ' -f1; }

sources="none_strip gray8 u16_pred u16_big lzw_tiled utm_lzw pixelispoint deflate_tiled16"
modes="none packbits lzw lzw_pred rows1 onestrip"

for src in $sources; do
  S=$OUT/$src.tif
  sgt=$(gdal_gt $S); sepsg=$(gdal_epsg $S); saop=$(gdal_aop $S); smd5=$(gdal_md5 $S $OUT/w/$src.src.raw)
  for m in $modes; do
    case $m in
      none)     args="-c none" ;;
      packbits) args="-c packbits" ;;
      lzw)      args="-c lzw" ;;
      lzw_pred) args="-c lzw -p" ;;
      rows1)    args="-c lzw -rows 1" ;;
      onestrip) args="-c lzw -p -rows 100000" ;;
    esac
    D=$OUT/w/${src}_$m.tif; msg=""
    if ! $CP $args $S $D 2>$OUT/w/err.txt; then msg="gtcopy failed: $(cat $OUT/w/err.txt)"
    else
      tiffinfo -D $D 2>&1 >/dev/null | grep -v -E "Unknown field with tag (33550|33922|34264|34735|34736|34737) " > $OUT/w/tiff.txt   # plain libtiff does not know the GeoTIFF tags
      [ -s $OUT/w/tiff.txt ] && msg="libtiff: $(head -1 $OUT/w/tiff.txt)"
      d=$(python3 -c "a=[float(v) for v in '$sgt'.split()]; b=[float(v) for v in '$(gdal_gt $D)'.split()]; print(max([abs(x-y)/max(1.0,abs(x)) for x,y in zip(a,b)]+[0]) if len(a)==len(b)==6 else 'missing')")
      if [ "$d" = missing ] || ! awk -v d="$d" 'BEGIN{exit !(d < 1e-12)}'; then msg="$msg geotransform differs ($d)"; fi
      [ "$(gdal_epsg $D)" = "$sepsg" ] || msg="$msg EPSG $(gdal_epsg $D) not $sepsg"
      [ "$(gdal_aop $D)" = "$saop" ] || msg="$msg $(gdal_aop $D) not $saop"
      [ "$(gdal_md5 $D $OUT/w/x.raw)" = "$smd5" ] || msg="$msg pixels differ"
    fi
    if [ -z "$msg" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf "FAIL  %-16s %-9s %s\n" $src $m "$msg"; fi
  done
  printf "      %-16s %s  %s  %s\n" $src "$sepsg" "$saop" "copied 6 ways"
done
echo "writer: $pass passed, $fail failed  ($(echo $sources | wc -w) sources x $(echo $modes | wc -w) modes)"
[ $fail = 0 ]

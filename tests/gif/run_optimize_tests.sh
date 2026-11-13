#!/bin/bash
# Optimizer tests: optimize every test GIF and the WinFli samples; the result must show the same
# pictures for the same times (giftool same) and must decode in ffmpeg like the source.
# With XGT set (XGT=../../xojo/xgt.sh), the Xojo GIFOptimizer must write the same bytes as the C one.
set -u
cd "$(dirname "$0")"
OUT=out/opt; mkdir -p $OUT
GT=../../c/giftool
XGT=${XGT:-}
pass=0; fail=0
[ -d out/src ] || python3 make_gifs.py out/src >/dev/null
for f in out/src/*.gif ../../../winfli/SampleAnimations/gif/*.gif; do
  [ -f "$f" ] || continue
  n=$(basename "$f" .gif); msg=""
  if ! $GT optimize-raw "$f" $OUT/$n.gif 2>$OUT/$n.err; then
    if grep -q "more than 255 colours" $OUT/$n.err; then printf "SKIP  %-36s %s\n" $n "$(cat $OUT/$n.err)"; continue; fi
    msg="optimize failed: $(cat $OUT/$n.err)"
  else
    same=$($GT same "$f" $OUT/$n.gif) || msg="$msg $same;"
    if [[ $n != winfli* ]]; then
      ffmpeg -v error -y -i "$f" -fps_mode passthrough -f rawvideo -pix_fmt rgba $OUT/$n.a.raw 2>/dev/null
      ffmpeg -v error -y -i $OUT/$n.gif -fps_mode passthrough -f rawvideo -pix_fmt rgba $OUT/$n.b.raw 2>/dev/null
      # ffmpeg shows every stored frame; merged frames make the counts differ, so compare the last picture
      fs=$(python3 -c "import sys;from PIL import Image;im=Image.open(sys.argv[1]);print(im.size[0]*im.size[1]*4)" "$f")
      cmp -s <(tail -c $fs $OUT/$n.a.raw) <(tail -c $fs $OUT/$n.b.raw) || msg="$msg ffmpeg's last picture differs;"
    fi
    if [ -n "$XGT" ]; then
      if $XGT gif optimize-raw "$f" $OUT/$n.x.gif 2>$OUT/$n.xerr; then
        cmp -s $OUT/$n.gif $OUT/$n.x.gif || msg="$msg Xojo output differs from C;"
      else msg="$msg Xojo optimize failed: $(cat $OUT/$n.xerr);"; fi
    fi
  fi
  a=$(stat -c %s "$f"); b=$(stat -c %s $OUT/$n.gif 2>/dev/null || echo 0)
  if [ -z "$msg" ]; then pass=$((pass+1)); printf "PASS  %-36s %8d -> %8d bytes%s\n" $n $a $b "${XGT:+, Xojo bytes identical}"
  else fail=$((fail+1)); printf "FAIL  %-36s %s\n" $n "$msg"; fi
done
echo "optimize: $pass passed, $fail failed"
[ $fail = 0 ]

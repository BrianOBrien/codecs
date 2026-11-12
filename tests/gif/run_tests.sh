#!/bin/bash
# GIF tests: decode test GIFs with giftool (or the Xojo build) and compare every rendered frame with
# ffmpeg's and Pillow's; then copy each with our writer and check ffmpeg decodes the copy the same.
set -u
cd "$(dirname "$0")"
OUT=out; mkdir -p $OUT
GT=${GT:-../../c/giftool}        # GT="../../xojo/xgt.sh gif" tests the Xojo port
pass=0; fail=0

python3 make_gifs.py $OUT/src >/dev/null
# a GIF made by ffmpeg's own encoder (palette per frame and frame differencing)
ffmpeg -v error -y -f lavfi -i "testsrc2=size=160x120:rate=10:duration=2" -vf "split[a][b];[a]palettegen[p];[b][p]paletteuse" $OUT/src/ffmpeg_made.gif

compare() {  # a.raw b.raw width height -> number of differing pixels (transparent counts as equal)
  python3 - "$@" <<'PY'
import sys
a=open(sys.argv[1],'rb').read(); b=open(sys.argv[2],'rb').read()
if len(a)!=len(b): print('size', len(a), len(b)); sys.exit()
bad=0
for i in range(0,len(a),4):
    if a[i+3]==0 and b[i+3]==0: continue
    if a[i:i+4]!=b[i:i+4]: bad+=1
print(bad)
PY
}
pillow_rgba() {  # file out.raw: every frame composited by Pillow, RGBA
  python3 -c "
import sys; from PIL import Image, ImageSequence
im=Image.open(sys.argv[1]); o=open(sys.argv[2],'wb')
for f in ImageSequence.Iterator(im): o.write(f.convert('RGBA').tobytes())" "$1" "$2"
}
ffmpeg_rgba() { ffmpeg -v error -y -i "$1" -fps_mode passthrough -f rawvideo -pix_fmt rgba "$2"; }

for f in $OUT/src/*.gif; do
  n=$(basename $f .gif); msg=""
  if ! $GT -rgba $OUT/$n.ours.raw $f 2>$OUT/$n.err; then msg="decode failed: $(cat $OUT/$n.err)"
  else
    ffmpeg_rgba $f $OUT/$n.ff.raw;  dff=$(compare $OUT/$n.ours.raw $OUT/$n.ff.raw)
    pillow_rgba $f $OUT/$n.pil.raw; dpil=$(compare $OUT/$n.ours.raw $OUT/$n.pil.raw)
    [ "$dff" = 0 ] || msg="$msg vs ffmpeg: $dff px differ;"
    [ "$dpil" = 0 ] || msg="$msg vs Pillow: $dpil px differ;"
    # writer: our copy must decode (in ffmpeg) exactly like the source
    if $GT copy $f $OUT/$n.copy.gif 2>$OUT/$n.err; then
      ffmpeg_rgba $OUT/$n.copy.gif $OUT/$n.copyff.raw
      dc=$(compare $OUT/$n.ff.raw $OUT/$n.copyff.raw)
      [ "$dc" = 0 ] || msg="$msg copy decodes differently: $dc px;"
    else msg="$msg copy failed: $(cat $OUT/$n.err)"; fi
  fi
  frames=$(python3 -c "from PIL import Image; print(getattr(Image.open('$f'),'n_frames',1))")
  if [ -z "$msg" ]; then pass=$((pass+1)); printf "PASS  %-16s %2s frame(s): ffmpeg and Pillow agree pixel for pixel; copy decodes the same\n" $n $frames
  else fail=$((fail+1)); printf "FAIL  %-16s %s\n" $n "$msg"; fi
done
# Damaged files: cut short and corrupted copies must give an error or a partial picture, never a crash
crash=0; tried=0
for f in $OUT/src/*.gif; do
  sz=$(stat -c %s $f)
  for cut in 6 13 40 $((sz/3)) $((sz/2)) $((sz-3)); do
    head -c $cut $f > $OUT/damaged.gif; tried=$((tried+1))
    $GT -rgba $OUT/damaged.raw $OUT/damaged.gif >$OUT/damaged.err 2>&1; rc=$?
    if [ $rc -ge 128 ] || grep -qi exception $OUT/damaged.err; then crash=$((crash+1)); echo "CRASH  $(basename $f) cut at $cut (exit $rc)"; fi
  done
  for seed in 1 2 3 4; do
    python3 -c "import random; random.seed($seed); b=bytearray(open('$f','rb').read()); [b.__setitem__(random.randrange(6,len(b)), random.randrange(256)) for _ in range(30)]; open('$OUT/damaged.gif','wb').write(b)"
    tried=$((tried+1))
    $GT -rgba $OUT/damaged.raw $OUT/damaged.gif >$OUT/damaged.err 2>&1; rc=$?
    if [ $rc -ge 128 ] || grep -qi exception $OUT/damaged.err; then crash=$((crash+1)); echo "CRASH  $(basename $f) corrupted, seed $seed (exit $rc)"; fi
  done
done
if [ $crash = 0 ]; then pass=$((pass+1)); echo "PASS  damaged files: $tried cut-short or corrupted copies, no crash or exception"
else fail=$((fail+1)); echo "FAIL  damaged files: $crash of $tried crashed"; fi

echo "gif: $pass passed, $fail failed"
[ $fail = 0 ]

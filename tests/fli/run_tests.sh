#!/bin/bash
# FLI/FLC tests:
#  - real FLI/FLC files (tests/fli/corpus, copied from the WD; not in git): every frame we decode must
#    equal ffmpeg's flic decoder, pixel for pixel;
#  - our writer: each real file copied as an FLC, and generated patterns of awkward sizes, must decode
#    in ffmpeg exactly like the source (and read back the same in our reader).
set -u
cd "$(dirname "$0")"
OUT=out; mkdir -p $OUT/src
FT=${FT:-../../c/flitool}        # FT="../../xojo/xgt.sh fli" tests the Xojo port
WD=/mnt/wdmycloud/Pegasys/VolumeDData
pass=0; fail=0

if [ ! -d corpus ] || [ -z "$(ls corpus 2>/dev/null)" ]; then   # fetch the real files from the WD
  mkdir -p corpus
  cp $WD/Multimedia/fli/* $WD/3DS3/FLICS/* $WD/3DS3/MAPS/LRTRAN.FLC $WD/3DS3/IMAGES/GALTITLE.FLC corpus/ 2>/dev/null
fi
cp corpus/* $OUT/src/ 2>/dev/null
$FT pattern $OUT/src/pattern_641x203.flc 641 203 12      # odd width, wider than 255 packets of words
$FT pattern $OUT/src/pattern_640x203.flc 640 203 12      # even width: SS2 on long, busy lines
$FT pattern $OUT/src/pattern_1x1.flc 1 1 4               # smallest
$FT pattern $OUT/src/pattern_2x300.flc 2 300 6           # one word per line

nframes() { $FT "$1" | sed -n 's/.* \([0-9]*\) frame(s).*/\1/p'; }
ffmpeg_rgba() { ffmpeg -v error -y -i "$1" -fps_mode passthrough -f rawvideo -pix_fmt rgba "$2"; }
compare_frames() {  # ours.raw ff.raw width height nframes -> differing pixels in the first nframes
  python3 - "$@" <<'PY'
import sys
a=open(sys.argv[1],'rb').read(); b=open(sys.argv[2],'rb').read()
n=int(sys.argv[3])*int(sys.argv[4])*4*int(sys.argv[5])
if len(a)<n or len(b)<n: print('short', len(a)//(n//int(sys.argv[5])), len(b)//(n//int(sys.argv[5]))); sys.exit()
print(sum(1 for i in range(0,n,4) if a[i:i+3]!=b[i:i+3]))
PY
}

for f in $OUT/src/*; do
  n=$(basename $f); msg=""; note=""
  size=$($FT $f | sed -n 's/^Size: \([0-9]*\) x \([0-9]*\).*/\1 \2/p'); fr=$(nframes $f)
  if [ -z "$fr" ] || ! $FT -rgba $OUT/$n.ours.raw $f 2>$OUT/$n.err; then msg="decode failed: $(cat $OUT/$n.err)"
  else
    if ffmpeg_rgba $f $OUT/$n.ff.raw 2>/dev/null; then
      d=$(compare_frames $OUT/$n.ours.raw $OUT/$n.ff.raw $size $fr); [ "$d" = 0 ] || msg="$msg vs ffmpeg: $d px differ;"
    else   # ffmpeg cannot open it (PREVIEW.FLC has a depth of 347): judge our copy against our own decode
      cp $OUT/$n.ours.raw $OUT/$n.ff.raw; note="(ffmpeg refuses the source; copy checked against our decode)"
    fi
    if $FT copy $f $OUT/$n.copy.flc 2>$OUT/$n.err; then
      ffmpeg_rgba $OUT/$n.copy.flc $OUT/$n.copyff.raw
      d=$(compare_frames $OUT/$n.ff.raw $OUT/$n.copyff.raw $size $fr); [ "$d" = 0 ] || msg="$msg our FLC copy decodes differently in ffmpeg: $d px;"
      $FT -rgba $OUT/$n.copyours.raw $OUT/$n.copy.flc
      d=$(compare_frames $OUT/$n.ours.raw $OUT/$n.copyours.raw $size $fr); [ "$d" = 0 ] || msg="$msg reads back differently: $d px;"
    else msg="$msg copy failed: $(cat $OUT/$n.err)"; fi
  fi
  if [ -z "$msg" ]; then pass=$((pass+1)); printf "PASS  %-22s %4s frames: equals ffmpeg; FLC copy decodes the same %s\n" $n $fr "$note"
  else fail=$((fail+1)); printf "FAIL  %-22s %s\n" $n "$msg"; fi
done
# Damaged files: cut short and corrupted copies must give an error or partial frames, never a crash
crash=0; tried=0
for f in $OUT/src/*; do
  sz=$(stat -c %s $f)
  for cut in 10 128 140 $((sz/3)) $((sz/2)) $((sz-5)); do
    head -c $cut $f > $OUT/damaged.fli; tried=$((tried+1))
    $FT -rgba $OUT/damaged.raw $OUT/damaged.fli >$OUT/damaged.err 2>&1; rc=$?
    if [ $rc -ge 128 ] || grep -qi exception $OUT/damaged.err; then crash=$((crash+1)); echo "CRASH  $(basename $f) cut at $cut (exit $rc)"; fi
  done
  for seed in 1 2 3 4; do
    python3 -c "import random; random.seed($seed); b=bytearray(open('$f','rb').read()); [b.__setitem__(random.randrange(4,len(b)), random.randrange(256)) for _ in range(30)]; open('$OUT/damaged.fli','wb').write(b)"
    tried=$((tried+1))
    $FT -rgba $OUT/damaged.raw $OUT/damaged.fli >$OUT/damaged.err 2>&1; rc=$?
    if [ $rc -ge 128 ] || grep -qi exception $OUT/damaged.err; then crash=$((crash+1)); echo "CRASH  $(basename $f) corrupted, seed $seed (exit $rc)"; fi
  done
done
if [ $crash = 0 ]; then pass=$((pass+1)); echo "PASS  damaged files: $tried cut-short or corrupted copies, no crash or exception"
else fail=$((fail+1)); echo "FAIL  damaged files: $crash of $tried crashed"; fi

echo "fli: $pass passed, $fail failed"
[ $fail = 0 ]

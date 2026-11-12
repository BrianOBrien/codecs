#!/bin/bash
# xojo-build.sh [project] [program it makes]: open the project in the Xojo IDE (display: the Mac XQuartz), build it through the IDE scripting socket, report BUILT or FAILED (+ error screenshot)
export DISPLAY=192.168.1.11:0
X="$(dirname "$(readlink -f "$0")")/xojoipc.py"
PROJ=${1:-/home/brian/dev/FlightOverview/FlightOverview.xojo_project}   # build.sh [project] [program it makes]
B=${2:-"/home/brian/dev/FlightOverview/Builds - FlightOverview/Linux ARM64/FlightOverview/FlightOverview"}
SHOT=${SHOT:-/tmp/xojo-build-errors.png}
closeide(){ python3 $X 'CloseProject(False)' 15 >/dev/null 2>&1; sleep 3
  if pgrep -x Xojo >/dev/null && ! xwininfo -root -tree | grep -q '"Xojo - \[[^]]*\*\]'; then kill $(pgrep -x Xojo); fi; }
# Always build from the files on disk: close any open Xojo first (refuse if it has unsaved changes)
if pgrep -x Xojo >/dev/null; then
  if xwininfo -root -tree | grep -q '"Xojo - \[[^]]*\*\]'; then echo "Xojo has unsaved changes: not closing it"; exit 1; fi
  python3 $X 'CloseProject(False)' 15 >/dev/null 2>&1
  for i in $(seq 1 10); do pgrep -x Xojo >/dev/null || break; sleep 1; done
  pkill -x Xojo; sleep 2
fi
if ! pgrep -x Xojo >/dev/null; then
  (cd /opt/xojo2026r3.1_arm64 && setsid ./Xojo "$PROJ" >/dev/null 2>&1 &)
fi
until xwininfo -root -tree 2>/dev/null | grep -q -e '"Xojo - \[' -e '"Missing'; do sleep 2; done; sleep 6
if xwininfo -root -tree | grep -q '"Missing'; then echo "LOAD FAILED (Missing Files)"; exit 1; fi
until [ -S /tmp/XojoIDE ] && ss -xl | grep -q /tmp/XojoIDE; do sleep 2; done; sleep 3   # scripting socket ready
before=$(stat -c %Y "$B" 2>/dev/null || echo 0)
python3 $X 'DoCommand("BuildApp")' 150 >/dev/null
for i in $(seq 1 40); do now=$(stat -c %Y "$B" 2>/dev/null || echo 0); [ "$now" != "$before" ] && [ "$now" != 0 ] && break; sleep 3; done
pkill -f 'pcmanfm /home/brian/dev/[F]lightOverview/Builds|pcmanfm /home/brian/dev/[g]eotiff/xojo/Builds'
now=$(stat -c %Y "$B" 2>/dev/null || echo 0)
if [ "$now" != "$before" ] && [ "$now" != 0 ]; then echo BUILT; closeide; exit 0; fi
W=$(xwininfo -root -tree | grep '"Xojo - \[' | awk '{print $1}' | head -1)
xwd -id $W -silent | convert xwd:- -crop 1000x330+0+476 "$SHOT"; echo "FAILED: see $SHOT"; exit 1

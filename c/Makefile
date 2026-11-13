CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c99

all: gtinfo gtcopy giftool flitool

gtinfo: gtinfo.c geotiff.c lzw.c inflate.c geotiff.h lzw.h inflate.h tiff.h
	$(CC) $(CFLAGS) -o $@ gtinfo.c geotiff.c lzw.c inflate.c

gtcopy: gtcopy.c geotiff.c gtwrite.c lzw.c inflate.c geotiff.h lzw.h inflate.h tiff.h
	$(CC) $(CFLAGS) -o $@ gtcopy.c geotiff.c gtwrite.c lzw.c inflate.c

giftool: giftool.c gif.c lzw.c gif.h lzw.h
	$(CC) $(CFLAGS) -o $@ giftool.c gif.c lzw.c

flitool: flitool.c fli.c fli.h
	$(CC) $(CFLAGS) -o $@ flitool.c fli.c

test: gtinfo gtcopy giftool flitool
	cd ../tests/geotiff && ./run_tests.sh && ./run_write_tests.sh
	cd ../tests/gif && ./run_tests.sh
	cd ../tests/fli && ./run_tests.sh

# The Xojo port: build with the Xojo IDE (xojo/build.sh), then run the same tests on it
test-xojo: gtinfo gtcopy
	cd ../tests/geotiff && GT=../../xojo/xgt.sh ./run_tests.sh && CP="../../xojo/xgt.sh copy" ./run_write_tests.sh
	cd ../tests/gif && GT="../../xojo/xgt.sh gif" ./run_tests.sh
	cd ../tests/fli && FT="../../xojo/xgt.sh fli" ./run_tests.sh

clean:
	rm -f gtinfo gtcopy giftool flitool
	rm -rf ../tests/geotiff/out

.PHONY: all test test-xojo clean

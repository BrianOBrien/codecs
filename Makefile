CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c99

all: gtinfo gtcopy

gtinfo: gtinfo.c geotiff.c lzw.c inflate.c geotiff.h lzw.h inflate.h tiff.h
	$(CC) $(CFLAGS) -o $@ gtinfo.c geotiff.c lzw.c inflate.c

gtcopy: gtcopy.c geotiff.c gtwrite.c lzw.c inflate.c geotiff.h lzw.h inflate.h tiff.h
	$(CC) $(CFLAGS) -o $@ gtcopy.c geotiff.c gtwrite.c lzw.c inflate.c

test: gtinfo gtcopy
	./tests/run_tests.sh && ./tests/run_write_tests.sh

# The Xojo port: build with the Xojo IDE (xojo/build.sh), then run the same tests on it
test-xojo: gtinfo gtcopy
	GT=../xojo/xgt.sh ./tests/run_tests.sh && CP="../xojo/xgt.sh copy" ./tests/run_write_tests.sh

clean:
	rm -f gtinfo gtcopy
	rm -rf tests/out

.PHONY: all test test-xojo clean

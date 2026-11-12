CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c99

all: gtinfo

gtinfo: gtinfo.c geotiff.c lzw.c inflate.c geotiff.h lzw.h inflate.h tiff.h
	$(CC) $(CFLAGS) -o $@ gtinfo.c geotiff.c lzw.c inflate.c

test: gtinfo
	./tests/run_tests.sh

clean:
	rm -f gtinfo
	rm -rf tests/out

.PHONY: all test clean

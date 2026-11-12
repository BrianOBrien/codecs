# codecs: C reference codecs in c/, their Xojo ports in xojo/, shared tests in tests/
all:
	$(MAKE) -C c

test: all
	$(MAKE) -C c test

# build the Xojo test app first: tools/build-xgt.sh (needs the Xojo IDE)
test-xojo: all
	$(MAKE) -C c test-xojo

clean:
	$(MAKE) -C c clean

.PHONY: all test test-xojo clean

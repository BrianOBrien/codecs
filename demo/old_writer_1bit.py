# Reproduce what Brian's 1998 Writegif did with a binary (2-colour) image: bpp = 1, so the
# LZW minimum code size written to the file is 1 (GIF needs at least 2). The LZW itself is a
# faithful copy of lzw::write / bitstream::write (sub-blocks included). The palette bug is left
# out here (the table is written correctly) so only the code-size problem shows.
import sys, struct
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('L').point(lambda v: 255 if v > 110 else 0).convert('1')
w, h = im.size
pix = [1 if p else 0 for p in im.getdata()]
bpp = 1
clear = 1 << bpp; eof = clear + 1
table = {}; nEntries = clear + 2; codeSize = bpp + 1
bits = acc = 0; data = bytearray()
def put(code):
    global codeSize, acc, bits
    if nEntries > (1 << codeSize): codeSize += 1
    acc |= code << bits; bits += codeSize
    while bits >= 8:
        data.append(acc & 255); acc >>= 8; bits -= 8
put(clear)
prefix = -1
for c in pix:
    if prefix == -1: prefix = c; continue
    if (prefix, c) in table: prefix = table[(prefix, c)]; continue
    put(prefix)
    if nEntries == 4096:
        put(clear); table = {}; nEntries = clear + 2; codeSize = bpp + 1
    else:
        table[(prefix, c)] = nEntries; nEntries += 1
    prefix = c
put(prefix); put(eof)
if bits: data.append(acc & 255)
blocks = bytearray()
for i in range(0, len(data), 255):
    blocks += bytes([len(data[i:i+255])]) + data[i:i+255]
gif = (b'GIF89a' + struct.pack('<HHBBB', w, h, 0x80 | 0x70 | (bpp - 1), 0, 0) + bytes([0, 0, 0, 255, 255, 255])
       + b'\x2c' + struct.pack('<HHHHB', 0, 0, w, h, 0) + bytes([bpp]) + blocks + b'\x00\x3b')
open(out, 'wb').write(gif)
print('wrote', out, w, 'x', h, 'LZW code size', bpp)

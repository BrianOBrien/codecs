# Make test GIFs with Pillow (and the map from FlightOverview). Run from tests/gif.
import os, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
base = Image.open('../geotiff/map.png').convert('RGB')

base.quantize(256).save(f'{out}/still256.gif')                       # big frame: LZW clears
base.quantize(16).save(f'{out}/still16.gif')
base.quantize(4).save(f'{out}/still4.gif')
base.quantize(2).save(f'{out}/still2.gif')

def true_1bit(path, w, h):
    # A real 1-bit GIF (2-entry colour table, LZW code size 2) written by hand: Pillow never
    # writes tables under 4 entries. Codes stay 3 bits wide by sending Clear before every pair.
    import struct
    pix = [1 if ((x // 9) + (y // 7)) % 2 or (x * y) % 11 == 0 else 0 for y in range(h) for x in range(w)]
    codes = []
    for i in range(0, len(pix), 2):
        codes += [4] + pix[i:i + 2]          # Clear (4), then up to two roots
    codes.append(5)                          # EndOfInformation
    bits = acc = 0; data = bytearray()
    for c in codes:                          # least significant bit first, 3 bits each
        acc |= c << bits; bits += 3
        while bits >= 8:
            data.append(acc & 255); acc >>= 8; bits -= 8
    if bits: data.append(acc & 255)
    blocks = bytearray()
    for i in range(0, len(data), 255):
        blocks += bytes([len(data[i:i + 255])]) + data[i:i + 255]
    gif = (b'GIF89a' + struct.pack('<HHBBB', w, h, 0x80, 0, 0) + bytes([10, 30, 60, 250, 220, 120])
           + b'\x2c' + struct.pack('<HHHHB', 0, 0, w, h, 0) + bytes([2]) + blocks + b'\x00\x3b')
    open(path, 'wb').write(gif)
true_1bit(f'{out}/onebit.gif', 61, 43)                                # 2 colours: code size 2
import subprocess
subprocess.run([sys.executable, '../../demo/old_writer_1bit.py', '../geotiff/map.png', f'{out}/winfli98_1bit.gif'], check=True, capture_output=True)   # WinFLI's code size 1
base.quantize(64).save(f'{out}/interlaced.gif', interlace=True)
base.resize((7, 5)).quantize(8).save(f'{out}/tiny.gif')               # odd sizes, short data

# animation: a dot moving over the map, one global palette, loop forever
pal_src = base.quantize(200)
frames = []
for i in range(12):
    im = base.copy()
    d = ImageDraw.Draw(im)
    x = 40 + i * 35
    d.ellipse([x, 200, x + 40, 240], fill=(255, 40, 40))
    frames.append(im.quantize(palette=pal_src))
frames[0].save(f'{out}/anim_global.gif', save_all=True, append_images=frames[1:], duration=80, loop=0)

# animation with a different palette per frame (Pillow writes local colour tables)
frames = [base.rotate(a).quantize(64 + 10 * k) for k, a in enumerate((0, 15, 30, 45))]
frames[0].save(f'{out}/anim_local.gif', save_all=True, append_images=frames[1:], duration=150, loop=3)

# transparency with disposal 2 (restore background) and disposal 3 (restore previous)
def sprites(disposal, name):
    fr = []
    for i in range(8):
        im = Image.new('RGBA', (120, 90), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rectangle([5 + 12 * i, 10, 35 + 12 * i, 40], fill=(30, 200, 90, 255))
        d.ellipse([60, 40 + 3 * i, 90, 70 + 3 * i], fill=(240, 220, 20, 255))
        fr.append(im)
    fr[0].save(f'{out}/{name}.gif', save_all=True, append_images=fr[1:], duration=100, loop=0,
               disposal=disposal, transparency=0, optimize=False)
sprites(2, 'transp_dispose2')
sprites(3, 'transp_dispose3')
sprites(1, 'transp_dispose1')
print('made', len(os.listdir(out)), 'GIFs')

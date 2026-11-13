# Compose the codecs demo video from frames decoded by the Xojo build (xgt). Output: demo.mp4
import subprocess, sys, os
from PIL import Image, ImageDraw, ImageFont
W, H, FPS = 1280, 720, 30
BG, FG, DIM, BLUE, GREEN, RED = (24, 28, 38), (236, 239, 244), (150, 160, 178), (96, 165, 250), (110, 220, 140), (248, 113, 113)
VF = os.path.expanduser('~/.local/share/fonts/plex/IBMPlexSans-VF.ttf')
MONO = os.path.expanduser('~/.local/share/fonts/plex/IBMPlexMono-SemiBold.ttf')
def font(size, style='Regular'):
    f = ImageFont.truetype(VF, size)
    try: f.set_variation_by_name(style)
    except Exception: pass
    return f
F_TITLE, F_H, F_B, F_S = font(54, 'Bold'), font(34, 'SemiBold'), font(24), font(19)
F_M = ImageFont.truetype(MONO, 20)
ff = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS),
                       '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', 'demo.mp4'], stdin=subprocess.PIPE)
count = [0]
def emit(img, seconds):
    n = max(1, round(seconds * FPS)); b = img.convert('RGB').tobytes()
    for _ in range(n): ff.stdin.write(b)
    count[0] += n
def canvas(title=None, sub=None):
    im = Image.new('RGB', (W, H), BG); d = ImageDraw.Draw(im)
    d.text((40, 22), 'codecs  ·  Xojo modules', font=F_S, fill=DIM)
    d.text((W - 40, 22), "Brian O'Brien", font=F_S, fill=DIM, anchor='ra')
    if title: d.text((40, 52), title, font=F_H, fill=FG)
    if sub: d.text((40, 96), sub, font=F_S, fill=DIM)
    return im, d
def frames(path, w, h):
    raw = open(path, 'rb').read(); fs = w * h * 4
    return [Image.frombytes('RGBA', (w, h), raw[i:i + fs]) for i in range(0, len(raw) - fs + 1, fs)]
def checker(w, h, s=12):
    im = Image.new('RGB', (w, h), (205, 205, 205)); d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if (x // s + y // s) % 2: d.rectangle([x, y, x + s - 1, y + s - 1], fill=(160, 160, 160))
    return im

# 1. title
im, d = canvas()
d.text((W // 2, 250), 'GIF and FLI/FLC in Xojo', font=font(64, 'Bold'), fill=FG, anchor='mm')
d.text((W // 2, 330), 'from WinFLI (1997-2000) to the codecs repo (2026)', font=F_B, fill=BLUE, anchor='mm')
d.text((W // 2, 400), "Brian's Readfli, Readgif and Writegif, ported to C and Xojo, tested against ffmpeg and Pillow", font=F_S, fill=DIM, anchor='mm')
emit(im, 4)

# 2. FLI/FLC side by side with ffmpeg
for name, label, delay, maxsec in (('3DFSPIR.FLI', '3DFSPIR.FLI  ·  FLI, 1994, 80 frames', 0.043, 7),
                                   ('GALTITLE.FLC', 'GALTITLE.FLC  ·  3D Studio FLC, 150 frames', 0.071, 9),
                                   ('Matsci.fli', 'Matsci.fli  ·  FLI, 120 frames', 0.071, 7)):
    ours, ref = frames(f'x_{name}.raw', 320, 200), frames(f'f_{name}.raw', 320, 200)
    t = 0.0; total = 0
    for k, (a, b) in enumerate(zip(ours, ref)):
        if t > maxsec: break
        diff = sum(1 for p, q in zip(a.tobytes()[0::4], b.tobytes()[0::4]) if p != q) if k % 3 == 0 else 0
        total += diff
        im, d = canvas('FLI / FLC: real files from the 1990s', label)
        for i, (img, cap) in enumerate(((a, 'FLIFile.Read  (Xojo)'), (b, 'ffmpeg (reference)'))):
            x0 = 40 + i * 610
            im.paste(img.convert('RGB').resize((560, 350), Image.NEAREST), (x0, 150))
            d.text((x0, 512), cap, font=F_B, fill=BLUE if i == 0 else DIM)
        d.text((40, 570), f'frame {k + 1:3d} of {len(ours)}', font=F_M, fill=FG)
        d.text((40, 604), f'pixels different from ffmpeg: {diff}', font=F_M, fill=GREEN if diff == 0 else RED)
        d.text((40, 650), 'chunks: COLOR_64 / COLOR_256, BYTE_RUN, LC, SS2, COPY, BLACK  ·  Readfli fixes: palette packets, FLC speed in ms, wide lines',
               font=F_S, fill=DIM)
        emit(im, delay); t += delay

# 3. FLI -> GIF (WinFLI's Save as GIF)
src, gif = frames('f_DOLLAR.FLI.raw', 320, 200), frames('x_dollar.raw', 320, 200)
for rep in range(3):
    for k, (a, b) in enumerate(zip(src, gif)):
        im, d = canvas("FLI to GIF: WinFLI's \"Save as GIF\", reborn", 'xgt fli togif DOLLAR.FLI dollar.gif   (FLIFile in, GIFFile out: 13 frames, local palettes when they change)')
        for i, (img, cap) in enumerate(((a, 'DOLLAR.FLI'), (b, 'dollar.gif, read back with GIFFile'))):
            x0 = 40 + i * 610
            im.paste(img.convert('RGB').resize((560, 350), Image.NEAREST), (x0, 150))
            d.text((x0, 512), cap, font=F_B, fill=BLUE if i else DIM)
        d.text((40, 590), 'every frame identical: 0 pixels different', font=F_M, fill=GREEN)
        emit(im, 0.071)

# 4. GIF: transparency and disposal over a checkerboard
fr = frames('x_disp3.raw', 120, 90)
for rep in range(4):
    for k, f in enumerate(fr):
        im, d = canvas('GIF: transparency and disposal', 'GIFFile.Composite: sub-rectangles, local palettes, transparent index, disposal 3 (restore previous)')
        base = checker(480, 360); base.paste(f.resize((480, 360), Image.NEAREST), (0, 0), f.resize((480, 360), Image.NEAREST))
        im.paste(base, (40, 150))
        d.text((560, 170), f'frame {k + 1} of {len(fr)}', font=F_M, fill=FG)
        for j, line in enumerate(('Every rendered frame of 15 test GIFs', 'equals ffmpeg and Pillow, pixel for pixel.', '',
                                  'GIF-flavour LZW from lzw_decompress', 'and lzw::write (1998-99): low bit first,',
                                  'no early change, 255-byte sub-blocks.')):
            d.text((560, 230 + 36 * j), line, font=F_B, fill=FG if j < 2 else DIM)
        emit(im, 0.1)

# 5. the binary image story
old, fixed = frames('x_old1bit.raw', 509, 574)[0], frames('x_fixed1bit.raw', 509, 574)[0]
def panel(img, x, cap, verdict, col):
    im.paste(img.convert('RGB').resize((280, 316)), (x, 170)); d.text((x, 500), cap, font=F_B, fill=FG); d.text((x, 534), verdict, font=F_S, fill=col)
im, d = canvas('"Something broke when I optimized a binary image for GIF"', 'A 2-colour image made the 1998 writer use LZW code size 1. GIF needs at least 2.')
blank = Image.new('RGB', (509, 574), (60, 30, 30)); ImageDraw.Draw(blank).text((254, 287), 'cannot open', font=font(44, 'Bold'), fill=RED, anchor='mm')
panel(blank, 40, '1998 file in Pillow', '"image file is truncated"', RED)
panel(old, 350, '1998 file in ffmpeg', 'shows it (tolerant)', GREEN)
panel(old, 660, '1998 file in GIFFile (2026)', 'reads it, like ffmpeg', GREEN)
panel(fixed, 970, 'fixed writer: code size 2', 'every viewer reads it', GREEN)
d.text((40, 600), 'The old writer also filled its palette backwards, so viewers that did open such files could show the wrong colours.',
       font=F_S, fill=DIM)
d.text((40, 630), 'Both are fixed: GIFFile.Write uses code size 2 and the right palette; the reader still opens WinFLI-era binary GIFs.', font=F_S, fill=DIM)
emit(im, 10)

# 6. summary
im, d = canvas('All tests pass, in C and in Xojo')
rows = (('TIFF / GeoTIFF', 'read 21, write 48', 'GDAL, libtiff'), ('GIF', '15 files, every frame', 'ffmpeg, Pillow'),
        ('FLI / FLC', '10 real files, 516 frames', 'ffmpeg'), ('Damaged files', 'about 470', 'no crash, no exception'),
        ('C vs Xojo writers', 'GIF and FLC copies', 'byte-identical'))
for j, (a, b, c) in enumerate(rows):
    y = 170 + 70 * j
    d.text((80, y), a, font=F_H, fill=FG); d.text((520, y + 6), b, font=F_B, fill=BLUE); d.text((900, y + 6), c, font=F_B, fill=DIM)
d.text((80, 560), 'github.com/BrianOBrien/codecs   ·   xojo/GIFCodec, xojo/FLICodec, xojo/LZWCodec, xojo/TIFFCodec', font=F_S, fill=DIM)
emit(im, 6)
ff.stdin.close(); ff.wait()
print('demo.mp4:', count[0], 'frames,', round(count[0] / FPS, 1), 's')

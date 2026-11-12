/*
 * flitool - look inside an FLI/FLC, render its frames, copy it as an FLC.
 *
 *   flitool file.fli                  summary
 *   flitool -rgba out.raw file.fli    every frame as RGBA (alpha 255), one after another
 *   flitool copy in.fli out.flc       read, then write as FLC with our writer
 *   flitool pattern out.flc W H N     write a test FLC of any size: moving shapes, noise, a palette
 *                                     that changes every 5th frame (odd widths exercise SS2's last byte)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fli.h"

int main(int argc, char *argv[])
{
    char err[200];
    FLIFile *f;
    int i;

    if (argc == 4 && !strcmp(argv[1], "copy"))
    {
        f = fli_read(argv[2], err, sizeof err);
        if (!f)
        {
            fprintf(stderr, "flitool: %s: %s\n", argv[2], err);
            return 1;
        }
        if (!fli_write_flc(argv[3], f, err, sizeof err))
        {
            fprintf(stderr, "flitool: %s: %s\n", argv[3], err);
            fli_free(f);
            return 1;
        }
        fli_free(f);
        return 0;
    }
    if (argc == 6 && !strcmp(argv[1], "pattern"))
    {
        FLIFile p;
        int w = atoi(argv[3]), h = atoi(argv[4]), n = atoi(argv[5]), x, y, k;
        unsigned seed = 12345;
        memset(&p, 0, sizeof p);
        p.type = FLC_MAGIC;
        p.width = w;
        p.height = h;
        p.delayMs = 50;
        p.nFrames = n;
        p.frames = calloc(n, sizeof(FLIFrame));
        for (i = 0; i < n; ++i)
        {
            uint8_t *px = p.frames[i].pixels = malloc((size_t) w * h);
            for (k = 0; k < 256; ++k)            /* palette: changes every 5th frame */
            {
                p.frames[i].palette[3 * k] = (uint8_t) (k + 40 * (i / 5));
                p.frames[i].palette[3 * k + 1] = (uint8_t) (255 - k);
                p.frames[i].palette[3 * k + 2] = (uint8_t) (k * 7 + i / 5);
            }
            for (y = 0; y < h; ++y)
                for (x = 0; x < w; ++x)
                {
                    int v = (x / 16 + y / 16) & 1 ? 10 : 200;            /* checkerboard: long runs */
                    if (x > 5 + 7 * i && x < 60 + 7 * i && y > 20 && y < 90)
                        v = 100 + (x + y) % 3;                            /* a moving block */
                    if (y == h / 2 && (x * 31 + i) % 5 == 0)
                        v = (x * 13 + i) & 255;                           /* a busy line: many packets */
                    if (x == w - 1 && (y + i) % 4 == 0)
                        v = i & 255;                                      /* the last column changes */
                    px[(size_t) y * w + x] = (uint8_t) v;
                }
            for (k = 0; k < 40; ++k)                                      /* scattered single pixels */
            {
                seed = seed * 1103515245u + 12345u;
                px[(seed >> 8) % ((unsigned) w * h)] = (uint8_t) (seed >> 24);
            }
        }
        if (!fli_write_flc(argv[2], &p, err, sizeof err))
        {
            fprintf(stderr, "flitool: %s: %s\n", argv[2], err);
            return 1;
        }
        for (i = 0; i < n; ++i)
            free(p.frames[i].pixels);
        free(p.frames);
        return 0;
    }
    if (argc == 4 && !strcmp(argv[1], "-rgba"))
    {
        FILE *o;
        size_t n;
        uint8_t *rgba;
        f = fli_read(argv[3], err, sizeof err);
        if (!f)
        {
            fprintf(stderr, "flitool: %s: %s\n", argv[3], err);
            return 1;
        }
        n = (size_t) f->width * f->height;
        rgba = malloc(n * 4);
        o = fopen(argv[2], "wb");
        if (!o || !rgba)
        {
            fprintf(stderr, "flitool: cannot write %s\n", argv[2]);
            free(rgba);
            fli_free(f);
            return 1;
        }
        for (i = 0; i < f->nFrames; ++i)
        {
            size_t k;
            for (k = 0; k < n; ++k)
            {
                int idx = f->frames[i].pixels[k];
                rgba[4 * k] = f->frames[i].palette[3 * idx];
                rgba[4 * k + 1] = f->frames[i].palette[3 * idx + 1];
                rgba[4 * k + 2] = f->frames[i].palette[3 * idx + 2];
                rgba[4 * k + 3] = 255;
            }
            fwrite(rgba, 4, n, o);
        }
        fclose(o);
        free(rgba);
        fli_free(f);
        return 0;
    }
    if (argc != 2)
    {
        fprintf(stderr, "usage: flitool file.fli | flitool -rgba out.raw file.fli | flitool copy in.fli out.flc\n");
        return 2;
    }
    f = fli_read(argv[1], err, sizeof err);
    if (!f)
    {
        fprintf(stderr, "flitool: %s: %s\n", argv[1], err);
        return 1;
    }
    printf("File: %s (%s)\n", argv[1], f->type == FLI_MAGIC ? "FLI" : "FLC");
    printf("Size: %d x %d, %d frame(s), %d ms per frame\n", f->width, f->height, f->nFrames, f->delayMs);
    fli_free(f);
    return 0;
}

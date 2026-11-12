/*
 * giftool - look inside a GIF, render its frames, copy it.
 *
 *   giftool file.gif                  summary: screen, palette, loop count, each frame
 *   giftool -rgba out.raw file.gif    every frame as a viewer shows it, RGBA, one after another
 *   giftool copy in.gif out.gif       read, then write again with our writer
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gif.h"

int main(int argc, char *argv[])
{
    char err[200];
    GIFFile *g;
    int i;

    if (argc == 4 && !strcmp(argv[1], "copy"))
    {
        g = gif_read(argv[2], err, sizeof err);
        if (!g)
        {
            fprintf(stderr, "giftool: %s: %s\n", argv[2], err);
            return 1;
        }
        if (!gif_write(argv[3], g, err, sizeof err))
        {
            fprintf(stderr, "giftool: %s: %s\n", argv[3], err);
            gif_free(g);
            return 1;
        }
        gif_free(g);
        return 0;
    }
    if (argc == 4 && !strcmp(argv[1], "-rgba"))
    {
        FILE *o;
        g = gif_read(argv[3], err, sizeof err);
        if (!g)
        {
            fprintf(stderr, "giftool: %s: %s\n", argv[3], err);
            return 1;
        }
        o = fopen(argv[2], "wb");
        if (!o)
        {
            fprintf(stderr, "giftool: cannot write %s\n", argv[2]);
            gif_free(g);
            return 1;
        }
        for (i = 0; i < g->nFrames; ++i)
        {
            uint8_t *c = gif_composite(g, i);
            if (!c)
                break;
            fwrite(c, 4, (size_t) g->width * g->height, o);
            free(c);
        }
        fclose(o);
        gif_free(g);
        return 0;
    }
    if (argc != 2)
    {
        fprintf(stderr, "usage: giftool file.gif | giftool -rgba out.raw file.gif | giftool copy in.gif out.gif\n");
        return 2;
    }
    g = gif_read(argv[1], err, sizeof err);
    if (!g)
    {
        fprintf(stderr, "giftool: %s: %s\n", argv[1], err);
        return 1;
    }
    printf("File: %s (GIF%s)\n", argv[1], g->version89 ? "89a" : "87a");
    printf("Screen: %d x %d, global palette %d colours, background %d, loop %d, %d frame(s)\n",
           g->width, g->height, g->ncolors, g->background, g->loopCount, g->nFrames);
    if (g->comment[0])
        printf("Comment: %s\n", g->comment);
    for (i = 0; i < g->nFrames; ++i)
    {
        const GIFFrame *f = &g->frames[i];
        printf("  frame %3d: %dx%d at (%d,%d)%s, %s, delay %d/100 s, disposal %d, transparent %d\n", i,
               f->width, f->height, f->left, f->top, f->interlaced ? " interlaced" : "",
               f->ncolors ? "local palette" : "global palette", f->delay, f->disposal, f->transparent);
    }
    gif_free(g);
    return 0;
}

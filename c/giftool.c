/*
 * giftool - look inside a GIF, render its frames, copy it.
 *
 *   giftool file.gif                  summary: screen, palette, loop count, each frame
 *   giftool -rgba out.raw file.gif    every frame as a viewer shows it, RGBA, one after another
 *   giftool copy in.gif out.gif       read, then write again with our writer
 *   giftool optimize in.gif out.gif   lossless optimize, check the result looks the same, print sizes
 *   giftool same a.gif b.gif          do two GIFs show the same pictures for the same times?
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

    if (argc == 4 && !strcmp(argv[1], "same"))
    {
        char why[200];
        GIFFile *a = gif_read(argv[2], err, sizeof err), *b;
        if (!a)
        {
            fprintf(stderr, "giftool: %s: %s\n", argv[2], err);
            return 2;
        }
        b = gif_read(argv[3], err, sizeof err);
        if (!b)
        {
            fprintf(stderr, "giftool: %s: %s\n", argv[3], err);
            gif_free(a);
            return 2;
        }
        i = gif_same_look(a, b, why, sizeof why);
        printf("%s: %s\n", i ? "same" : "DIFFERENT", why);
        gif_free(a);
        gif_free(b);
        return i ? 0 : 1;
    }
    if (argc == 4 && !strcmp(argv[1], "optimize"))
    {
        char why[200];
        GIFFile *o, *back;
        g = gif_read(argv[2], err, sizeof err);
        if (!g)
        {
            fprintf(stderr, "giftool: %s: %s\n", argv[2], err);
            return 2;
        }
        o = gif_optimize(g, err, sizeof err);
        if (!o)
        {
            fprintf(stderr, "giftool: optimize %s: %s\n", argv[2], err);
            gif_free(g);
            return 1;
        }
        if (!gif_write(argv[3], o, err, sizeof err))
        {
            fprintf(stderr, "giftool: %s: %s\n", argv[3], err);
            gif_free(g);
            gif_free(o);
            return 1;
        }
        back = gif_read(argv[3], err, sizeof err);        /* read it back and compare */
        i = back && gif_same_look(g, back, why, sizeof why);
        {
            /* never bigger: if the original is smaller (and whole), keep its bytes */
            FILE *a = fopen(argv[2], "rb"), *b = fopen(argv[3], "rb");
            long sa = -1, sb = -1;
            if (a) { fseek(a, 0, SEEK_END); sa = ftell(a); }
            if (b) { fseek(b, 0, SEEK_END); sb = ftell(b); fclose(b); }
            if (i && a && !g->truncated && sa >= 0 && sb > sa)
            {
                FILE *w = fopen(argv[3], "wb");
                char buf[65536];
                size_t k;
                rewind(a);
                while (w && (k = fread(buf, 1, sizeof buf, a)) > 0)
                    fwrite(buf, 1, k, w);
                if (w)
                    fclose(w);
                printf("kept original (optimized was %ld bytes) ", sb);
            }
            if (a)
                fclose(a);
        }
        printf("%s: %d frames -> %d frames, %s palette%s; %s: %s\n", argv[2], g->nFrames, o->nFrames,
               o->ncolors ? "global" : "local", g->truncated ? ", original was cut short (repaired)" : "",
               i ? "same" : "DIFFERENT", back ? why : err);
        gif_free(back);
        gif_free(g);
        gif_free(o);
        return i ? 0 : 1;
    }
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

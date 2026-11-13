/*
 * quant.c - colour quantizer: weighted k-means in OKLab.
 *
 * Input: the distinct colours of a picture or animation with how many pixels use each (the
 * "super palette"). Output: at most k palette colours and, for every input colour, which one it
 * becomes. Rare colours fold into their neighbours; colours many pixels use stay exact:
 *   - start: the most used colour, then again and again the colour with the largest
 *     count x (distance to the nearest chosen colour)^2 (a deterministic k-means++);
 *   - Lloyd iterations: every colour goes to the nearest centre, centres move to the weighted mean;
 *   - each palette colour is a real input colour: the member nearest its cluster's centre.
 * Distances are in OKLab (Bjorn Ottosson, 2020), where equal steps look about equally different.
 * Everything is deterministic, so the Xojo port (Quantizer module) gives the same palette.
 *
 * pal_sort_key: the order palettes are written in: greys dark to light, then colours by hue
 * (16 sectors), each dark to light. LZW does not care about the order; people reading a palette do.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "quant.h"

static double lin(int c)                 /* sRGB 0..255 to linear light */
{
    double v = c / 255.0;
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
}

static void oklab(uint32_t rgb, double *L, double *a, double *b)
{
    double r = lin((int) (rgb >> 16) & 255), g = lin((int) (rgb >> 8) & 255), bl = lin((int) rgb & 255);
    double l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl;
    double m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl;
    double s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl;
    l = pow(l, 1.0 / 3.0);
    m = pow(m, 1.0 / 3.0);
    s = pow(s, 1.0 / 3.0);
    *L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    *a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    *b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
}

static double d2(const double *p, const double *q)
{
    double x = p[0] - q[0], y = p[1] - q[1], z = p[2] - q[2];
    return x * x + y * y + z * z;
}

int quant_build(const uint32_t *rgb, const uint32_t *cnt, int n, int k, uint32_t *pal, int *map)
{
    double *lab, *cen, *best;
    int *asg, i, j, m = 0, iter, nc;

    if (n <= 0 || k <= 0)
        return 0;
    if (n <= k)                           /* fits already: nothing to do */
    {
        for (i = 0; i < n; ++i)
        {
            pal[i] = rgb[i];
            map[i] = i;
        }
        return n;
    }
    lab = malloc(sizeof(double) * 3 * n);
    cen = malloc(sizeof(double) * 3 * k);
    best = malloc(sizeof(double) * n);
    asg = malloc(sizeof(int) * n);
    if (!lab || !cen || !best || !asg)
    {
        free(lab); free(cen); free(best); free(asg);
        return -1;
    }
    for (i = 0; i < n; ++i)
        oklab(rgb[i], &lab[3 * i], &lab[3 * i + 1], &lab[3 * i + 2]);

    /* start: the most used colour, then the largest count x distance^2 */
    j = 0;
    for (i = 1; i < n; ++i)
        if (cnt[i] > cnt[j])
            j = i;
    memcpy(cen, &lab[3 * j], 3 * sizeof(double));
    nc = 1;
    for (i = 0; i < n; ++i)
        best[i] = d2(&lab[3 * i], cen);
    while (nc < k)
    {
        double top = 0;
        j = -1;
        for (i = 0; i < n; ++i)
        {
            double v = cnt[i] * best[i];
            if (v > top)
            {
                top = v;
                j = i;
            }
        }
        if (j < 0)
            break;                        /* every colour is already a centre */
        memcpy(&cen[3 * nc], &lab[3 * j], 3 * sizeof(double));
        for (i = 0; i < n; ++i)
        {
            double v = d2(&lab[3 * i], &cen[3 * nc]);
            if (v < best[i])
                best[i] = v;
        }
        nc++;
    }

    /* Lloyd iterations */
    for (i = 0; i < n; ++i)
        asg[i] = -1;
    for (iter = 0; iter < 16; ++iter)
    {
        int changed = 0, c;
        double *sum = calloc((size_t) nc * 4, sizeof(double));
        if (!sum)
            break;
        for (i = 0; i < n; ++i)
        {
            int bc = 0;
            double bd = d2(&lab[3 * i], cen);
            for (c = 1; c < nc; ++c)
            {
                double v = d2(&lab[3 * i], &cen[3 * c]);
                if (v < bd)
                {
                    bd = v;
                    bc = c;
                }
            }
            if (asg[i] != bc)
                changed = 1;
            asg[i] = bc;
            sum[4 * bc] += cnt[i] * lab[3 * i];
            sum[4 * bc + 1] += cnt[i] * lab[3 * i + 1];
            sum[4 * bc + 2] += cnt[i] * lab[3 * i + 2];
            sum[4 * bc + 3] += cnt[i];
        }
        for (c = 0; c < nc; ++c)
            if (sum[4 * c + 3] > 0)
            {
                cen[3 * c] = sum[4 * c] / sum[4 * c + 3];
                cen[3 * c + 1] = sum[4 * c + 1] / sum[4 * c + 3];
                cen[3 * c + 2] = sum[4 * c + 2] / sum[4 * c + 3];
            }
        free(sum);
        if (!changed)
            break;
    }

    /* each cluster becomes its member nearest the centre (ties: more pixels, then first) */
    {
        int c;
        for (c = 0; c < nc; ++c)
        {
            int rep = -1;
            double rd = 0;
            for (i = 0; i < n; ++i)
                if (asg[i] == c)
                {
                    double v = d2(&lab[3 * i], &cen[3 * c]);
                    if (rep < 0 || v < rd || (v == rd && cnt[i] > cnt[rep]))
                    {
                        rep = i;
                        rd = v;
                    }
                }
            if (rep < 0)
                continue;                 /* an empty cluster: dropped */
            pal[m] = rgb[rep];
            for (i = 0; i < n; ++i)
                if (asg[i] == c)
                    map[i] = m;
            m++;
        }
    }
    free(lab);
    free(cen);
    free(best);
    free(asg);
    return m;
}

uint64_t pal_sort_key(uint32_t rgb)
{
    int r = (int) (rgb >> 16) & 255, g = (int) (rgb >> 8) & 255, b = (int) rgb & 255;
    int mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
    int mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
    uint64_t luma = (uint64_t) (r * 299 + g * 587 + b * 114), group = 0;
    if (mx - mn >= 12)                    /* a colour, not a grey: 16 hue sectors */
    {
        int h, d = mx - mn;
        if (mx == r)
            h = (g - b) * 256 / d;
        else if (mx == g)
            h = 512 + (b - r) * 256 / d;
        else
            h = 1024 + (r - g) * 256 / d;
        if (h < 0)
            h += 1536;
        group = 1 + (uint64_t) (h / 96);
    }
    return group << 42 | luma << 24 | rgb;
}

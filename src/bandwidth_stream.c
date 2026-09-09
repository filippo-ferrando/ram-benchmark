/*
 * bandwidth_stream.c - simplified STREAM-style bandwidth benchmark.
 * Reports Copy / Scale / Add / Triad throughput in MB/s. Not an official
 * STREAM binary, but the same four kernels and the same math, so results
 * are comparable across two runs of THIS tool (baseline vs TDX VM).
 *
 * Usage: bandwidth_stream <array_elements> <iterations>
 * Output: CSV lines -> kernel,MBps
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <array_elements> <iterations>\n", argv[0]);
        return 1;
    }
    size_t n = strtoull(argv[1], NULL, 10);
    int iters = atoi(argv[2]);
    if (iters < 1) iters = 1;

    double *a = aligned_alloc(4096, n * sizeof(double));
    double *b = aligned_alloc(4096, n * sizeof(double));
    double *c = aligned_alloc(4096, n * sizeof(double));
    if (!a || !b || !c) { perror("aligned_alloc"); return 1; }

    for (size_t i = 0; i < n; i++) { a[i] = 1.0; b[i] = 2.0; c[i] = 0.0; }

    const double scalar = 3.0;
    double t_copy = 0, t_scale = 0, t_add = 0, t_triad = 0;

    for (int it = 0; it < iters; it++) {
        double t0 = now_sec();
        for (size_t i = 0; i < n; i++) c[i] = a[i];
        t_copy += now_sec() - t0;

        t0 = now_sec();
        for (size_t i = 0; i < n; i++) b[i] = scalar * c[i];
        t_scale += now_sec() - t0;

        t0 = now_sec();
        for (size_t i = 0; i < n; i++) c[i] = a[i] + b[i];
        t_add += now_sec() - t0;

        t0 = now_sec();
        for (size_t i = 0; i < n; i++) a[i] = b[i] + scalar * c[i];
        t_triad += now_sec() - t0;
    }

    double bytes_copy  = 2.0 * n * sizeof(double);
    double bytes_scale = 2.0 * n * sizeof(double);
    double bytes_add   = 3.0 * n * sizeof(double);
    double bytes_triad = 3.0 * n * sizeof(double);

    printf("kernel,MBps\n");
    printf("Copy,%.2f\n",  (bytes_copy  * iters) / t_copy  / 1e6);
    printf("Scale,%.2f\n", (bytes_scale * iters) / t_scale / 1e6);
    printf("Add,%.2f\n",   (bytes_add   * iters) / t_add   / 1e6);
    printf("Triad,%.2f\n", (bytes_triad * iters) / t_triad / 1e6);

    free(a); free(b); free(c);
    return 0;
}

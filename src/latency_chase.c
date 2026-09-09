/*
 * latency_chase.c - random-access memory latency benchmark.
 *
 * Builds a single-cycle random permutation over an array (Sattolo's
 * algorithm, guaranteeing no fixed points and no short sub-cycles), then
 * "chases" the pointer chain sequentially. Because the next address is
 * data-dependent, hardware prefetchers cannot hide the access latency, so
 * the measured ns/access is a good proxy for true memory-subsystem latency
 * at the given working-set size - including any per-access overhead added
 * by inline memory encryption (e.g. TDX/MKTME/TME-MT).
 *
 * Usage: latency_chase <size_bytes> <target_accesses> [seed]
 * Output: CSV line -> size_bytes,ns_per_access
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

static uint64_t xorshift_state;

static uint64_t xorshift64(void) {
    uint64_t x = xorshift_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    xorshift_state = x;
    return x;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <size_bytes> <target_accesses> [seed]\n", argv[0]);
        return 1;
    }

    size_t size_bytes       = strtoull(argv[1], NULL, 10);
    uint64_t target_accesses = strtoull(argv[2], NULL, 10);
    xorshift_state = argc > 3 ? strtoull(argv[3], NULL, 10) : 0x9E3779B97F4A7C15ULL;

    size_t n = size_bytes / sizeof(uint64_t);
    if (n < 2) n = 2;

    uint64_t *arr = aligned_alloc(4096, n * sizeof(uint64_t));
    if (!arr) { perror("aligned_alloc"); return 1; }

    for (size_t i = 0; i < n; i++) arr[i] = i;

    /* Sattolo's algorithm: single cycle covering all n elements */
    for (size_t i = n - 1; i >= 1; i--) {
        size_t j = xorshift64() % i; /* j in [0, i-1] */
        uint64_t tmp = arr[i];
        arr[i] = arr[j];
        arr[j] = tmp;
    }

    /* fault pages in ahead of timing so we don't measure page faults */
    for (size_t i = 0; i < n; i += 4096 / sizeof(uint64_t)) {
        arr[i] = arr[i];
    }

    volatile size_t p = 0;
    uint64_t warmup = target_accesses / 10 + 1;
    for (uint64_t k = 0; k < warmup; k++) p = arr[p];

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (uint64_t k = 0; k < target_accesses; k++) p = arr[p];
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double elapsed_ns = (t1.tv_sec - t0.tv_sec) * 1e9 +
                         (t1.tv_nsec - t0.tv_nsec);
    double ns_per_access = elapsed_ns / (double)target_accesses;

    printf("%zu,%.4f\n", size_bytes, ns_per_access);

    free(arr);
    (void)p;
    return 0;
}

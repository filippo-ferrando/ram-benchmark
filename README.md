# ram-bench-suite

A small benchmark suite that measures how much Intel TDX memory encryption slows down RAM.
It measures memory **latency** and **bandwidth** inside a TDX guest (a *trust domain*, TD)
and compares them with an identical regular VM.

## Background

Intel Trust Domain Extensions (TDX) isolate a VM from the host and hypervisor. Three parts
of this design sit on the memory access path:

- **Inline memory encryption (MKTME / TME-MT).** The memory controller encrypts and
  decrypts each cache line with a per-TD AES-XTS key. Data inside the CPU caches is plaintext,
  so the cost only appears on a cache miss.
- **Integrity and ownership tracking.** TDX attaches metadata to each cache line
  (the TD-owner bit, and optionally cryptographic integrity) and checks it on every
  DRAM access.
- **Secure EPT.** Guest-physical to host-physical address translation goes through page
  tables managed by the TDX module, so TLB misses and page walks can also cost more.

So the expected pattern is little or no overhead while the working set fits in cache, then
a step up once accesses go to DRAM. The suite is built to show that step and measure its size.

## Methodology

### 1. Experimental design

The test is an A/B comparison where the only intended difference is whether TDX is enabled.
`run_all.sh` runs on a regular VM (`--label not-tdx`) and on a TDX guest (`--label tdx`),
and `compare.sh` turns the two result directories into overhead tables.

Controls that keep the comparison fair:

- **Same hardware:** both VMs on the same physical host, with the same BIOS and firmware settings.
- **Same VM shape:** same vCPU count and topology, same amount of RAM, same guest kernel.
- **Same binaries:** the C sources are compiled inside each VM with the same `gcc -O2` flags.
- **Stable clocks:** `setup.sh` sets the cpufreq governor to `performance` where the guest exposes it.
- **No page-fault noise:** every page is touched before the timed region starts.
- **Run-to-run noise:** `--repeat N` repetitions, which `compare.sh` averages.
- **Verified TDX status:** `system_info.txt` records the `tdx_guest` CPU flag and the `tdx:` dmesg lines,
  so you can prove which VM was which.

### 2. Latency: pointer chasing over a random cycle

Source: [`src/latency_chase.c`](src/latency_chase.c)

Latency is the primary metric. Encryption adds a fixed cost to each DRAM access, and that
cost is clearest when accesses can't overlap.

1. **Allocate** an array of `n = size / 8` 64-bit slots, aligned to 4 KB pages.
2. **Build a single random cycle** with Sattolo's algorithm: start from the identity
   permutation and, for `i = n-1 … 1`, swap `arr[i]` with `arr[j]` where `j ∈ [0, i-1]`.
   Unlike a plain Fisher–Yates shuffle, this always produces one cycle that covers all
   `n` elements. With no short sub-cycles, the chase visits the whole working set instead
   of looping inside a small, cache-resident subset. A seeded `xorshift64` PRNG makes runs
   reproducible.
3. **Pre-fault** every 4 KB page, so first-touch page faults (and, on TDX, lazy page
   acceptance) stay out of the measurement.
4. **Warm up** with `accesses / 10` hops.
5. **Time** `accesses` dependent loads with `CLOCK_MONOTONIC`:

   ```c
   for (k = 0; k < accesses; k++) p = arr[p];   // next address = this load's value
   ```

   Each load's address is the value of the previous load, so the CPU can't issue loads in
   parallel, and the random order defeats the hardware prefetchers. `p` is `volatile`, so
   the compiler can't remove the loop.
6. **Report** `elapsed_ns / accesses` (average ns per dependent access) as a
   `size_bytes,ns_per_access` CSV line.

### 3. Working-set sweep

Driver: [`run_latency.sh`](run_latency.sh)

The pointer chase runs at 11 working-set sizes, from 4 KB to 4 GB in ×4 steps. This covers
every level of the memory hierarchy. The cache levels act as built-in controls, because TDX
should make no difference there.

| Size | Typical level | Timed accesses |
|---|---|---|
| 4 KB, 16 KB | L1d | 50 M |
| 64 KB, 256 KB, 1 MB | L2 | 50 M |
| 4 MB, 16 MB | L2 → L3 | 50 M |
| 64 MB, 256 MB | L3 → DRAM (CPU-dependent) | 5 M |
| 1 GB, 4 GB | DRAM | 5 M |

Sizes above a few MB also miss the TLB on most hops. The real boundaries depend on the CPU,
so read them from your own latency curve. Small sizes run 10× more accesses because each hop
is cheap, and the higher count keeps timer resolution from dominating.

### 4. Bandwidth: STREAM-style kernels

Source: [`src/bandwidth_stream.c`](src/bandwidth_stream.c), driver: [`run_bandwidth.sh`](run_bandwidth.sh)

Bandwidth is a secondary metric. Sequential streams are prefetch-friendly and keep many
requests in flight, which hides much of the per-access encryption latency. The suite
reimplements the four classic [STREAM](https://www.cs.virginia.edu/stream/) kernels:

| Kernel | Operation | Bytes moved per element |
|---|---|---|
| Copy  | `c[i] = a[i]` | 16 |
| Scale | `b[i] = s * c[i]` | 16 |
| Add   | `c[i] = a[i] + b[i]` | 24 |
| Triad | `a[i] = b[i] + s * c[i]` | 24 |

- Three arrays of 64 Mi doubles (512 MB each, 1.5 GB total), far larger than any LLC, so the kernels stream from DRAM.
- 10 iterations. Each kernel is timed separately: MB/s = `bytes × iters / time`.
- Single-threaded, so the result is per-core sustainable bandwidth, not socket bandwidth.

### 5. Cross-checks: sysbench and Intel MLC

- **sysbench memory** (in `run_bandwidth.sh`) reads and writes 64 GB in 1 MB blocks as an
  independent sanity check. A 1 MB block stays largely in cache, so this mostly measures
  cache bandwidth and should show little TDX difference.
- **Intel Memory Latency Checker** (`run_mlc.sh`): if `mlc` is on `PATH`, the suite also
  records `--idle_latency`, `--bandwidth_matrix` and `--loaded_latency`. MLC is Intel's
  reference tool for this kind of measurement. It's a license-gated download, so this step
  is skipped when MLC isn't installed.

### 6. Environment capture

At the start of each run, `run_all.sh` writes `system_info.txt` with:

- `lscpu`: CPU model, cache sizes (to locate the LLC boundary) and flags
- `/proc/meminfo`, including `Unaccepted:` memory on TDX guests
- `dmesg | grep tdx`, e.g. `Memory Encryption Features active: Intel TDX`
- whether the `tdx_guest` CPU flag is present

Each result directory is therefore self-describing, so you can always prove that a run came from a real TD.

### 7. Repetition and aggregation

Aggregator: [`compare.sh`](compare.sh)

Each repetition creates `rep1/ … repN/` with `latency.csv` and `bandwidth.csv`.
`compare.sh` takes the arithmetic mean across repetitions for every size and kernel, then reports:

```
latency overhead = (TDX - baseline) / baseline * 100    (higher is worse)
bandwidth delta  = (TDX - baseline) / baseline * 100    (lower is worse)
```

## Quick start

Requirements: a Linux guest with `bash`, `gcc` and `python3`. `sysbench`, `numactl` and
Intel MLC are optional.

```bash
# 1. One-time setup on each VM (installs gcc/sysbench, sets the CPU governor)
sudo ./setup.sh

# 2a. On the regular (non-TDX) VM
./run_all.sh --label not-tdx --repeat 5

# 2b. On the TDX guest
./run_all.sh --label tdx --repeat 5

# 3. Copy both result directories to one machine and compare
./compare.sh results/not-tdx/<timestamp> results/tdx/<timestamp>
```

Each `run_all.sh` prints its output directory. A full pass takes a few minutes per repetition.

The latency sweep allocates up to 4 GB and the bandwidth test about 1.5 GB. On smaller VMs,
reduce `SIZES_KB` in `run_latency.sh` and `ELEMENTS` in `run_bandwidth.sh`, keeping at least
2–3 sizes larger than the LLC.

Individual tools:

```bash
./run_latency.sh   out.csv        # latency sweep only
./run_bandwidth.sh out.csv        # STREAM + sysbench only
./run_mlc.sh       out_dir/       # Intel MLC only (if installed)

bin/latency_chase    <size_bytes> <accesses> [seed]   # prints size_bytes,ns_per_access
bin/bandwidth_stream <elements> <iterations>          # prints kernel,MBps
```

## Repository layout

```
setup.sh               one-time: dependencies + 'performance' CPU governor
run_all.sh             orchestrator: system snapshot + N labelled repetitions
run_latency.sh         compiles and runs the 4 KB → 4 GB pointer-chase sweep
run_bandwidth.sh       compiles and runs the STREAM-like kernels + sysbench cross-check
run_mlc.sh             Intel MLC idle/loaded latency + bandwidth matrix (optional)
compare.sh             baseline vs TDX: mean over repetitions, % overhead tables
lib/common.sh          logging and helper functions
src/latency_chase.c    Sattolo single-cycle pointer chase
src/bandwidth_stream.c Copy / Scale / Add / Triad

results/<label>/<timestamp>/
  system_info.txt      lscpu, meminfo, TDX evidence
  rep<N>/              latency.csv, bandwidth.csv, sysbench and mlc output
```

## Interpreting the results

1. **Find the LLC size** in `system_info.txt`. Inside VMs the reported cache topology may be
   synthetic and can differ between the two guests, so where the latency curve jumps
   (typically a 2–3× step into DRAM) is a better guide.
2. **Treat small-size overhead as an offset.** Data in L1/L2 never reaches the memory
   controller, so any difference there isn't encryption. If it's consistent across
   repetitions, it's a systematic offset (from clock or virtualization differences)
   that every other row also includes.
3. **Don't attribute the mid-range to encryption.** Between the L2 size and the jump to DRAM,
   the L3 serves most accesses. Overhead there more likely comes from TLB misses, page walks
   (Secure EPT) and virtualization.
4. **Read the plateau.** The overhead at the largest sizes, where it stops growing, answers
   "how much latency does TDX add?". It's an end-to-end figure (DRAM encryption plus TLB
   misses and page walks), not pure AES latency.
5. **Expect bandwidth to suffer less than latency.** Streaming accesses overlap and hide
   per-line latency, so pointer-heavy workloads (databases, key-value stores, graph
   traversal) feel TDX more than streaming or compute-bound ones.
6. **Check the spread.** If the standard deviation across repetitions is close to the
   difference you're reading, run more repetitions (`--repeat 10`).

## Limitations

- **Same-host assumption.** Results only mean something if both VMs run on the same hardware
  with the same BIOS and firmware settings. Otherwise you measure platform differences instead
  of TDX. `system_info.txt` records the CPU model but can't prove both guests ran on the same host.
- **Concurrent runs.** Running both VMs at the same time makes them compete for the host's
  memory bandwidth and LLC, so run them one at a time.
- **Guests can differ in more than TDX.** Compare the two `system_info.txt` files: differences
  in physical address width, exposed cache topology or RAM size can also affect the measured gap.
- **No vCPU pinning by default.** Scheduler migrations and noisy neighbours add variance.
  For tighter numbers, pin with `taskset` or `numactl` on both the host and the guest.
- **Page size not controlled.** The benchmark doesn't request huge pages, and the guest's THP
  setting isn't recorded, so results at large sizes probably include TLB-miss and page-walk
  cost as well as DRAM latency. Using `madvise(MADV_HUGEPAGE)` or hugetlbfs would separate the two.
- **Single-threaded.** Neither benchmark measures loaded latency or full-socket bandwidth.
  Intel MLC's `--loaded_latency` and `--bandwidth_matrix` cover that when it's available.
- **Simplified STREAM.** These kernels aren't the official STREAM binary (no OpenMP, `-O2` only),
  so don't compare absolute MB/s with published STREAM results. Only the A/B difference is meaningful.
- **Mean, not median.** `compare.sh` averages repetitions, so one outlier can shift a row.
  Check the per-repetition CSVs if a value looks odd.
- **Platform-specific.** Results only hold for the CPU generation, TDX module version and
  memory integrity settings they were measured on.

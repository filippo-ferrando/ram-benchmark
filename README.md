# ram-bench-suite

Measures how much latency RAM/memory encryption (Intel TDX / MKTME /
TME-MT) adds inside a VM, by comparing a **baseline** (non-confidential)
VM against a **TDX** VM, ideally on the same physical host.

## Why latency, not just bandwidth

TDX's memory-encryption engine sits inline on the path to DRAM. Its
cost mostly shows up as **added nanoseconds per random access**, and
that overhead only becomes visible once your working set is larger
than the last-level cache (LLC) — below that, you're hitting cache,
not the encryption engine. Bandwidth (STREAM-style) is included as a
secondary, cheaper-to-collect signal, but latency is the primary one.

The core tool is a pointer-chasing benchmark (`src/latency_chase.c`)
using Sattolo's algorithm to build a single random cycle over the
array, so the CPU's prefetcher can't hide the true access latency —
each next address is only known after the previous load completes.

## Layout

```
setup.sh              # one-time: installs gcc/sysbench, sets CPU governor
run_latency.sh <csv>   # compiles + runs the latency sweep (4KB..4GB)
run_bandwidth.sh <csv> # compiles + runs the STREAM-like bandwidth test
run_mlc.sh <dir>       # runs Intel MLC too, IF you have it installed
run_all.sh             # orchestrates everything, tags results with a label
compare.sh             # diffs a baseline run vs a TDX run, % overhead
src/latency_chase.c    # pointer-chase latency benchmark (C)
src/bandwidth_stream.c # simplified 4-kernel STREAM-alike (C)
lib/common.sh          # shared logging helpers
```

## Usage

Run this identically on **both** VMs (same vCPU/RAM sizing, same host
if at all possible):

```bash
sudo ./setup.sh                      # once per VM

# on the non-TDX / baseline VM:
./run_all.sh --label baseline --repeat 5

# on the TDX VM:
./run_all.sh --label tdx --repeat 5
```

Each `run_all.sh` invocation prints its result directory, e.g.
`results/baseline/20260909_150749`. Copy both directories to one
machine (or just run `compare.sh` remotely against mounted/copied
paths) and diff them:

```bash
./compare.sh results/baseline/20260909_150749 results/tdx/20260909_151200
```

This prints a per-size latency overhead table and a bandwidth delta
table.

## Interpreting results

- Check `system_info.txt` in each run dir for LLC size (`lscpu`) so you
  know which rows in the latency table are cache-resident vs DRAM.
- Below the LLC size, expect noisy or even negative "overhead" —
  you're not touching DRAM yet, so TDX shouldn't matter there.
- Above the LLC size, expect the overhead % to stabilize at roughly a
  constant value — that stabilized number is your answer to "how much
  latency does TDX add."
- Run with `--repeat 5` (or more) and treat single-rep results with
  suspicion; VMs are noisy neighbors.

## Caveats for a fair comparison

- Best done on the **same physical host**, one VM with TDX enabled,
  one without, same vCPU count/pinning, same amount of RAM.
- Set the CPU governor to `performance` on both (setup.sh does this).
- Avoid comparing across different host generations/BIOS settings —
  you'll measure hardware differences, not TDX overhead.
- If you have access to Intel's Memory Latency Checker (`mlc`,
  license-gated download from Intel), `run_mlc.sh` will use it
  automatically if it's on `PATH` — it's the closest thing to an
  industry-standard tool for exactly this comparison and Intel's own
  TDX collateral is built with it.

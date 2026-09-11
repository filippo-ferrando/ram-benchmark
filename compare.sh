#!/usr/bin/env bash
# Compares a baseline run directory against a TDX run directory
# (the timestamped dirs that run_all.sh prints), averaging across
# repetitions, and prints latency/bandwidth overhead as a percentage.
#
# Usage: ./compare.sh <baseline_run_dir> <tdx_run_dir>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

[[ $# -eq 2 ]] || die "usage: $0 <baseline_run_dir> <tdx_run_dir>"
check_bin python3 || die "python3 required for compare.sh"

BASELINE="$1"
TDX="$2"

python3 - "$BASELINE" "$TDX" <<'PYEOF'
import sys, os, glob, csv
from collections import defaultdict

def load_latency(run_dir):
    data = defaultdict(list)
    for f in glob.glob(os.path.join(run_dir, "rep*", "latency.csv")):
        with open(f) as fh:
            r = csv.reader(fh)
            next(r, None)
            for row in r:
                if not row:
                    continue
                size, ns = int(row[0]), float(row[1])
                data[size].append(ns)
    return {k: sum(v) / len(v) for k, v in data.items()}

def load_bandwidth(run_dir):
    data = defaultdict(list)
    for f in glob.glob(os.path.join(run_dir, "rep*", "bandwidth.csv")):
        with open(f) as fh:
            r = csv.reader(fh)
            next(r, None)
            for row in r:
                if not row:
                    continue
                kernel, mbps = row[0], float(row[1])
                data[kernel].append(mbps)
    return {k: sum(v) / len(v) for k, v in data.items()}

baseline_dir, tdx_dir = sys.argv[1], sys.argv[2]

base_lat = load_latency(baseline_dir)
tdx_lat = load_latency(tdx_dir)

def human_size(n):
    if n < 1024 * 1024:
        return f"{n // 1024}KB"
    if n < 1024 * 1024 * 1024:
        return f"{n // 1024 // 1024}MB"
    return f"{n // 1024 // 1024 // 1024}GB"

print("\n=== Memory Latency (pointer chase, ns/access) ===")
print(f"{'Size':>10} {'Baseline':>12} {'TDX':>12} {'Overhead':>10}")
for size in sorted(set(base_lat) | set(tdx_lat)):
    b, t = base_lat.get(size), tdx_lat.get(size)
    if b is None or t is None:
        continue
    pct = (t - b) / b * 100
    print(f"{human_size(size):>10} {b:>12.2f} {t:>12.2f} {pct:>9.1f}%")

base_bw = load_bandwidth(baseline_dir)
tdx_bw = load_bandwidth(tdx_dir)

print("\n=== Memory Bandwidth (STREAM-like, MB/s) ===")
print(f"{'Kernel':>10} {'Baseline':>14} {'TDX':>12} {'Delta':>10}")
for kernel in sorted(set(base_bw) | set(tdx_bw)):
    b, t = base_bw.get(kernel), tdx_bw.get(kernel)
    if b is None or t is None:
        continue
    pct = (t - b) / b * 100
    print(f"{kernel:>10} {b:>14.2f} {t:>12.2f} {pct:>9.1f}%")

print("\nInterpretation: watch the latency overhead column as size crosses your")
print("LLC size (check system_info.txt / lscpu for cache sizes) into pure DRAM")
print("range - that's where TDX's memory-encryption engine sits on the access")
print("path, so overhead should stabilize at roughly a constant % there.")
PYEOF

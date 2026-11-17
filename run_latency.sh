#!/usr/bin/env bash
# Runs the pointer-chase latency benchmark across a sweep of working-set
# sizes from L1-cache range up to well past typical LLC size, into DRAM.
# Usage: run_latency.sh <output_csv_path>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

[[ $# -eq 1 ]] || die "usage: $0 <output_csv_path>"
OUT="$1"

ensure_dir "$DIR/bin"
gcc -O2 -o "$DIR/bin/latency_chase" "$DIR/src/latency_chase.c" || die "compile failed"

echo "size_bytes,ns_per_access" > "$OUT"

# Sizes in KB: 4KB (L1) ... 4GB (deep DRAM). Trim the top end if your VM
# has less RAM than this - leave at least 2-3 sizes past your LLC size.
SIZES_KB=(4 16 64 256 1024 4096 16384 65536 262144 1048576 4194304)

for kb in "${SIZES_KB[@]}"; do
  bytes=$((kb * 1024))
  if [[ $bytes -le $((32 * 1024 * 1024)) ]]; then
    accesses=50000000
  else
    accesses=5000000
  fi
  log "latency: size=${kb}KB accesses=${accesses}"
  line=$("$DIR/bin/latency_chase" "$bytes" "$accesses") || die "latency_chase failed at ${kb}KB"
  echo "$line" >> "$OUT"
done

log "latency results -> $OUT"

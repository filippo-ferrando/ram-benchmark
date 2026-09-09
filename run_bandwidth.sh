#!/usr/bin/env bash
# Runs the STREAM-like bandwidth benchmark (secondary signal - TDX's
# encryption overhead mostly shows up in latency, not raw throughput,
# but it's cheap to collect and worth checking).
# Usage: run_bandwidth.sh <output_csv_path>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

[[ $# -eq 1 ]] || die "usage: $0 <output_csv_path>"
OUT="$1"

gcc -O2 -o "$DIR/bin/bandwidth_stream" "$DIR/src/bandwidth_stream.c" || die "compile failed"

# 64M doubles/array = 512MB per array, comfortably past typical LLC size.
# Lower this if the VM has limited RAM.
ELEMENTS=$((64 * 1024 * 1024))
ITERS=10

log "bandwidth: elements=$ELEMENTS iters=$ITERS"
"$DIR/bin/bandwidth_stream" "$ELEMENTS" "$ITERS" > "$OUT" || die "bandwidth_stream failed"

if check_bin sysbench; then
  log "running sysbench memory as a secondary cross-check"
  sysbench memory --memory-block-size=1M --memory-total-size=64G --memory-oper=read run \
    > "${OUT%.csv}_sysbench_read.txt" 2>&1 || true
  sysbench memory --memory-block-size=1M --memory-total-size=64G --memory-oper=write run \
    > "${OUT%.csv}_sysbench_write.txt" 2>&1 || true
fi

log "bandwidth results -> $OUT"

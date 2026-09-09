#!/usr/bin/env bash
# Orchestrates a full benchmark pass and tags results with a label
# (e.g. "baseline" or "tdx") so compare.sh can diff two runs later.
#
# Usage:
#   ./run_all.sh --label baseline --repeat 5
#   ./run_all.sh --label tdx      --repeat 5
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

LABEL="run"
REPEAT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--label)  LABEL="$2"; shift 2 ;;
    -r|--repeat) REPEAT="$2"; shift 2 ;;
    *) die "unknown arg $1" ;;
  esac
done

TS="$(date +%Y%m%d_%H%M%S)"
BASE="$RESULTS_ROOT/${LABEL}/${TS}"
ensure_dir "$BASE"

log "Capturing system info snapshot..."
{
  echo "== lscpu =="; lscpu 2>/dev/null || echo "lscpu unavailable"
  echo "== meminfo =="; cat /proc/meminfo
  echo "== TDX guest dmesg lines =="
  dmesg 2>/dev/null | grep -i tdx || echo "no tdx dmesg lines found (need sudo, or not a TDX guest)"
  echo "== cpuid tdx_guest flag =="
  grep -o 'tdx_guest' /proc/cpuinfo | head -1 || echo "tdx_guest flag not present in /proc/cpuinfo"
} > "$BASE/system_info.txt" 2>&1

for i in $(seq 1 "$REPEAT"); do
  RUN_DIR="$BASE/rep${i}"
  ensure_dir "$RUN_DIR"
  log "=== repetition $i/$REPEAT (label=$LABEL) ==="
  "$DIR/run_latency.sh" "$RUN_DIR/latency.csv"
  "$DIR/run_bandwidth.sh" "$RUN_DIR/bandwidth.csv"
  "$DIR/run_mlc.sh" "$RUN_DIR"
done

log "All results saved under: $BASE"
echo "$BASE"

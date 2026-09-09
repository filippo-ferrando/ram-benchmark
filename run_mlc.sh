#!/usr/bin/env bash
# Wraps Intel Memory Latency Checker (mlc) if it's installed - it's a
# proprietary, license-gated download from Intel, not installable via
# apt, but it's the closest thing to an industry-standard tool for this
# exact comparison (Intel's own TDX collateral uses it). Skipped silently
# if not found.
# Usage: run_mlc.sh <output_dir>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

[[ $# -eq 1 ]] || die "usage: $0 <output_dir>"
OUT_DIR="$1"

if ! check_bin mlc; then
  log "Intel MLC not found in PATH - skipping (get it from Intel's site if you want it)."
  exit 0
fi

log "running mlc idle latency"
mlc --idle_latency > "$OUT_DIR/mlc_idle_latency.txt" 2>&1 || true

log "running mlc bandwidth matrix"
mlc --bandwidth_matrix > "$OUT_DIR/mlc_bandwidth_matrix.txt" 2>&1 || true

log "running mlc loaded latency"
mlc --loaded_latency > "$OUT_DIR/mlc_loaded_latency.txt" 2>&1 || true

log "mlc results -> $OUT_DIR"

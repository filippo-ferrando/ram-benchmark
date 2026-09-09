#!/usr/bin/env bash
# Installs build tools + optional helper utilities, and tunes the CPU
# governor for repeatable measurements. Run this once on EACH VM you
# intend to benchmark (baseline and TDX).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

if [[ $EUID -ne 0 ]]; then
  die "run as root (sudo) - needs to install packages and set the CPU governor"
fi

log "Installing build dependencies..."
if check_bin apt-get; then
  apt-get update -y
  apt-get install -y build-essential sysbench numactl linux-tools-common linux-tools-generic
elif check_bin dnf; then
  dnf install -y gcc make sysbench numactl
else
  die "unsupported package manager - install gcc, sysbench, numactl manually"
fi

log "Setting CPU governor to 'performance' where supported..."
shopt -s nullglob
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [[ -w "$gov" ]] && echo performance > "$gov" 2>/dev/null || true
done

log "NOTE: for a fair baseline-vs-TDX comparison, also try to:"
log "  - pin vCPUs to the same physical cores each run (taskset/numactl)"
log "  - disable/avoid host-level turbo boost variance if you control the host"
log "  - keep both VMs otherwise identically sized/configured"
log "Setup complete."

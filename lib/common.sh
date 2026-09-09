#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[$(date '+%H:%M:%S')] $*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

RESULTS_ROOT="${RESULTS_ROOT:-$(pwd)/results}"

ensure_dir() { mkdir -p "$1"; }

check_bin() { command -v "$1" >/dev/null 2>&1; }

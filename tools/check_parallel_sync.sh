#!/bin/bash
#
# tools/check_parallel_sync.sh — each program in f90_src_parallel must be its
# f90_src program plus OpenMP directives only. Prints the differences (other than
# the !$omp lines and the OpenMP note at the top) and exits 1 if there are any.
# Run it after changing one of these programs in f90_src.
#
# Usage: tools/check_parallel_sync.sh
#
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
strip() {  # drop the !$omp lines and the OpenMP note block
  awk '/^!\$omp/ {next}
       /^! OpenMP version \(f90_src_parallel\)/ {note=1}
       note && /^! without the flag the directives are comments/ {note=0; skip=1; next}
       note {next}
       skip && /^!$/ {skip=0; next}
       {skip=0; print}' "$1"
}
rc=0
for p in "${ROOT_DIR}"/f90_src_parallel/RCM_*.f90; do
  s="${ROOT_DIR}/f90_src/$(basename "$p")"
  if [ ! -f "$s" ]; then
    echo "$(basename "$p"): no f90_src/$(basename "$p")"; rc=1; continue
  fi
  if ! d=$(diff <(strip "$s") <(strip "$p")); then
    echo "== $(basename "$p") differs from f90_src (besides OpenMP):"; echo "$d"; rc=1
  fi
done
[ $rc -eq 0 ] && echo "f90_src_parallel: in step with f90_src."
exit $rc

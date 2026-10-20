#!/bin/bash
#
# scripts/run_aggregate.sh — job: daily and monthly files with tools/aggregate.sh.
# Usage: ./submit.sh [--ntasks=<n>] [--time=hh:mm:ss] run_aggregate.sh [aggregate options] <first year> [<last year>] [<variable> ...]
#        ./run.sh -a <experiment> <first year> [<last year>] [<variable> ...]
# With --ntasks=<n>, n variables are processed at the same time.
# See README.md §11.
#----------------------------------------------------------------

#
#--- Repo location and site settings (set by submit.sh) ----------
#
: "${ROOT_DIR:?ROOT_DIR is not set — submit this script through submit.sh, not plain sbatch (see README.md §0)}"
# shellcheck source=/dev/null
source "${ROOT_DIR}/env.site.sh"

# NCO: from the modules, or the archive step's modules (CP_MODULES), or the default nco module
if ! command -v ncra >/dev/null; then
  # shellcheck disable=SC2086
  module load ${AGG_MODULES:-nco} || true
fi
command -v ncra >/dev/null || { echo "ERROR: NCO (ncra) not found — set AGG_MODULES in env.site.sh." >&2; exit 1; }
ncks --version 2>&1 | head -1

#
#--- Run ---------------------------------------------------------
# Temporary files on the node's local disk ($TMPDIR), one variable per task.
#
exec "${ROOT_DIR}/tools/aggregate.sh" -j "${SLURM_NTASKS:-1}" -w "${TMPDIR:-/tmp}" "$@"

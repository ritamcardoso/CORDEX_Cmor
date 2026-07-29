#!/bin/bash
#
# submit.sh
#
# Thin wrapper so you never have to `export ROOT_DIR` yourself (in
# ~/.bashrc or otherwise) before submitting a job. It figures out ROOT_DIR
# from where THIS file actually lives — which can be on a different disk
# from wherever you run it from — and passes it straight into the Slurm
# job's environment via `sbatch --export`, without ever touching your
# shell's persistent state.
#
# Why this works reliably (and scripts/*.sh on their own don't): sbatch
# copies whatever script you hand it into a spool file before running it,
# so a script trying to find its own location via $0/dirname once it's
# running as a job gets the spool path, not this repo (see README.md,
# "Where the code lives"). submit.sh sidesteps that entirely by resolving
# its own path *before* sbatch is ever invoked, then threading ROOT_DIR
# through explicitly as part of the sbatch call itself.
#
# Usage:
#   ./submit.sh <script-name> [args...]
#
# Examples:
#   ./submit.sh run_Analysis_v2.sh 20010101 20011231 2005
#   ./submit.sh run_out_generic.sh 19900101 19901231 2000 soil
#   ./submit.sh run_cp_generic.sh  19900101 19901231 2000 soil
#
# Need custom sbatch flags (--job-name, --time, --output, --error, ...) —
# e.g. to submit a single varset directly with its own name/time limit?
# Pass them via SBATCH_OPTS:
#   SBATCH_OPTS="--job-name=wrf-soil --time=12:00:00 \
#                --output=wrf-soil.%j.out --error=wrf-soil.%j.out" \
#     ./submit.sh run_out_generic.sh 19900101 19901231 2000 soil
#
# Can be run from anywhere — you don't need to cd into this repo first,
# just give the right path to submit.sh itself, e.g.:
#   /mnt/other-disk/CORDEX_Cmor/submit.sh run_Analysis_v2.sh ...
#
# (If you'd rather keep exporting ROOT_DIR by hand — e.g. for scripting
# around this repo some other way — that still works exactly as before;
# this is purely an additional, easier front door.)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
export ROOT_DIR="${SCRIPT_DIR}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <script-name> [args...]" >&2
  echo "e.g.:  $0 run_Analysis_v2.sh 20010101 20011231 2005" >&2
  exit 1
fi

target="$1"
shift

target_path="${ROOT_DIR}/scripts/${target}"
if [ ! -f "${target_path}" ]; then
  echo "No such script: ${target_path}" >&2
  echo "(Looked under ROOT_DIR=${ROOT_DIR}, auto-detected from submit.sh's own location.)" >&2
  exit 1
fi

echo "ROOT_DIR=${ROOT_DIR} (auto-detected from submit.sh's own location)"
# SBATCH_OPTS is intentionally unquoted and word-split below — it's meant to
# carry zero or more separate flags (e.g. SBATCH_OPTS="--time=12:00:00
# --job-name=foo"), same as any other $@-style flag-forwarding wrapper.
# shellcheck disable=SC2086
exec sbatch --export=ALL,ROOT_DIR="${ROOT_DIR}" ${SBATCH_OPTS:-} "${target_path}" "$@"

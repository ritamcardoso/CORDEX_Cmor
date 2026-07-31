#!/bin/bash
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --hint=nomultithread
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt
#
# scripts/run_cp_generic.sh
#
# Generic replacement for run_cp_out.sh and its siblings. Archives every
# variable belonging to <varset> (config/varsets.sh) to ECFS and a remote
# server. Variable names come straight from config/varsets.sh, so this
# always matches what run_out_generic.sh just produced for that varset —
# no separate variable list to keep in sync.
#
# --account/--mail-user/--chdir above are the only site-specific bits left
# in this file — edit them directly here (and in run_out_generic.sh /
# run_Analysis_v2.sh, the only other two scripts).
#
# Usage (ROOT_DIR must be exported first — see README.md):
#   export ROOT_DIR=/path/to/this/repo
#   sbatch --job-name=cp-<varset> --time=<hh:mm:ss> \
#          --output=cp-<varset>.%j.out --error=cp-<varset>.%j.out \
#          $ROOT_DIR/scripts/run_cp_generic.sh <datebeg> <dateend> <year_lim> <varset>
#
# Normally you don't call this directly — run_out_generic.sh submits it
# automatically after processing each varset.
#
# ECFS and scp transfers run one at a time by default (MAX_PARALLEL_CP=1,
# set in env.site.sh — see env.site.sh.example). See README.md §6,
# "Running things in parallel", for raising MAX_PARALLEL_CP if your
# site allows concurrent transfers. A failed transfer is caught and
# turned into a nonzero exit either way.
#----------------------------------------------------------------

set -x

# ROOT_DIR must be set in your environment — see run_out_generic.sh's
# comment on why $0/dirname can't be used to find this repo under Slurm.
: "${ROOT_DIR:?ROOT_DIR is not set. export ROOT_DIR=/path/to/this/repo (e.g. in ~/.bashrc) before submitting — see README.md}"
REPO_DIR="${ROOT_DIR}"

datebeg=$1
dateend=$2
year_lim=$3
VARSET=$4

if [ -z "${VARSET}" ]; then
  echo "Usage: $0 <datebeg> <dateend> <year_lim> <varset>" >&2
  exit 1
fi

#----------------------------------------------------------------
#                          ENVIRONMENT                            |
#----------------------------------------------------------------
# site/user-specific modules & remote paths for the archive step -> env.site.sh
source "${REPO_DIR}/env.site.sh"

# variable-set definitions -> config/varsets.sh
source "${REPO_DIR}/config/varsets.sh"

if [ -z "${VARSETS[$VARSET]+x}" ]; then
  echo "Unknown varset '${VARSET}'. Known varsets:" >&2
  printf ' %s\n' "${!VARSETS[@]}" >&2
  exit 1
fi

# shellcheck disable=SC2086
module load ${CP_MODULES}

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${NETCDF4_DIR}/lib"

# Flatten every group in this varset into one plain variable list — the
# program pattern doesn't matter for archiving, only the variable name
# (it's the output file prefix, "<var>_*.nc").
IFS=';' read -r -a groups <<< "${VARSETS[$VARSET]}"
var=()
for group in "${groups[@]}"; do
  IFS=',' read -r -a group_vars <<< "${group#*:}"
  var+=("${group_vars[@]}")
done

#----------------------------------------------------------------
#                        Processing                               |
#----------------------------------------------------------------
date

echo "$datebeg"
echo "$dateend"

yeari=$(echo "$datebeg" | cut -c1-4)
echo "$yeari"
yearf=$(echo "$dateend" | cut -c1-4)
echo "$yearf"

cd "${CP_RUN_DIR}" || exit 1

# Both archive loops below run up to MAX_PARALLEL_CP transfers concurrently
# instead of one at a time — for varsets with many variables (e.g. [out]
# has 15) running them one at a time is a lot of serial network
# round-trips for what's an embarrassingly parallel operation. Defaults to
# 1 (fully serial) below; set MAX_PARALLEL_CP in env.site.sh (see
# env.site.sh.example and README.md §6) to raise it if your site allows
# concurrent transfers. Failures are tracked either way (a backgrounded
# transfer failing silently would otherwise go unnoticed) and turned into
# a nonzero exit at the end.
MAX_PARALLEL_CP="${MAX_PARALLEL_CP:-1}"
failed=0

pids=()
for (( v=0; v<${#var[@]}; v++)); do
  (
    emkdir -p "${ECFS_BASE}/${var[$v]}" &&
    ecp -o "${var[$v]}"_* "${ECFS_BASE}/${var[$v]}/"
  ) &
  pids+=("$!")
  if [ "${#pids[@]}" -ge "${MAX_PARALLEL_CP}" ]; then
    wait "${pids[0]}" || { failed=1; echo "ERROR: an ECFS archive transfer failed for varset ${VARSET}" >&2; }
    pids=("${pids[@]:1}")
  fi
done
for pid in "${pids[@]}"; do
  wait "${pid}" || failed=1
done

pids=()
for (( v=0; v<${#var[@]}; v++)); do
  scp "${var[$v]}"_*.nc "${REMOTE_HOST}:${REMOTE_BASE}/${var[$v]}/raw" &
  pids+=("$!")
  if [ "${#pids[@]}" -ge "${MAX_PARALLEL_CP}" ]; then
    wait "${pids[0]}" || failed=1
    pids=("${pids[@]:1}")
  fi
done
for pid in "${pids[@]}"; do
  wait "${pid}" || failed=1
done

if [ "${failed}" -ne 0 ]; then
  echo "ERROR: one or more archive transfers failed for varset ${VARSET} — see above." >&2
  exit 1
fi

echo "$0 (${VARSET}) done."

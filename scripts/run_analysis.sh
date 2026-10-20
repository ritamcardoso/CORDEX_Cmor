#!/bin/bash
#
# scripts/run_analysis.sh — submit the first job of every stream in ORDER.
# Usage: ./submit.sh run_analysis.sh <datebeg yyyymmdd> <dateend yyyymmdd> <year_lim yyyy>
# See README.md §0.
#----------------------------------------------------------------

set -x

#
#--- Repo location (set by submit.sh) ---------------------------
# ROOT_DIR comes from submit.sh; stops if this script was sent with plain sbatch.
#
: "${ROOT_DIR:?ROOT_DIR is not set — submit this script through submit.sh, not plain sbatch (see README.md §0)}"
REPO_DIR="${ROOT_DIR}"

#
#--- Environment (modules from env.site.sh) ---------------------
# Loads env.site.sh, so this job uses the same modules as every other
# job — change them once, in env.site.sh.
#
source "${REPO_DIR}/env.site.sh"

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${NETCDF4_DIR}/lib"

#
#--- Arguments --------------------------------------------------
# datebeg, dateend (yyyymmdd) and year_lim (yyyy), passed on to every job.
#
date

datebeg=$1
dateend=$2
year_lim=$3

echo "$datebeg"
echo "$dateend"

#
#--- Varsets ----------------------------------------------------
# Loads config/varsets.sh and stops if ORDER is empty.
#
source "${REPO_DIR}/config/${CMOR_VARSETS:-varsets.sh}"

if [ "${#ORDER[@]}" -eq 0 ]; then
  echo "ORDER in config/varsets.sh is empty — nothing to submit. (With varsets_single.sh, uncomment one of its ORDER batches first.)" >&2
  exit 1
fi

#
#--- Submit each ORDER entry, 120 s apart -----------------------
# Submits run_out_generic.sh for each ORDER entry; submit.sh adds its
# job name, time, memory and log files from config/varsets.sh.
#
for vs in "${ORDER[@]}"; do
  ${REPO_DIR}/submit.sh "run_out_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${vs}"
  sleep 120
done

echo "$0 done."

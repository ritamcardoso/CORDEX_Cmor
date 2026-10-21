#!/bin/bash
#
# scripts/run_cp_generic.sh — archive one varset's output to ECFS and the remote server.
# Usage: ./submit.sh run_cp_generic.sh <datebeg> <dateend> <year_lim> <varset>
# Normally submitted by run_out_generic.sh. See README.md §7.
#----------------------------------------------------------------

set -x

#
#--- Repo location (set by submit.sh) ---------------------------
# ROOT_DIR comes from submit.sh; stops if this script was sent with plain sbatch.
#
: "${ROOT_DIR:?ROOT_DIR is not set — submit this script through submit.sh, not plain sbatch (see README.md §0)}"
REPO_DIR="${ROOT_DIR}"

#
#--- Arguments --------------------------------------------------
# datebeg dateend year_lim varset; stops if the varset is missing.
#
datebeg=$1
dateend=$2
year_lim=$3
VARSET=$4

if [ -z "${VARSET}" ]; then
  echo "Usage: $0 <datebeg> <dateend> <year_lim> <varset>" >&2
  exit 1
fi

#
#--- Environment: site, experiment, varsets ---------------------
# Loads env.site.sh, the experiment (grids, output and archive paths)
# and config/varsets.sh, then checks the varset exists.
#
source "${REPO_DIR}/env.site.sh"
source "${REPO_DIR}/scripts/load_experiment.sh"
source "${REPO_DIR}/config/${CMOR_VARSETS:-varsets.sh}"

if [ -z "${VARSETS[$VARSET]+x}" ]; then
  echo "Unknown varset '${VARSET}'. Known varsets:" >&2
  printf ' %s\n' "${!VARSETS[@]}" >&2
  exit 1
fi

#
#--- Modules for the archive step -------------------------------
# CP_MODULES from env.site.sh; they can differ from the processing modules.
#
# shellcheck disable=SC2086
module load ${CP_MODULES}

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${NETCDF4_DIR}/lib"

#
#--- Variable list (all groups of the varset) -------------------
# All variables of the varset, from every group; they are the
# prefixes of the output files (<var>_*.nc).
#
IFS=';' read -r -a groups <<< "${VARSETS[$VARSET]}"
var=()
for group in "${groups[@]}"; do
  IFS=',' read -r -a group_vars <<< "${group#*:}"
  var+=("${group_vars[@]}")
done

#
#--- Years ------------------------------------------------------
# First and last year, from datebeg and dateend (printed for the log).
#
date

echo "$datebeg"
echo "$dateend"

yeari=$(echo "$datebeg" | cut -c1-4)
echo "$yeari"
yearf=$(echo "$dateend" | cut -c1-4)
echo "$yearf"

#
#--- Archive, grid by grid (ECFS, then remote) ------------------
# For each grid: copy this job's years of each variable to ECFS and scp them
# to REMOTE_HOST (retried, see COPY_ATTEMPTS); nothing is deleted, and any
# failure makes the job FAILED.
#
shopt -s nullglob
failed=0
COPY_ATTEMPTS="${COPY_ATTEMPTS:-3}"   # scp attempts per variable (env.site.sh)
COPY_WAIT="${COPY_WAIT:-300}"         # seconds between attempts (env.site.sh)
for grid in "${GRIDS[@]}"; do
  echo "Archiving grid ${grid}, ${yeari}-${yearf}: ${OUTPUT_DIR[$grid]} -> ${ECFS_BASE[$grid]}, ${REMOTE_HOST}:${REMOTE_BASE[$grid]}"
  cd "${OUTPUT_DIR[$grid]}" || exit 1

  for (( v=0; v<${#var[@]}; v++)); do
    # This job's years only (<var>_..._<yyyymmdd...>), plus fixed fields (<var>_..._fx.nc)
    files=()
    for (( y=yeari; y<=yearf; y++ )); do
      files+=( "${var[$v]}"_*_"${y}"[0-9][0-9][0-9][0-9]* )
    done
    files+=( "${var[$v]}"_*fx.nc )
    if [ "${#files[@]}" -eq 0 ]; then
      echo "ERROR: no ${var[$v]} files for ${yeari}-${yearf} in ${OUTPUT_DIR[$grid]}" >&2
      failed=1
      continue
    fi
    nc_files=()
    for f in "${files[@]}"; do [[ "${f}" == *.nc ]] && nc_files+=( "${f}" ); done

    emkdir -p "${ECFS_BASE[$grid]}/${var[$v]}" \
      && ecp -o "${files[@]}" "${ECFS_BASE[$grid]}/${var[$v]}/" \
      || { echo "ERROR: ECFS copy of ${var[$v]} (${grid}) failed" >&2; failed=1; }
    if [ "${#nc_files[@]}" -gt 0 ]; then
      # scp to REMOTE_HOST, retried up to COPY_ATTEMPTS times, COPY_WAIT seconds apart
      copied=no
      for (( attempt=1; attempt<=COPY_ATTEMPTS; attempt++ )); do
        if scp "${nc_files[@]}" "${REMOTE_HOST}:${REMOTE_BASE[$grid]}/${var[$v]}/raw/"; then
          copied=yes
          break
        fi
        echo " [WARN] ${var[$v]} (${grid}): copy to ${REMOTE_HOST} failed (attempt ${attempt} of ${COPY_ATTEMPTS})" >&2
        if [ "${attempt}" -lt "${COPY_ATTEMPTS}" ]; then
          sleep "${COPY_WAIT}"
        fi
      done
      if [ "${copied}" != yes ]; then
        echo "ERROR: scp of ${var[$v]} (${grid}) failed after ${COPY_ATTEMPTS} attempts" >&2
        failed=1
      fi
    fi
  done
done

if [ "${failed}" -ne 0 ]; then
  echo "$0 (${VARSET}): some files were not archived — see the errors above. Nothing was deleted." >&2
  exit 1
fi
echo "$0 (${VARSET}) done."

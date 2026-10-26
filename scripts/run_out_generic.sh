#!/bin/bash
#
# scripts/run_out_generic.sh — process one varset, then archive and chain.
# Usage: ./submit.sh run_out_generic.sh <datebeg> <dateend> <year_lim> <varset>
# See README.md §6, §8 and §0.
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
date1=$1
date2=$2
date3=$3
VARSET=$4

datebeg=${date1}
dateend=${date2}
year_lim=${date3}

if [ -z "${VARSET}" ]; then
  echo "Usage: $0 <datebeg> <dateend> <year_lim> <varset>" >&2
  exit 1
fi

#
#--- Environment: site, experiment, varsets ---------------------
# Loads env.site.sh, the experiment (grids, input, output and archive
# paths) and config/varsets.sh, then checks the varset exists.
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
#--- WRF file type (wrfxtrm for wxtrm, else wrfout) -------------
# The wxtrm (and testex) varset reads wrfxtrm files; every other varset
# reads wrfout.
#
wrffile="wrfout"
if [ "${VARSET}" = "wxtrm" ] || [ "${VARSET}" = "testex" ]; then
  wrffile="wrfxtrm"
fi

#
#--- Varset groups ("PROGRAM:var1,var2;PROGRAM:var3") -----------
# Splits VARSETS[varset] into its groups (program pattern + variables).
#
exp="${EXPERIMENT}"
IFS=';' read -r -a groups <<< "${VARSETS[$VARSET]}"

#
#--- Failure handling -------------------------------------------
# A failed compile or program run stops the job with an error, so no
# archive job and no next job are submitted (the job shows as FAILED).
#
fail() {
  echo "ERROR: $* — stopping ${VARSET}: no archive job, no next job." >&2
  exit 1
}

#
#--- Repacking (REPACK="on" in env.site.sh, the default) --------
# Every file a program writes is repacked with ncrepack-cordex (CORDEX
# archive layout: time and time_bnds in one chunk, data rechunked, internal
# metadata at the start of the file). The data are not changed. Needs the
# HDF5 tools h5repack, h5stat and h5dump (from the HDF5 module); the check
# is done here so a missing tool stops the job before any processing.
#
NCREPACK="${NCREPACK:-${REPO_DIR}/tools/ncrepack-cordex}"
if [ "${REPACK:-on}" = "on" ]; then
  for t in h5repack h5stat h5dump; do
    command -v "$t" >/dev/null || fail "$t not found (REPACK=on needs the HDF5 tools: load an HDF5 module, or set REPACK=\"off\" in env.site.sh)"
  done
  [ -x "${NCREPACK}" ] || fail "ncrepack-cordex not found at ${NCREPACK}"
fi

# repack_new <folder> <marker> <name>... : repack the <name>_*.nc files in
# <folder> written after <marker> (this run's files only; other jobs write
# other variables into the same folder at the same time).
repack_new() {
  local dir=$1 marker=$2; shift 2
  local files=() n f
  for n in "$@"; do
    while IFS= read -r f; do files+=("$f"); done \
      < <(find "$dir" -maxdepth 1 -name "${n}_*.nc" -newer "$marker")
  done
  [ ${#files[@]} -gt 0 ] || { echo "repack: no new files for $* in ${dir}"; return 0; }
  "${NCREPACK}" -o "${files[@]}"
}

#
#--- Years and working directory --------------------------------
# First and last year from datebeg/dateend; work happens in
# ${ROOT_RUN_DIR}/<varset>.
#
date

echo $datebeg
echo $dateend

yeari=`echo $datebeg | cut -c1-4`
echo $yeari
yearf=`echo $dateend | cut -c1-4`
echo $yearf

#
#--- Simulation period (variable calendar) -----------------------
# If the grid ini files set sim_start and sim_end ('YYYY-MM-DD_HH', the first
# and the last wrfout file), the programs are built from f90_src_varcalendar:
# they process only the time steps inside the simulation period, which may
# start and end at any hour. The years are limited to the simulation period
# (also for the chain: year_lim is at most the year of sim_end).
# Without sim_start/sim_end: f90_src, whole calendar years (imonth .. nmonths).
#
# ini_key <file> <key>: the value of key = '...' (empty if not set)
ini_key() {
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" "$1" | tail -1
}
VARCAL=0
sim_y0=""; sim_y1=""
for grid in "${GRIDS[@]}"; do
  _ini="${EXPERIMENT_DIR}/${exp}_${DOMAIN_ID[${grid}]}_${grid}.ini"
  _s=$(ini_key "${_ini}" sim_start); _e=$(ini_key "${_ini}" sim_end)
  if [ -n "${_s}${_e}" ]; then
    [ -n "${_s}" ] && [ -n "${_e}" ] || fail "${_ini}: set both sim_start and sim_end (or neither)"
    VARCAL=1
    [ -z "${sim_y0}" ] || [ "${_s:0:4}" -lt "${sim_y0}" ] && sim_y0="${_s:0:4}"
    [ -z "${sim_y1}" ] || [ "${_e:0:4}" -gt "${sim_y1}" ] && sim_y1="${_e:0:4}"
    echo "Grid ${grid}: simulation ${_s} to ${_e} (f90_src_varcalendar)"
  elif [ "${VARCAL}" = "1" ]; then
    fail "${_ini}: no sim_start/sim_end, but another grid of ${exp} has them"
  fi
done
if [ "${VARCAL}" = "1" ]; then
  [ "${yeari}" -lt "${sim_y0}" ] && yeari="${sim_y0}"
  [ "${yearf}" -gt "${sim_y1}" ] && yearf="${sim_y1}"
  [ "${year_lim}" -gt "${sim_y1}" ] && year_lim="${sim_y1}"
  if [ "${yeari}" -gt "${yearf}" ]; then
    echo "${datebeg}-${dateend} is outside the simulation period (${sim_y0}-${sim_y1}): nothing to do, no archive job, no next job."
    exit 0
  fi
  datebeg="${yeari}"; dateend="${yearf}"
  echo "Years ${yeari}-${yearf} (year_lim ${year_lim})"
fi
VARCAL_DIR="${PROG_DIR_VARCAL:-${PROG_DIR%/}_varcalendar}"

RUN_DIR="${ROOT_RUN_DIR}/${VARSET}"
mkdir -p "${RUN_DIR}"

cd "${RUN_DIR}" || exit 1

#
#--- Processing loop: year -> grid -> group -> variable ---------
# For every year, grid, group and variable: build the namelist,
# compile the program and run it.
#
for(( j = ${yeari}; j <= ${yearf}; j++ )) ; do

 START_YY=`echo ${j}`
 END_YY=`echo ${j}`

 #
 # Grid (domain)
 # Each grid of the experiment, with its own ini files and output folder.
 #
 for grid in "${GRIDS[@]}"; do

  dom_id="${DOMAIN_ID[${grid}]}"
  mkdir -p "${OUTPUT_DIR[${grid}]}"

  cp "${EXPERIMENT_DIR}/${exp}_global_${dom_id}_${grid}.ini" global_data.inp

  #
  # Group
  # Each group of the varset: one program pattern and its variables.
  #
  for group in "${groups[@]}"; do
   prog_pattern="${group%%:*}"
   IFS=',' read -r -a var <<< "${group#*:}"

   #
   # Variable
   # Each variable (or level) is a separate run of the program.
   #
   for (( v=0; v<${#var[@]}; v++)); do

    #
    # Namelist: grid ini (placeholders filled in) + variable header
    # inputlist.inp = the grid's ini file with year, WRF file type and
    # paths filled in, plus header/header_<var>.
    #
    sed \
     -e "s|_START_YY_|$START_YY|g" \
     -e "s|_END_YY_|$END_YY|g" \
     -e "s|_WRFFILE_|${wrffile}|g" \
     -e "s|_OUTPUT_WRF_|${OUTPUT_WRF[${grid}]}/|g" \
     -e "s|_OUTPUT_DIR_|${OUTPUT_DIR[${grid}]}/|g" \
     "${EXPERIMENT_DIR}/${exp}_${dom_id}_${grid}.ini" \
     > "${RUN_DIR}/header_${grid}"

    cat header_${grid} > inputlist.inp
    echo "!" >> inputlist.inp
    echo "! Variable" >> inputlist.inp
    echo "!" >> inputlist.inp
    cat ${HEADER_DIR}/header_${var[$v]} >> inputlist.inp
    echo "!" >> inputlist.inp
    echo "/" >> inputlist.inp

    #
    # Program name (VAR -> variable name)
    # The group's pattern with VAR replaced by the variable name.
    #
    PROG_NAME="${prog_pattern/VAR/${var[$v]}}"

    #
    # Compile and run
    # Builds the shared module, the shared subroutines and the program, then
    # runs it; any failure stops the job (see "Failure handling").
    #
    # OpenMP (optional): with OMP_FLAG set in env.site.sh, a program that has
    # a version in f90_src_parallel is built from there with OMP_FLAG and runs
    # with SLURM_CPUS_PER_TASK threads (CPUS in config/varsets.sh).
    src_dir="${PROG_DIR}"; omp=""
    par_dir="${PROG_DIR_PARALLEL:-${PROG_DIR%/}_parallel}"
    # Variable calendar (sim_start/sim_end in the grid ini): the program of
    # f90_src_varcalendar (and its parallel/ copy). Programs without a time
    # loop (fx) are only in f90_src.
    if [ "${VARCAL}" = "1" ]; then
      if [ -f "${VARCAL_DIR}/${PROG_NAME}.f90" ]; then
        src_dir="${VARCAL_DIR}"; par_dir="${VARCAL_DIR}/parallel"
      elif [[ "${PROG_NAME}" != RCM_fx_* && "${PROG_NAME}" != RCM_sfc_mrsofc ]]; then
        fail "${PROG_NAME}.f90 is not in ${VARCAL_DIR} (sim_start/sim_end are set in the grid ini)"
      fi
    fi
    if [ -n "${OMP_FLAG:-}" ] && [ -f "${par_dir}/${PROG_NAME}.f90" ]; then
      src_dir="${par_dir}"; omp="${OMP_FLAG}"
      export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
      echo "OpenMP: ${PROG_NAME} from ${par_dir}, ${OMP_NUM_THREADS} thread(s)"
    fi
    # shellcheck disable=SC2086
    $FC $FFLAGS $omp -c "${PROG_DIR}/${MOD_NAME}.f90" || fail "compiling ${MOD_NAME}.f90 failed"
    # Moist thermodynamics (saturation, LCL, theta_e, parcel with ice): its own module,
    # after datvar_s (HUM_NAME in env.site.sh; humidity_subs if unset)
    HUM_NAME="${HUM_NAME:-humidity_subs}"
    # shellcheck disable=SC2086
    $FC $FFLAGS $omp -c "${PROG_DIR}/${HUM_NAME}.f90" || fail "compiling ${HUM_NAME}.f90 failed"
    # shellcheck disable=SC2086
    $FC $FFLAGS $omp -c "${PROG_DIR}/${SUB_NAME}.f90" $NC_INC || fail "compiling ${SUB_NAME}.f90 failed"
    # Land use and urban cells (urban_cell, landuse_field): after shared_subs, whose ncerror it
    # uses (LU_NAME in env.site.sh; landuse_subs if unset)
    LU_NAME="${LU_NAME:-landuse_subs}"
    # shellcheck disable=SC2086
    $FC $FFLAGS $omp -c "${PROG_DIR}/${LU_NAME}.f90" $NC_INC || fail "compiling ${LU_NAME}.f90 failed"
    # Every -L folder in ALL_LIBS is also written into the executable
    # (rpath), so it finds the NetCDF/HDF5 libraries it was linked with even
    # when the loaded modules don't put them on LD_LIBRARY_PATH.
    RPATH=""
    for w in $ALL_LIBS; do
      case "$w" in -L?*) RPATH+=" -Wl,-rpath,${w#-L}" ;; esac
    done
    # shellcheck disable=SC2086
    $FC $FFLAGS $omp ${src_dir}/${PROG_NAME}.f90 ${MOD_NAME}.o ${HUM_NAME}.o ${SUB_NAME}.o ${LU_NAME}.o -o ${PROG_NAME}.exe $ALL_LIBS $RPATH \
      || fail "compiling ${PROG_NAME}.f90 failed"

    touch repack_marker
    ./${PROG_NAME}.exe
    rc=$?
    [ "$rc" -eq 0 ] || fail "${PROG_NAME}.exe failed (exit code ${rc}) for ${var[$v]}, ${grid}, ${j}"

    #
    # Repack the files this run wrote (the uava programs also write ua<level>)
    #
    if [ "${REPACK:-on}" = "on" ]; then
      names=("${var[$v]}")
      [[ "${PROG_NAME}" == *uava* && "${var[$v]}" == va* ]] && names+=("ua${var[$v]#va}")
      repack_new "${OUTPUT_DIR[${grid}]}" repack_marker "${names[@]}" \
        || fail "repacking ${names[*]} failed for ${grid}, ${j} (the files are kept as written)"
    fi
    rm -f repack_marker

    rm inputlist.inp
    rm header_${grid}

   done #var
  done #group
 done #domain (grid)
done #year

#
#--- Archive job(s), if ARCHIVE="on": varset + CP_EXTRA companion
# If ARCHIVE="on" in env.site.sh: archive this varset, and its CP_EXTRA
# companion if it has one (submit.sh fills in the job flags).
#
if [ "${ARCHIVE:-on}" = "on" ]; then
  ${REPO_DIR}/submit.sh "run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${VARSET}"

  extra="${CP_EXTRA[$VARSET]:-}"
  if [ -n "${extra}" ]; then
    ${REPO_DIR}/submit.sh "run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${extra}"
  fi
else
  echo "ARCHIVE=\"${ARCHIVE}\" in env.site.sh — no archive job submitted."
fi

#
#--- Chain to the next varset (NEXT[], ADVANCE_YEAR[]) ----------
# Submits NEXT[varset] while year_lim isn't passed: non-advancing links
# keep the dates, the advancing link moves on to the next block of years.
#
next="${NEXT[$VARSET]}"
if [ "${ADVANCE_YEAR[$VARSET]:-0}" = "1" ]; then
  chain_ok=0
  [ "$yearf" -lt "$year_lim" ] && chain_ok=1
else
  chain_ok=0
  [ "$yeari" -le "$year_lim" ] && chain_ok=1
fi

if [ -n "${next}" ] && [ "$chain_ok" = "1" ]; then
  next_datebeg="${datebeg}"
  next_dateend="${dateend}"
  #
  # Advancing link: next block of the same length, after this one, up to year_lim
  # Next block: the year after this job's last year, same length, up to year_lim.
  #
  if [ "${ADVANCE_YEAR[$VARSET]:-0}" = "1" ]; then
    next_datebeg=$(( yearf + 1 ))
    next_dateend=$(( yearf + 1 + yearf - yeari ))
    [ "$next_dateend" -gt "$year_lim" ] && next_dateend="$year_lim"
  fi
  ${REPO_DIR}/submit.sh "run_out_generic.sh" "${next_datebeg}" "${next_dateend}" "${year_lim}" "${next}"
fi
echo "$0 (${VARSET}) done."

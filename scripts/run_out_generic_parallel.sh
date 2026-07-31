#!/bin/bash
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --hint=nomultithread
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt
#
# scripts/run_out_generic_parallel.sh
#
# Parallel variant of run_out_generic.sh: runs up to MAX_PARALLEL_RUN
# variables concurrently instead of one at a time. NOT a drop-in
# replacement — read this whole header before using it.
#
# WHY THIS NEEDS TO BE A SEPARATE SCRIPT, NOT JUST A FLAG ON THE ORIGINAL:
# every RCM program reads two fixed filenames — inputlist.inp and
# global_data.inp — from its current working directory (hardcoded in
# f90_src/shared_subs_v2.f90: read_cordex_config('inputlist.inp'),
# read_global_metadata('global_data.inp')). run_out_generic.sh writes both
# directly into RUN_DIR and runs one variable at a time, which is fine
# serially but would corrupt output if two variables' programs raced on
# the same inputlist.inp. This script instead gives every concurrent
# variable its own subdirectory under RUN_DIR (a copy of global_data.inp,
# its own inputlist.inp, a symlink to the shared compiled .exe) so they
# can safely run at once.
#
# WHEN TO USE THIS: only if your site's Slurm setup actually allows a
# batch job to run several processes concurrently on its allocation (some
# HPC configs/queues don't — see README.md, "Notes"). If you're not sure,
# ask your HPC's helpdesk before relying on this, or just use
# run_out_generic.sh (MAX_PARALLEL_RUN=1 in env.site.sh is equivalent here,
# minus the working-directory overhead).
#
# RESOURCES: this requests --cpus-per-task=4 above (vs =1 implied on
# run_out_generic.sh) to actually have something to run concurrently on —
# adjust this AND MAX_PARALLEL_RUN (in env.site.sh — see below) together to
# match your node/queue's real core count and how CPU-heavy each RCM
# program is.
#
# Usage — identical to run_out_generic.sh, same 4 positional args:
#   $ROOT_DIR/submit.sh --job-name=wrf-<varset> --time=<hh:mm:ss> \
#          --output=wrf-<varset>.%j.out --error=wrf-<varset>.%j.out \
#          run_out_generic_parallel.sh <datebeg> <dateend> <year_lim> <varset>
#
# MAX_PARALLEL_RUN caps how many variables run at once — set it in
# env.site.sh (see env.site.sh.example; default there is 4), not by editing
# this script. Keep it <= --cpus-per-task above.
#
# Same FORCE_REBUILD=1 / FORCE_REPROCESS=1 overrides as run_out_generic.sh.
#
# Chains to run_cp_generic.sh and NEXT[] exactly like run_out_generic.sh —
# see that script's header for details on the archiving/chaining behaviour,
# not repeated here.
#----------------------------------------------------------------

set -x

# ROOT_DIR must be set in your environment (e.g. exported from ~/.bashrc) —
# NOT auto-detected from $0/dirname. See run_out_generic.sh / README.md:
# "Where the code lives" for why.
: "${ROOT_DIR:?ROOT_DIR is not set. export ROOT_DIR=/path/to/this/repo (e.g. in ~/.bashrc) before submitting — see README.md}"
REPO_DIR="${ROOT_DIR}"

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

#----------------------------------------------------------------
#                          ENVIRONMENT                            |
#----------------------------------------------------------------
source "${REPO_DIR}/env.site.sh"
source "${REPO_DIR}/config/varsets.sh"

if [ -z "${VARSETS[$VARSET]+x}" ]; then
  echo "Unknown varset '${VARSET}'. Known varsets:" >&2
  printf ' %s\n' "${!VARSETS[@]}" >&2
  exit 1
fi

ini_kind=""
if [ "${VARSET}" = "wxtrm" ]; then
  ini_kind="xtrm_"
fi

exp="${EXPERIMENT:?No EXPERIMENT set in env.site.sh — add EXPERIMENT=\"cordex\" (or \"fpsurb\") near OUTPUT_WRF/OUTPUT_DIR}"

IFS=';' read -r -a groups <<< "${VARSETS[$VARSET]}"

MAX_PARALLEL_RUN="${MAX_PARALLEL_RUN:-4}"   # set in env.site.sh — see env.site.sh.example

#----------------------------------------------------------------
#                        Processing                               |
#----------------------------------------------------------------
date

echo $datebeg
echo $dateend

yeari=`echo $datebeg | cut -c1-4`
echo $yeari
yearf=`echo $dateend | cut -c1-4`
echo $yearf

RUN_DIR="${ROOT_RUN_DIR}/${VARSET}"
mkdir -p "${RUN_DIR}"

cd "${RUN_DIR}" || exit 1

#----------------------------------------------------------------
# Compile everything this varset needs up front, serially, before any
# parallel dispatch. This MUST stay serial and MUST happen before the
# loops below: two concurrent variables both compiling the same PROG_NAME
# for the first time would race on the same .exe file. Same cache logic as
# run_out_generic.sh (skipped if already built; FORCE_REBUILD=1 to force).
#----------------------------------------------------------------
if [ "${FORCE_REBUILD:-0}" = "1" ] || [ ! -f "${MOD_NAME}.o" ]; then
  $FC $FFLAGS -c "${PROG_DIR}/${MOD_NAME}.f90"
fi
if [ "${FORCE_REBUILD:-0}" = "1" ] || [ ! -f "${SUB_NAME}.o" ]; then
  $FC $FFLAGS -c "${PROG_DIR}/${SUB_NAME}.f90" $NC_INC
fi

declare -A COMPILED_PROGS=()
for group in "${groups[@]}"; do
  prog_pattern="${group%%:*}"
  IFS=',' read -r -a group_vars <<< "${group#*:}"
  for gv in "${group_vars[@]}"; do
    prog_name="${prog_pattern/VAR/${gv}}"
    if [ "${FORCE_REBUILD:-0}" = "1" ] || [ -z "${COMPILED_PROGS[$prog_name]+x}" ]; then
      $FC $FFLAGS ${PROG_DIR}/${prog_name}.f90 ${MOD_NAME}.o ${SUB_NAME}.o -o ${prog_name}.exe $ALL_LIBS
      COMPILED_PROGS[$prog_name]=1
    fi
  done
done

#
#  Time Loop (yeari <= yearf; it is usually =)
#
run_failed=0

for(( j = ${yeari}; j <= ${yearf}; j++ )) ; do

 START_YY=`echo ${j}`
 END_YY=`echo ${j}`
#
# Domain
#
 for grid in "${!run[@]}"; do

  dom_id="${DOMAIN_ID[${grid}]:?No DOMAIN_ID set for '${grid}' in env.site.sh — add [${grid}]=\"<CORDEX-domain-id>\" to the DOMAIN_ID array}"

  sed \
   -e "s|_START_YY_|$START_YY|g" \
   -e "s|_END_YY_|$END_YY|g" \
   -e "s|_OUTPUT_WRF_|${OUTPUT_WRF}/|g" \
   -e "s|_OUTPUT_DIR_|${OUTPUT_DIR}/|g" \
   "${HEADER_INI_DIR}/${exp}_${ini_kind}${dom_id}_${grid}.ini" \
   > "${RUN_DIR}/header_${grid}_${START_YY}"

  global_ini="${HEADER_INI_DIR}/${exp}_global_${dom_id}_${grid}.ini"

#
# Variables (a varset can have more than one group — see config/varsets.sh)
#
  pids=()
  work_dirs=()   # parallel array to pids/below: WORK_DIR<TAB>var, for cleanup after the wait loop
  for group in "${groups[@]}"; do
   prog_pattern="${group%%:*}"
   IFS=',' read -r -a var <<< "${group#*:}"

   for (( v=0; v<${#var[@]}; v++)); do
#
# Skip if this variable's output for this year already exists (same check
# as run_out_generic.sh). FORCE_REPROCESS=1 to redo it anyway.
#
    existing=( "${OUTPUT_DIR}/${var[$v]}"_*"${START_YY}"*.nc )
    if [ "${FORCE_REPROCESS:-0}" != "1" ] && [ -e "${existing[0]}" ]; then
      echo "Skipping ${var[$v]} ${START_YY}: output already exists (${existing[0]}). Set FORCE_REPROCESS=1 to redo it."
      continue
    fi

    PROG_NAME="${prog_pattern/VAR/${var[$v]}}"
    WORK_DIR="${RUN_DIR}/.work_${grid}_${START_YY}_${var[$v]}"

    (
      set -e
      mkdir -p "${WORK_DIR}"
      cd "${WORK_DIR}"
      cp "${global_ini}" global_data.inp
      cat "${RUN_DIR}/header_${grid}_${START_YY}" > inputlist.inp
      echo "!" >> inputlist.inp
      echo "! Variable" >> inputlist.inp
      echo "!" >> inputlist.inp
      cat "${HEADER_DIR}/header_${var[$v]}" >> inputlist.inp
      echo "!" >> inputlist.inp
      echo "/" >> inputlist.inp
      "${RUN_DIR}/${PROG_NAME}.exe"
    ) &
    pids+=("$!")
    work_dirs+=("${WORK_DIR}$(printf '\t')${var[$v]}")

    if [ "${#pids[@]}" -ge "${MAX_PARALLEL_RUN}" ]; then
      wait "${pids[0]}" || { run_failed=1; echo "ERROR: a variable run failed (grid=${grid}, year=${START_YY})" >&2; }
      pids=("${pids[@]:1}")
    fi

   done #var
  done #group

  for pid in "${pids[@]}"; do
    wait "${pid}" || run_failed=1
  done

  rm -f "${RUN_DIR}/header_${grid}_${START_YY}"

  # Clean up successful WORK_DIRs; leave failed ones (any still containing
  # inputlist.inp — the .exe only removes/renames its own output, it
  # doesn't touch its inputs) so you can inspect/rerun them by hand.
  for entry in "${work_dirs[@]}"; do
    d="${entry%%$(printf '\t')*}"
    var_name="${entry#*$(printf '\t')}"
    [ -d "${d}" ] || continue
    existing=( "${OUTPUT_DIR}/${var_name}"_*"${START_YY}"*.nc )
    if [ -e "${existing[0]}" ]; then
      rm -rf "${d}"
    else
      echo "WARNING: keeping ${d} for inspection — no matching output found in OUTPUT_DIR after it ran." >&2
    fi
  done

 done #domain (grid)
done #year

if [ "${run_failed}" -ne 0 ]; then
  echo "ERROR: one or more variable runs failed for varset ${VARSET} — see above. Not chaining further." >&2
  exit 1
fi

#----------------------------------------------------------------
# Archive + chain — identical to run_out_generic.sh (see its header).
#----------------------------------------------------------------
${REPO_DIR}/submit.sh --job-name="cp-${VARSET}" --time="${CP_TIME[$VARSET]:-$DEFAULT_CP_TIME}" \
      --output="cp-${VARSET}.%j.out" --error="cp-${VARSET}.%j.out" \
      "run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${VARSET}"

extra="${CP_EXTRA[$VARSET]:-}"
if [ -n "${extra}" ]; then
  ${REPO_DIR}/submit.sh --job-name="cp-${extra}" --time="${CP_TIME[$extra]:-$DEFAULT_CP_TIME}" \
        --output="cp-${extra}.%j.out" --error="cp-${extra}.%j.out" \
        "run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${extra}"
fi

next="${NEXT[$VARSET]}"
if [ -n "${next}" ] && [ "$yeari" -le "$year_lim" ]; then
  next_datebeg="${datebeg}"
  next_dateend="${dateend}"
  if [ "${ADVANCE_YEAR[$VARSET]:-0}" = "1" ]; then
    next_datebeg=$(( yeari + 1 ))
    next_dateend=$(( yearf + 1 ))
  fi
  ${REPO_DIR}/submit.sh --job-name="wrf-${next}" --time="${TIME[$next]}" \
        --output="wrf-${next}.%j.out" --error="wrf-${next}.%j.out" \
        "run_out_generic_parallel.sh" "${next_datebeg}" "${next_dateend}" "${year_lim}" "${next}"
fi

echo "$0 (${VARSET}) done."

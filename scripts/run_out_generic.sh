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
# scripts/run_out_generic.sh
#
# Generic replacement for run_out.sh, run_out_rad.sh, run_out_soil.sh, ...
# (all run_out_* variants in this repo). Which variables/programs it runs is
# looked up from config/varsets.sh using the 4th argument.
#
# --account/--mail-user/--chdir above are the only site-specific bits left
# in this file (there are only 3 scripts total now, so it's simpler to just
# edit them directly in each than to maintain a shared-options mechanism —
# see run_cp_generic.sh and run_Analysis_v2.sh for the other two).
#
# Usage (ROOT_DIR must be exported first — see README.md):
#   export ROOT_DIR=/path/to/this/repo
#   sbatch --job-name=wrf-<varset> --time=<hh:mm:ss> \
#          --output=wrf-<varset>.%j.out --error=wrf-<varset>.%j.out \
#          $ROOT_DIR/scripts/run_out_generic.sh <datebeg> <dateend> <year_lim> <varset>
#
# You can submit from anywhere (e.g. $SCRATCH/Analysis) — ROOT_DIR is what
# tells this script (and everything it chains to) where the actual code,
# config, and env.site.sh live; it does not need to match your cwd.
#
# (--job-name / --time / --output / --error on the command line override
#  the #SBATCH defaults above, so you don't need a separate file per
#  varset just to change those.)
#
# At the end of its year loop this script also submits
# scripts/run_cp_generic.sh for the same varset (archiving to ECFS/remote),
# unconditionally — matching the original scripts' unconditional call to
# their run_cp_<varset>.sh sibling — plus a second cp call for its "u"
# companion where config/varsets.sh:CP_EXTRA[<varset>] is set (plev_uava,
# zlev_uava0, zlev_uava1). It then re-submits itself for whatever
# config/varsets.sh:NEXT[<varset>] points to (only if year_lim hasn't been
# reached yet) — mirroring the original scripts' self/pair-resubmission
# pattern (e.g. out<->soil, or zlev_ta<->plev_ta).
#
# Compiling is cached within a single run: the shared module/subroutines
# build once (not once per variable/year), and each PROG_NAME.exe builds
# once even for fixed-program groups shared across many variables/levels
# (e.g. RCM_plev_ta across all 16 pressure levels) — set FORCE_REBUILD=1 to
# bypass the cache (e.g. after editing f90_src/).
#
# Per-variable, per-year output is skipped if it already exists in
# OUTPUT_DIR — safe to rerun/resubmit without reprocessing finished years.
# Set FORCE_REPROCESS=1 to reprocess regardless.
#----------------------------------------------------------------

set -x

# ROOT_DIR must be set in your environment (e.g. exported from ~/.bashrc) —
# NOT auto-detected from $0/dirname. Slurm copies the submitted script into
# a spool directory before running it, so $0 at runtime often does not
# point at this repo at all, especially when you submit from a different
# working directory (e.g. $SCRATCH/Analysis) than where the code lives
# (ROOT_DIR). See README.md: "Where the code lives".
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
# site/user-specific paths, modules, compiler flags -> env.site.sh
source "${REPO_DIR}/env.site.sh"

# variable-set definitions, walltimes, chaining -> config/varsets.sh
source "${REPO_DIR}/config/varsets.sh"

if [ -z "${VARSETS[$VARSET]+x}" ]; then
  echo "Unknown varset '${VARSET}'. Known varsets:" >&2
  printf ' %s\n' "${!VARSETS[@]}" >&2
  exit 1
fi

# The xtrm variant of the grid/domain-setup ini (<exp>_xtrm_<dom_id>_<grid>.ini,
# sourced from wrfxtrm rather than wrfout — see header_ini/README.md) is only
# correct for the varset that actually runs RCM_sfc_xtrm. Every other varset
# keeps using the plain <exp>_<dom_id>_<grid>.ini.
ini_kind=""
if [ "${VARSET}" = "wxtrm" ]; then
  ini_kind="xtrm_"
fi

# EXPERIMENT is a single site-wide value, not per-grid — an experiment can
# span multiple domains (e.g. fpsurb runs both d01 and d02), unlike
# DOMAIN_ID which does vary per grid within an experiment.
exp="${EXPERIMENT:?No EXPERIMENT set in env.site.sh — add EXPERIMENT=\"cordex\" (or \"fpsurb\") near OUTPUT_WRF/OUTPUT_DIR}"

# VARSETS[$VARSET] looks like "PROGRAM_A:var1,var2;PROGRAM_B:var3,var4"
# (one or more ';'-separated groups; each a program pattern + its variables)
IFS=';' read -r -a groups <<< "${VARSETS[$VARSET]}"

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
# Compile the shared module + subroutines exactly once per run — these
# (datvar_s.f90 / shared_subs_v2.f90 by default) don't depend on
# year/grid/variable/program at all, so recompiling them inside the loop
# below (once per variable, per year) was pure waste. Skipped if the .o
# already exists in RUN_DIR (e.g. a rerun in a reused scratch dir); set
# FORCE_REBUILD=1 to force a clean recompile (e.g. after editing f90_src/).
#----------------------------------------------------------------
if [ "${FORCE_REBUILD:-0}" = "1" ] || [ ! -f "${MOD_NAME}.o" ]; then
  $FC $FFLAGS -c "${PROG_DIR}/${MOD_NAME}.f90"
fi
if [ "${FORCE_REBUILD:-0}" = "1" ] || [ ! -f "${SUB_NAME}.o" ]; then
  $FC $FFLAGS -c "${PROG_DIR}/${SUB_NAME}.f90" $NC_INC
fi

# Per-program compile cache for this run — see PROG_NAME compile step
# below. A program's .exe is identical across every year/grid it's used
# for, so once built it's reused rather than rebuilt on every iteration.
declare -A COMPILED_PROGS=()

#
#  Time Loop (yeari <= yearf; it is usually =)
#
for(( j = ${yeari}; j <= ${yearf}; j++ )) ; do

 START_YY=`echo ${j}`
 END_YY=`echo ${j}`
#
# Domain
#
 for grid in "${!run[@]}"; do

  dom_id="${DOMAIN_ID[${grid}]:?No DOMAIN_ID set for '${grid}' in env.site.sh — add [${grid}]=\"<CORDEX-domain-id>\" to the DOMAIN_ID array}"

  cp ${HEADER_INI_DIR}/${exp}_global_${dom_id}_${grid}.ini  global_data.inp

#
# Variables (a varset can have more than one group — see config/varsets.sh)
#
  for group in "${groups[@]}"; do
   prog_pattern="${group%%:*}"
   IFS=',' read -r -a var <<< "${group#*:}"

   for (( v=0; v<${#var[@]}; v++)); do
#
# Skip if this variable's output for this year already exists — makes a
# rerun/resubmit safe without reprocessing years that already succeeded.
# Set FORCE_REPROCESS=1 to reprocess regardless (e.g. after a source fix).
#
    existing=( "${OUTPUT_DIR}/${var[$v]}"_*"${START_YY}"*.nc )
    if [ "${FORCE_REPROCESS:-0}" != "1" ] && [ -e "${existing[0]}" ]; then
      echo "Skipping ${var[$v]} ${START_YY}: output already exists (${existing[0]}). Set FORCE_REPROCESS=1 to redo it."
      continue
    fi
#
#  Create list from header_d0?.ini + header_[var]
#
    sed \
     -e "s|_START_YY_|$START_YY|g" \
     -e "s|_END_YY_|$END_YY|g" \
     -e "s|_OUTPUT_WRF_|${OUTPUT_WRF}/|g" \
     -e "s|_OUTPUT_DIR_|${OUTPUT_DIR}/|g" \
     "${HEADER_INI_DIR}/${exp}_${ini_kind}${dom_id}_${grid}.ini" \
     > "${RUN_DIR}/header_${grid}"
    
    cat header_${grid} > inputlist.inp
    echo "!" >> inputlist.inp
    echo "! Variable" >> inputlist.inp
    echo "!" >> inputlist.inp
    cat ${HEADER_DIR}/header_${var[$v]} >> inputlist.inp
    echo "!" >> inputlist.inp
    echo "/" >> inputlist.inp
#
# Program name: literal, or with "VAR" substituted for the current variable
# (see config/varsets.sh header comment for examples).
#
    PROG_NAME="${prog_pattern/VAR/${var[$v]}}"
#
# Compiling — cached per PROG_NAME for the lifetime of this run (see
# COMPILED_PROGS above). A fixed-program group (e.g. RCM_plev_ta, shared
# by all 16 pressure levels) previously recompiled the identical .exe once
# per variable, per year; now it's built once and reused.
#
    if [ "${FORCE_REBUILD:-0}" = "1" ] || [ -z "${COMPILED_PROGS[$PROG_NAME]+x}" ]; then
      $FC $FFLAGS ${PROG_DIR}/${PROG_NAME}.f90 ${MOD_NAME}.o ${SUB_NAME}.o -o ${PROG_NAME}.exe $ALL_LIBS
      COMPILED_PROGS[$PROG_NAME]=1
    fi

    ./${PROG_NAME}.exe

    rm inputlist.inp
    rm header_${grid}

   done #var
  done #group
 done #domain (grid)
done #year

#----------------------------------------------------------------
# Archive this varset's output (config/varsets.sh: CP_TIME[]) — matches the
# original scripts' unconditional call to their run_cp_<varset>.sh sibling.
# plev_uava/zlev_uava0/zlev_uava1 need a second cp call for their "u"
# companion (config/varsets.sh: CP_EXTRA[]), since they only process "v"
# but the underlying programs also produce matching "u" files.
#----------------------------------------------------------------
# cd ${REPO_DIR}
 ${REPO_DIR}/submit.sh --job-name="cp-${VARSET}" --time="${CP_TIME[$VARSET]:-$DEFAULT_CP_TIME}" \
       --output="cp-${VARSET}.%j.out" --error="cp-${VARSET}.%j.out" \
       "run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${VARSET}"

extra="${CP_EXTRA[$VARSET]:-}"
if [ -n "${extra}" ]; then
  ${REPO_DIR}/submit.sh --job-name="cp-${extra}" --time="${CP_TIME[$extra]:-$DEFAULT_CP_TIME}" \
         --output="cp-${extra}.%j.out" --error="cp-${extra}.%j.out" \
         "run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${extra}"
fi

#----------------------------------------------------------------
# Auto-chain to the next varset in the pipeline (config/varsets.sh: NEXT[])
#----------------------------------------------------------------
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
         "run_out_generic.sh" "${next_datebeg}" "${next_dateend}" "${year_lim}" "${next}"
fi

echo "$0 (${VARSET}) done."

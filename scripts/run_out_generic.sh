#!/bin/bash
#SBATCH --job-name=wrf-out
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=18:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=wrf-out.%j.out
#SBATCH --error=wrf-out.%j.out
#SBATCH --account=
#SBATCH --mail-type=ALL
#SBATCH --mail-user=
#SBATCH --chdir=
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
#
#  Time Loop (yeari <= yearf; it is usually =)
#
for(( j = ${yeari}; j <= ${yearf}; j++ )) ; do

 START_YY=`echo ${j}`
 END_YY=`echo ${j}`
#
# Domain
#
 for (( r=0; r<${#run[@]}; r++)); do

  dom_id="${DOMAIN_ID[${run[$r]}]:?No DOMAIN_ID set for '${run[$r]}' in env.site.sh — add [${run[$r]}]=\"<CORDEX-domain-id>\" to the DOMAIN_ID array}"
  exp="${EXPERIMENT[${run[$r]}]:?No EXPERIMENT set for '${run[$r]}' in env.site.sh — add [${run[$r]}]=\"<experiment-name>\" to the EXPERIMENT array}"

  cp ${HEADER_INI_DIR}/${exp}_global_${dom_id}_${run[$r]}.ini  global_data.inp

#
# Variables (a varset can have more than one group — see config/varsets.sh)
#
  for group in "${groups[@]}"; do
   prog_pattern="${group%%:*}"
   IFS=',' read -r -a var <<< "${group#*:}"

   for (( v=0; v<${#var[@]}; v++)); do
#
#  Create list from header_d0?.ini + header_[var]
#
    cat ${HEADER_INI_DIR}/${exp}_${ini_kind}${dom_id}_${run[$r]}.ini | sed \
      -e "s|_START_YY_|$START_YY|g" \
      -e "s|_END_YY_|$END_YY|g" \
      -e "s|_OUTPUT_WRF_|${OUTPUT_WRF}/|g" \
      -e "s|_OUTPUT_DIR_|${OUTPUT_DIR}/|g" \
      -e "s|_OUT_DOM_|$OUT_DOM|g" \
      > ${RUN_DIR}/header_${run[$r]}

    cat header_${run[$r]} > inputlist.inp
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
# Compiling
#
    $FC $FFLAGS -c "${PROG_DIR}/${MOD_NAME}.f90"
    $FC $FFLAGS -c "${PROG_DIR}/${SUB_NAME}.f90" $NC_INC
    $FC $FFLAGS ${PROG_DIR}/${PROG_NAME}.f90 ${MOD_NAME}.o ${SUB_NAME}.o -o ${PROG_NAME}.exe $ALL_LIBS

    ./${PROG_NAME}.exe

    rm inputlist.inp
    rm header_${run[$r]}

   done #var
  done #group
 done #dom
done #year

#----------------------------------------------------------------
# Archive this varset's output (config/varsets.sh: CP_TIME[]) — matches the
# original scripts' unconditional call to their run_cp_<varset>.sh sibling.
# plev_uava/zlev_uava0/zlev_uava1 need a second cp call for their "u"
# companion (config/varsets.sh: CP_EXTRA[]), since they only process "v"
# but the underlying programs also produce matching "u" files.
#----------------------------------------------------------------
sbatch --job-name="cp-${VARSET}" --time="${CP_TIME[$VARSET]:-$DEFAULT_CP_TIME}" \
       --output="cp-${VARSET}.%j.out" --error="cp-${VARSET}.%j.out" \
       "${REPO_DIR}/scripts/run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${VARSET}"

extra="${CP_EXTRA[$VARSET]:-}"
if [ -n "${extra}" ]; then
  sbatch --job-name="cp-${extra}" --time="${CP_TIME[$extra]:-$DEFAULT_CP_TIME}" \
         --output="cp-${extra}.%j.out" --error="cp-${extra}.%j.out" \
         "${REPO_DIR}/scripts/run_cp_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${extra}"
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
  sbatch --job-name="wrf-${next}" --time="${TIME[$next]}" \
         --output="wrf-${next}.%j.out" --error="wrf-${next}.%j.out" \
         "${REPO_DIR}/scripts/run_out_generic.sh" "${next_datebeg}" "${next_dateend}" "${year_lim}" "${next}"
fi

echo "$0 (${VARSET}) done."

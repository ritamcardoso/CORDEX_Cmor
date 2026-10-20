#!/bin/bash
#
# run.sh — the simple way to start the processing.
# Usage: ./run.sh [-n] [-c] <experiment> <first year> [<last year>] [<varset> ...]
#   ./run.sh fpsurb 2015 2020            every stream, 2015 to 2020, one year per job
#   ./run.sh fpsurb 2015                 every stream, 2015 only
#   ./run.sh fpsurb 2015 2020 soil fx    only the varsets soil and fx
#   ./run.sh -n fpsurb 2015 2020         dry run: checks and shows what would be submitted
# It works out the dates and year_lim, checks the setup, and calls submit.sh
# (README.md §0). The job settings still come from env.site.sh and config/.
#----------------------------------------------------------------

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 [-n] [-c] <experiment> <first year> [<last year>] [<varset> ...]

  <experiment>  a folder in experiments/ (e.g. cordex, fpsurb, lucas)
  <first year>  first year to process
  <last year>   last year to process (default: the first year)
  <varset> ...  only these varsets (see config/varsets.sh). Each one runs on
                its own (config/varsets_single.sh): it processes a year,
                submits its archive job and resubmits itself for the next
                year. Without varsets: every stream of config/varsets.sh,
                through run_analysis.sh.
  -c            with varsets: let them hand over to the next varset of their
                stream (config/varsets.sh) instead of running on their own
  -n            dry run: do the checks and show the commands, submit nothing

Examples:
  $0 fpsurb 2015 2020
  $0 fpsurb 2015 2015 soil
  $0 -n cordex 2001 2005
EOF
  exit 1
}

DRY=0; CHAIN=0
while getopts "nch" opt; do
  case "$opt" in
    n) DRY=1 ;;
    c) CHAIN=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 2 ] || usage

EXP="$1"; Y1="$2"; shift 2
Y2="$Y1"
if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]{4}$ ]]; then Y2="$1"; shift; fi
VSETS=("$@")

ROOT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
SUBMIT="${ROOT_DIR}/submit.sh"
errors=0
err()  { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARNING: $*" >&2; }

#
#--- Checks -----------------------------------------------------
# Years, env.site.sh, the experiment (grids, ini files), the varsets and the
# WRF input of the first year. All problems are listed before stopping.
#
[[ "$Y1" =~ ^[0-9]{4}$ && "$Y2" =~ ^[0-9]{4}$ ]] || { echo "Years must be 4 digits, e.g. 2015 2020." >&2; usage; }
[ "$Y1" -le "$Y2" ] || { echo "The first year ($Y1) is after the last year ($Y2)." >&2; exit 1; }
[ -f "${ROOT_DIR}/env.site.sh" ] || err "no env.site.sh — copy env.site.sh.example to env.site.sh and fill it in (README §4)"
if [ ! -f "${ROOT_DIR}/experiments/${EXP}/${EXP}.sh" ]; then
  avail=("${ROOT_DIR}"/experiments/*/); avail=("${avail[@]%/}")
  echo "No experiment '${EXP}' (experiments/${EXP}/${EXP}.sh). Available: ${avail[*]##*/}" >&2
  exit 1
fi

# layout: every stream (varsets.sh), or the given varsets on their own (varsets_single.sh)
if [ ${#VSETS[@]} -gt 0 ] && [ "$CHAIN" = 0 ]; then LAYOUT=varsets_single.sh; else LAYOUT=varsets.sh; fi
[ -f "${ROOT_DIR}/config/${LAYOUT}" ] || { echo "No config/${LAYOUT}." >&2; exit 1; }

# experiment: grids and WRF input folders (in a subshell; load_experiment.sh checks the ini files)
exp_info="$(
  set +u
  export ROOT_DIR CMOR_EXPERIMENT="$EXP"
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/scripts/load_experiment.sh" >/dev/null || exit 1
  for g in "${GRIDS[@]}"; do echo "$g ${DOMAIN_ID[$g]} ${OUTPUT_WRF[$g]} ${OUTPUT_DIR[$g]}"; done
)" || { echo "The experiment '${EXP}' has a problem (see the message above)." >&2; exit 1; }

# varsets: known in the layout, and what ORDER holds
vs_info="$(
  set +eu
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/config/${LAYOUT}" >/dev/null 2>&1
  echo "ORDER ${ORDER[*]}"
  echo "ALL ${!VARSETS[*]}"
)"
order=$(sed -n 's/^ORDER //p' <<< "$vs_info"); known=" $(sed -n 's/^ALL //p' <<< "$vs_info") "
for vs in ${VSETS[@]+"${VSETS[@]}"}; do
  [[ "$known" == *" $vs "* ]] || err "unknown varset '$vs' (not in config/${LAYOUT}); known: $(tr ' ' '\n' <<< "$known" | sed '/^$/d' | sort | tr '\n' ' ')"
done
if [ ${#VSETS[@]} -eq 0 ] && [ -z "$order" ]; then
  err "ORDER in config/${LAYOUT} is empty — nothing would be submitted"
fi
if [ ${#VSETS[@]} -gt 10 ] && [ "$CHAIN" = 0 ]; then
  warn "${#VSETS[@]} varsets each run their own loop at the same time — check your queue's limit on running jobs"
fi

# WRF input of the first year, per grid (a warning: the folder may only be visible on the compute nodes)
while read -r g dom wrf out; do
  if [ ! -d "$wrf" ]; then
    warn "grid $g: the WRF output folder $wrf does not exist"
  elif ! compgen -G "${wrf}/wrfout_${g}_${Y1}-*" >/dev/null; then
    warn "grid $g: no wrfout_${g}_${Y1}-* files in $wrf"
  fi
done <<< "$exp_info"

[ "$errors" -eq 0 ] || { echo "$errors problem(s) — nothing submitted." >&2; exit 1; }

#
#--- What will be submitted --------------------------------------
# One year per job; each job resubmits (or hands over) for the next year,
# up to the last year (year_lim).
#
datebeg="${Y1}0101"; dateend="${Y1}1231"
echo "Experiment ${EXP}, years ${Y1}-${Y2}, one year per job, varsets from config/${LAYOUT}"
while read -r g dom wrf out; do
  echo "  grid ${g} (${dom}): WRF output ${wrf} -> ${out}"
done <<< "$exp_info"

cmds=()
if [ ${#VSETS[@]} -eq 0 ]; then
  echo "  every stream in ORDER: ${order}"
  cmds+=("run_analysis.sh ${datebeg} ${dateend} ${Y2}")
else
  if [ "$CHAIN" = 1 ]; then echo "  varsets (handing over to their stream): ${VSETS[*]}"
  else echo "  varsets, each on its own: ${VSETS[*]}"; fi
  for vs in "${VSETS[@]}"; do cmds+=("run_out_generic.sh ${datebeg} ${dateend} ${Y2} ${vs}"); done
fi

for c in "${cmds[@]}"; do
  echo "+ CMOR_EXPERIMENT=${EXP} CMOR_VARSETS=${LAYOUT} ./submit.sh ${c}"
  if [ "$DRY" = 0 ]; then
    # shellcheck disable=SC2086
    CMOR_EXPERIMENT="$EXP" EXPERIMENT="$EXP" CMOR_VARSETS="$LAYOUT" "$SUBMIT" $c
  fi
done
[ "$DRY" = 1 ] && echo "Dry run: nothing submitted."
exit 0

#!/bin/bash
#
# check_and_found_var.sh — which variables were extracted, per year, without
# reading the extraction logs. The output folder(s) are taken from the
# experiment (env.site.sh -> experiments/<name>/<name>.sh: OUTPUT_DIR of every
# grid in run[]).
# Usage: ./check_and_found_var.sh [-r <repo>] [-v <variables.txt>] [-o <report dir>] <start_year> <end_year>
#        EXPERIMENT=lucas ./check_and_found_var.sh 2015 2020     (another experiment)
#----------------------------------------------------------------

set -euo pipefail

#
#--- Options ----------------------------------------------------
# -r repository folder (default: the folder above tools/), -v variable list
# (default: variables.txt next to this script), -o where to write the reports.
#
usage() {
  cat >&2 <<EOF
Usage: $0 [-r <repo dir>] [-v <variables.txt>] [-o <report dir>] <start_year> <end_year>
  -r  the CORDEX_Cmor folder (default: the folder above tools/)
  -v  list of variables, one per line, '#' comments allowed
      (default: variables.txt next to this script)
  -o  folder for the reports (default: <ROOT_RUN_DIR>/check_<grid> of the experiment)
The experiment is EXPERIMENT from env.site.sh; set EXPERIMENT=<name> to check another.
EOF
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"; VARS_FILE="$SCRIPT_DIR/variables.txt"; REPORT_DIR=""
while getopts "r:v:o:h" opt; do
  case "$opt" in
    r) REPO="$OPTARG" ;;
    v) VARS_FILE="$OPTARG" ;;
    o) REPORT_DIR="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
START_YEAR="$1"; END_YEAR="$2"
[[ "$START_YEAR" =~ ^[0-9]{4}$ && "$END_YEAR" =~ ^[0-9]{4}$ && "$START_YEAR" -le "$END_YEAR" ]] \
  || { echo "Give two years, start <= end, e.g. 2015 2020." >&2; exit 1; }
[ -f "$VARS_FILE" ] || { echo "Variables file not found: $VARS_FILE (give it with -v)." >&2; exit 1; }

#
#--- Experiment: output folder of every grid --------------------
# EXPERIMENT from env.site.sh (read in a subshell, so its modules aren't
# loaded here), then the experiment file via scripts/load_experiment.sh.
#
ROOT_DIR="$(cd -- "$REPO" && pwd)"
[ -f "$ROOT_DIR/scripts/load_experiment.sh" ] \
  || { echo "$ROOT_DIR is not the CORDEX_Cmor folder (no scripts/load_experiment.sh); give it with -r." >&2; exit 1; }
if [ -z "${EXPERIMENT:-}" ]; then
  [ -f "$ROOT_DIR/env.site.sh" ] || { echo "No $ROOT_DIR/env.site.sh — or set EXPERIMENT=<name>." >&2; exit 1; }
  # shellcheck source=/dev/null
  EXPERIMENT="$(set +eu; source "$ROOT_DIR/env.site.sh" >/dev/null 2>&1; echo "${EXPERIMENT:-}")"
fi
export ROOT_DIR EXPERIMENT
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/load_experiment.sh"

#
#--- Variable list ----------------------------------------------
# One variable per line; blank lines and '#' comments are skipped.
#
mapfile -t VARS < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$VARS_FILE" | grep -v '^$')
echo "${#VARS[@]} variables in $VARS_FILE, years ${START_YEAR}-${END_YEAR}"

#
#--- Varset of each variable (config/varsets_chain.sh, or CMOR_VARSETS) ----------------
# varset_of[<var>] = the varset(s) that extract it; the varsets that run
# (ORDER and what they chain to via NEXT) are preferred over unused ones.
# The uava programs also write ua<level> for every va<level> they list.
#
# shellcheck source=/dev/null
source "$ROOT_DIR/config/${CMOR_VARSETS:-varsets_chain.sh}"
declare -A active=() varset_of=() varset_any=()
for vs in "${ORDER[@]}"; do
  while [ -n "$vs" ] && [ -z "${active[$vs]:-}" ]; do
    active[$vs]=1; vs="${NEXT[$vs]:-}"
  done
done
for vs in $(printf '%s\n' "${!VARSETS[@]}" | sort); do
  IFS=';' read -r -a groups <<< "${VARSETS[$vs]}"
  for group in "${groups[@]}"; do
    IFS=',' read -r -a gvars <<< "${group#*:}"
    for v in "${gvars[@]}"; do
      names=("$v"); [[ "${group%%:*}" == *uava* && "$v" == va* ]] && names+=("ua${v#va}")
      for n in "${names[@]}"; do
        if [ -n "${active[$vs]:-}" ]; then varset_of[$n]+="${varset_of[$n]:+,}$vs"
        else varset_any[$n]+="${varset_any[$n]:+,}$vs"; fi
      done
    done
  done
done
varset_for() { echo "${varset_of[$1]:-${varset_any[$1]:-no_varset}}"; }

#
#--- Check each grid --------------------------------------------
# missing_<year>.txt lines are "<varset> <variable>" (several varsets: comma-separated).
# A variable counts as found for a year if any of its files covers that year
# (file names <var>_..._<start>-<end>.nc, old or new date stamps, one or
# several years per file). fx files are not checked.
#
for grid in "${GRIDS[@]}"; do
  out="${OUTPUT_DIR[$grid]%/}"
  rep="${REPORT_DIR:-${ROOT_RUN_DIR%/}/check_${grid}}"
  mkdir -p "$rep"
  echo "Grid ${grid} (${DOMAIN_ID[$grid]}): ${out} -> reports in ${rep}"
  if [ ! -d "$out" ]; then
    echo "  output folder ${out} does not exist — every variable counts as missing." >&2
  fi

  # years covered by each variable's files: covered[<var>]="2015 2016 ..."
  declare -A covered=()
  while IFS= read -r name; do
    [[ "$name" =~ ^([A-Za-z0-9]+)_.*_([0-9]{4})[0-9]*-(([0-9]{4})[0-9]*)(_v2)?\.nc$ ]] || continue
    v="${BASH_REMATCH[1]}"; y1="${BASH_REMATCH[2]}"; end="${BASH_REMATCH[3]}"; y2="${BASH_REMATCH[4]}"
    # old daily names end on 1 January of the next year (..._2015010100-2016010100.nc)
    if [[ "$end" =~ ^[0-9]{4}0101(00)?(00)?$ ]] && [ "$y2" -gt "$y1" ]; then y2=$((y2 - 1)); fi
    for ((y = y1; y <= y2; y++)); do covered[$v]+=" $y "; done
  done < <( [ -d "$out" ] && find "$out" -maxdepth 1 -name '*.nc' -printf '%f\n' )

  summary="$rep/missing_summary.txt"
  : > "$summary"
  declare -A missing_years=()
  for ((year = START_YEAR; year <= END_YEAR; year++)); do
    found_file="$rep/found_${year}.txt"; missing_file="$rep/missing_${year}.txt"
    : > "$found_file"; : > "$missing_file"
    nf=0; nm=0
    for v in "${VARS[@]}"; do
      if [[ "${covered[$v]:-}" == *" $year "* ]]; then
        echo "$v" >> "$found_file"; nf=$((nf + 1))
      else
        echo "$(varset_for "$v") $v" >> "$missing_file"; nm=$((nm + 1)); missing_years[$v]+="$year "
      fi
    done
    echo "  ${year}: ${nf} found, ${nm} missing"
  done

  {
    echo "Experiment ${EXPERIMENT}, grid ${grid} (${DOMAIN_ID[$grid]}), ${out}"
    echo "Missing across ${START_YEAR}-${END_YEAR} (${#missing_years[@]} of ${#VARS[@]} variables):"
    for v in "${VARS[@]}"; do
      [ -n "${missing_years[$v]:-}" ] && echo "$v : ${missing_years[$v]% }"
    done
  } > "$summary"
  echo "  summary: ${summary}"
  unset covered missing_years
done

echo "$0 done."

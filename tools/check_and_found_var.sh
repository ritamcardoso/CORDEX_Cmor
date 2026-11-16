#!/bin/bash
#
# check_and_found_var.sh — which variables were extracted, per year, without
# reading the extraction logs. The output folder(s) are taken from the
# experiment (env.site.sh -> experiments/<name>/<name>.sh: OUTPUT_DIR of every
# grid in run[]). The variables: those of -v <file>, or (without -v) every
# variable the chained varsets extract (config/varsets_chain.sh: ORDER and
# their NEXT links, with their CP_EXTRA companions), plus the varsets of -s.
# Usage: ./check_and_found_var.sh [-e <experiment>] [-r <repo>] [-v <variables.txt> | -s <varset,...>] [-o <report dir>] <start_year> <end_year>
#----------------------------------------------------------------

set -euo pipefail

#
#--- Options ----------------------------------------------------
# -e experiment, -r repository folder (default: the folder above tools/),
# -v variable list, -s extra varsets (without -v), -o where to write the reports.
#
usage() {
  cat >&2 <<EOF
Usage: $0 [-e <experiment>] [-r <repo dir>] [-v <variables.txt> | -s <varset,...>] [-o <report dir>] <start_year> <end_year>
  -e  experiment (default: asked for when -v is not given and you are at a
      terminal; otherwise CMOR_EXPERIMENT, EXPERIMENT or EXPERIMENT in env.site.sh)
  -r  the CORDEX_Cmor folder (default: the folder above tools/)
  -v  list of variables, one per line, '#' comments allowed (e.g. variables.txt
      next to this script). Without -v: every variable of the chained varsets
      in config/varsets_chain.sh (or CMOR_VARSETS) — ORDER, their NEXT links
      and CP_EXTRA companions
  -s  without -v: also these varsets (comma-separated), e.g. -s lsm
  -o  folder for the reports (default: <ROOT_RUN_DIR>/check_<grid> of the experiment)
EOF
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"; VARS_FILE=""; REPORT_DIR=""; EXP_OPT=""; EXTRA_VS=""
while getopts "e:s:r:v:o:h" opt; do
  case "$opt" in
    e) EXP_OPT="$OPTARG" ;;
    s) EXTRA_VS="$OPTARG" ;;
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
if [ -n "$VARS_FILE" ]; then
  [ -f "$VARS_FILE" ] || { echo "Variables file not found: $VARS_FILE." >&2; exit 1; }
  [ -z "$EXTRA_VS" ] || { echo "-s is for the list from the varsets; with -v, list the variables in the file." >&2; exit 1; }
fi

#
#--- Experiment: output folder of every grid --------------------
# -e; else, without -v and at a terminal, ask (default: CMOR_EXPERIMENT,
# EXPERIMENT, or EXPERIMENT from env.site.sh, read in a subshell so its
# modules aren't loaded here); then the experiment file via
# scripts/load_experiment.sh.
#
ROOT_DIR="$(cd -- "$REPO" && pwd)"
[ -f "$ROOT_DIR/scripts/load_experiment.sh" ] \
  || { echo "$ROOT_DIR is not the CORDEX_Cmor folder (no scripts/load_experiment.sh); give it with -r." >&2; exit 1; }
EXPERIMENT="${EXP_OPT:-${CMOR_EXPERIMENT:-${EXPERIMENT:-}}}"
if [ -z "$EXPERIMENT" ] && [ -f "$ROOT_DIR/env.site.sh" ]; then
  # shellcheck source=/dev/null
  EXPERIMENT="$(set +eu; source "$ROOT_DIR/env.site.sh" >/dev/null 2>&1; echo "${EXPERIMENT:-}")"
fi
if [ -z "$EXP_OPT" ] && [ -z "$VARS_FILE" ] && [ -t 0 ]; then
  read -r -p "Experiment [${EXPERIMENT:-none}]: " _ans
  EXPERIMENT="${_ans:-$EXPERIMENT}"
fi
[ -n "$EXPERIMENT" ] || { echo "No experiment: give it with -e <name> (or EXPERIMENT in env.site.sh)." >&2; exit 1; }
[ -f "$ROOT_DIR/experiments/$EXPERIMENT/$EXPERIMENT.sh" ] \
  || { echo "No experiment file $ROOT_DIR/experiments/$EXPERIMENT/$EXPERIMENT.sh (experiment '$EXPERIMENT')." >&2; exit 1; }
CMOR_VARSETS="${CMOR_VARSETS:-varsets_chain.sh}"
[ "$CMOR_VARSETS" = varsets.sh ] && CMOR_VARSETS=varsets_chain.sh
[ -f "$ROOT_DIR/config/$CMOR_VARSETS" ] || { echo "No $ROOT_DIR/config/$CMOR_VARSETS (CMOR_VARSETS)." >&2; exit 1; }
export ROOT_DIR EXPERIMENT
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/load_experiment.sh"

#
#--- Varset of each variable (config/varsets_chain.sh, or CMOR_VARSETS) ----------------
# varset_of[<var>] = the varset(s) that extract it; the varsets that run
# (ORDER and what they chain to via NEXT, their CP_EXTRA companions and the
# varsets of -s) are preferred over unused ones. The uava programs also
# write ua<level> for every va<level> they list.
#
# shellcheck source=/dev/null
source "$ROOT_DIR/config/$CMOR_VARSETS"
declare -A active=() varset_of=() varset_any=()
running=()
# add_running <varset>: mark it as running (once); list it if it is a varset
add_running() {
  [ -n "$1" ] && [ -z "${active[$1]:-}" ] || return 0
  active[$1]=1; [ -n "${VARSETS[$1]+x}" ] && running+=("$1")
  return 0
}
for vs in "${ORDER[@]}"; do
  while [ -n "$vs" ] && [ -z "${active[$vs]:-}" ]; do
    add_running "$vs"; add_running "${CP_EXTRA[$vs]:-}"; vs="${NEXT[$vs]:-}"
  done
done
if [ -n "$EXTRA_VS" ]; then
  IFS=',' read -r -a _extra <<< "$EXTRA_VS"
  for vs in "${_extra[@]}"; do
    [ -n "${VARSETS[$vs]+x}" ] || { echo "Unknown varset '$vs' (-s) — not in config/$CMOR_VARSETS." >&2; exit 1; }
    add_running "$vs"; add_running "${CP_EXTRA[$vs]:-}"
  done
fi
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
#--- Variable list ----------------------------------------------
# -v: one variable per line; blank lines and '#' comments are skipped.
# Without -v: the variables of the running varsets, in ORDER/NEXT order.
#
vars_of() {   # vars_of <varset>: its variables, one per line (and ua<level> for the uava programs)
  local group v
  IFS=';' read -r -a _groups <<< "${VARSETS[$1]}"
  for group in "${_groups[@]}"; do
    IFS=',' read -r -a _gvars <<< "${group#*:}"
    for v in "${_gvars[@]}"; do
      echo "$v"; [[ "${group%%:*}" == *uava* && "$v" == va* ]] && echo "ua${v#va}"
    done
  done
  return 0
}
if [ -n "$VARS_FILE" ]; then
  mapfile -t VARS < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$VARS_FILE" | grep -v '^$')
  echo "${#VARS[@]} variables in $VARS_FILE, years ${START_YEAR}-${END_YEAR}"
else
  mapfile -t VARS < <(for vs in "${running[@]}"; do vars_of "$vs"; done | awk 'NF && !seen[$0]++')
  echo "${#VARS[@]} variables of the varsets in config/${CMOR_VARSETS}, years ${START_YEAR}-${END_YEAR}: ${running[*]}"
fi
[ "${#VARS[@]}" -gt 0 ] || { echo "No variables to check." >&2; exit 1; }

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

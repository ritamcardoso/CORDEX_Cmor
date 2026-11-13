#!/bin/bash
#
# check_archive.sh — were the files copied correctly to the remote server
# (REMOTE_HOST:REMOTE_BASE/<var>/raw) and to ECFS (ECFS_BASE/<var>)?
# Compares every archived copy with the original in OUTPUT_DIR (same size);
# where the original is gone, checks it is not empty and its size is within
# a few percent of the previous year's file.
# Usage: ./check_archive.sh [-d remote|ecfs|both] [-t pct] [-v file] [-o dir] [-r repo] <start_year> <end_year>
#----------------------------------------------------------------

set -euo pipefail

#
#--- Options ----------------------------------------------------
# -d which archive(s) to check, -t size tolerance (%) for files whose
# original is gone, -v variable list, -o report folder, -r repository.
#
usage() {
  cat >&2 <<EOF
Usage: $0 [-d remote|ecfs|both] [-t pct] [-v <variables.txt>] [-o <report dir>] [-r <repo dir>] <start_year> <end_year>
  -d  archive to check: remote (REMOTE_HOST), ecfs, or both (default: remote)
  -t  allowed size difference from the previous year, in %, for copies whose
      original is no longer in OUTPUT_DIR (default: 5)
  -v  list of variables (default: variables.txt next to this script)
  -o  folder for the reports (default: <ROOT_RUN_DIR>/check_archive_<grid>)
  -r  the CORDEX_Cmor folder (default: the folder above tools/)
The experiment is EXPERIMENT from env.site.sh; set EXPERIMENT=<name> to check another.
EOF
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"; VARS_FILE="$SCRIPT_DIR/variables.txt"; REPORT_DIR=""
DEST="remote"; THRESHOLD=5
while getopts "d:t:v:o:r:h" opt; do
  case "$opt" in
    d) DEST="$OPTARG" ;;
    t) THRESHOLD="$OPTARG" ;;
    v) VARS_FILE="$OPTARG" ;;
    o) REPORT_DIR="$OPTARG" ;;
    r) REPO="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
START_YEAR="$1"; END_YEAR="$2"
[[ "$START_YEAR" =~ ^[0-9]{4}$ && "$END_YEAR" =~ ^[0-9]{4}$ && "$START_YEAR" -le "$END_YEAR" ]] \
  || { echo "Give two years, start <= end, e.g. 2015 2020." >&2; exit 1; }
case "$DEST" in remote) DESTS=(remote) ;; ecfs) DESTS=(ecfs) ;; both) DESTS=(remote ecfs) ;; *) usage ;; esac
[[ "$THRESHOLD" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "-t needs a number (percent)." >&2; exit 1; }
[ -f "$VARS_FILE" ] || { echo "Variables file not found: $VARS_FILE (give it with -v)." >&2; exit 1; }

#
#--- Experiment and archive settings ----------------------------
# EXPERIMENT and REMOTE_HOST from env.site.sh (read in a subshell, so its
# modules aren't loaded here); grids and paths from the experiment file.
#
ROOT_DIR="$(cd -- "$REPO" && pwd)"
[ -f "$ROOT_DIR/scripts/load_experiment.sh" ] \
  || { echo "$ROOT_DIR is not the CORDEX_Cmor folder (no scripts/load_experiment.sh); give it with -r." >&2; exit 1; }
[ -f "$ROOT_DIR/env.site.sh" ] || { echo "No $ROOT_DIR/env.site.sh." >&2; exit 1; }
# shellcheck source=/dev/null
mapfile -t _site < <(set +eu; source "$ROOT_DIR/env.site.sh" >/dev/null 2>&1; echo "${EXPERIMENT:-}"; echo "${REMOTE_HOST:-}")
EXPERIMENT="${EXPERIMENT:-${_site[0]}}"; REMOTE_HOST="${_site[1]}"
export ROOT_DIR EXPERIMENT
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/load_experiment.sh"
if [[ " ${DESTS[*]} " == *" remote "* ]]; then
  [ -n "$REMOTE_HOST" ] || { echo "No REMOTE_HOST in env.site.sh." >&2; exit 1; }
  command -v ssh >/dev/null || { echo "ssh not found." >&2; exit 1; }
fi
if [[ " ${DESTS[*]} " == *" ecfs "* ]]; then
  command -v els >/dev/null || { echo "els (ECFS) not found — run this on the ECMWF HPC, or use -d remote." >&2; exit 1; }
fi

#
#--- Variable list and their varsets ----------------------------
# Variables from variables.txt; varset_of[<var>] from config/varsets_chain.sh (or CMOR_VARSETS),
# the running varsets (ORDER and their NEXT links) first, as in
# check_and_found_var.sh. The uava programs also write ua<level>.
#
mapfile -t VARS < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$VARS_FILE" | grep -v '^$')
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

# write_array <file> <list file>: the variables (last word of each line, before
# any '#' note) as a bash array, sorted and unique, as check_output_v5.sh wrote:
#   declare -a var=("pr" "tas" )
write_array() {
  {
    printf 'declare -a var=('
    sed -e 's/[[:space:]]*#.*//' "$2" | awk 'NF {print $NF}' | sort -u | while IFS= read -r v; do printf '"%s" ' "$v"; done
    echo ')'
  } > "$1"
}
echo "${#VARS[@]} variables, years ${START_YEAR}-${END_YEAR}, archive(s): ${DESTS[*]}"

#
#--- File names -> variable and years ---------------------------
# <var>_..._<start>-<end>.nc (old and new date stamps, one or several years);
# old daily names end on 1 January of the next year and count for their own year.
#
name_years() {   # name_years <file name>  ->  "<var> <first year> <last year>" or nothing
  local name="$1" v y1 y2 end
  [[ "$name" =~ ^([A-Za-z0-9]+)_.*_([0-9]{4})[0-9]*-(([0-9]{4})[0-9]*)(_v2)?\.nc$ ]] || return 0
  v="${BASH_REMATCH[1]}"; y1="${BASH_REMATCH[2]}"; end="${BASH_REMATCH[3]}"; y2="${BASH_REMATCH[4]}"
  if [[ "$end" =~ ^[0-9]{4}0101(00)?(00)?$ ]] && [ "$y2" -gt "$y1" ]; then y2=$((y2 - 1)); fi
  echo "$v $y1 $y2"
}

#
#--- Check each grid and archive --------------------------------
# For every variable and year: the archived file(s) covering that year must
# exist, not be empty and have the size of the original in OUTPUT_DIR (or,
# if the original is gone, be within THRESHOLD % of the previous year's copy).
#
status=0
for grid in "${GRIDS[@]}"; do
  out="${OUTPUT_DIR[$grid]%/}"

  # originals: local_size[<file name>]
  declare -A local_size=()
  if [ -d "$out" ]; then
    while read -r size name; do local_size[$name]=$size; done \
      < <(find "$out" -maxdepth 1 -name '*.nc' -printf '%s %f\n')
  fi

  for dest in "${DESTS[@]}"; do
    rep="${REPORT_DIR:-${ROOT_RUN_DIR%/}/check_archive_${grid}}/${dest}"
    mkdir -p "$rep"

    # archived copies: arch_size[<file name>], arch_files[<var>]="name1 name2 ..."
    declare -A arch_size=() arch_files=()
    if [ "$dest" = remote ]; then
      where="${REMOTE_HOST}:${REMOTE_BASE[$grid]}"
      echo "Grid ${grid}: ${where}/<var>/raw  (originals: ${out})"
      # one ssh for the whole tree: "<var>/raw/<file> <size>"
      if ! listing=$(ssh -o BatchMode=yes "$REMOTE_HOST" \
            "cd '${REMOTE_BASE[$grid]}' && find . -mindepth 3 -maxdepth 3 -path './*/raw/*.nc' -printf '%P %s\n'"); then
        echo "  ERROR: cannot list ${where} (ssh failed)." >&2; status=1; continue
      fi
      while read -r path size; do
        [ -n "$path" ] || continue
        name="${path##*/}"; arch_size[$name]=$size; arch_files[${path%%/*}]+="$name "
      done <<< "$listing"
    else
      where="${ECFS_BASE[$grid]}"
      echo "Grid ${grid}: ${where}/<var>  (originals: ${out})"
      for v in "${VARS[@]}"; do
        # els -l: like ls -l, size in column 5, name last; a missing folder is just empty
        while read -r size name; do
          [[ "$name" == *.nc ]] || continue
          arch_size[$name]=$size; arch_files[$v]+="$name "
        done < <(els -l "${where}/${v}/" 2>/dev/null | awk 'NF >= 9 {print $5, $NF}')
      done
    fi

    # files covering each year, per variable: cover[<var>:<year>]="name ..."
    declare -A cover=()
    for v in "${!arch_files[@]}"; do
      for name in ${arch_files[$v]}; do
        read -r nv y1 y2 <<< "$(name_years "$name")" || true
        [ -n "${nv:-}" ] && [ "$nv" = "$v" ] || continue
        for ((y = y1; y <= y2; y++)); do cover[$v:$y]+="$name "; done
      done
    done

    summary="$rep/problems_summary.txt"; : > "$summary"
    for ((year = START_YEAR; year <= END_YEAR; year++)); do
      found_f="$rep/found_${year}.txt"; missing_f="$rep/missing_${year}.txt"; size_f="$rep/size_mismatch_${year}.txt"
      : > "$found_f"; : > "$missing_f"; : > "$size_f"
      nf=0; nm=0; ns=0
      for v in "${VARS[@]}"; do
        cov="${cover[$v:$year]:-}"
        if [ -z "$cov" ]; then
          echo "$(varset_for "$v") $v" >> "$missing_f"; nm=$((nm + 1)); continue
        fi
        bad=""
        for name in $cov; do
          a="${arch_size[$name]}"
          if [ "$a" -eq 0 ]; then
            bad="empty copy ${name}"; break
          elif [ -n "${local_size[$name]:-}" ]; then
            [ "$a" -eq "${local_size[$name]}" ] || { bad="${name}: ${a} bytes, original ${local_size[$name]}"; break; }
          else
            # original gone: compare with the previous year's copy, if there is one
            prev="${cover[$v:$((year - 1))]:-}"; prev="${prev%% *}"
            if [ -n "$prev" ] && [ "$prev" != "$name" ] && [ "${arch_size[$prev]}" -gt 0 ]; then
              if ! awk -v n="$a" -v o="${arch_size[$prev]}" -v t="$THRESHOLD" \
                   'BEGIN { d = (n > o ? n - o : o - n) / o * 100; exit (d > t) }'; then
                bad="${name}: ${a} bytes, previous year ${arch_size[$prev]} (> ${THRESHOLD}%, original gone)"; break
              fi
            fi
          fi
        done
        if [ -z "$bad" ]; then
          echo "$v" >> "$found_f"; nf=$((nf + 1))
        else
          echo "$(varset_for "$v") $v  # $bad" >> "$size_f"; ns=$((ns + 1))
        fi
      done
      for kind in found missing size_mismatch; do
        write_array "$rep/${kind}_${year}.sh" "$rep/${kind}_${year}.txt"
      done
      echo "  ${year}: ${nf} copied correctly, ${nm} missing, ${ns} wrong size"
      { [ "$nm" -eq 0 ] && [ "$ns" -eq 0 ]; } || {
        status=1
        { echo "== ${year}: missing ${nm}, wrong size ${ns}"; cat "$missing_f" "$size_f"; } >> "$summary"
      }
    done
    echo "  reports: ${rep}"
    unset arch_size arch_files cover
  done
  unset local_size
done

[ "$status" -eq 0 ] && echo "All archived copies are complete." \
  || echo "Some copies are missing or wrong — see the reports above (problems_summary.txt)." >&2
exit "$status"

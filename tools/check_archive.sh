#!/bin/bash
#
# check_archive.sh — were the files copied correctly to the remote server
# (REMOTE_HOST:REMOTE_BASE/<var>/raw) and to ECFS (ECFS_BASE/<var>)?
# Compares every archived copy with the original in OUTPUT_DIR (same size);
# where the original is gone, checks it is not empty and its size is within
# a few percent of the previous year's file.
# The variables: those of -v <file>, or (without -v) every variable the
# chained varsets extract (config/varsets_chain.sh: ORDER and their NEXT
# links, with their CP_EXTRA companions), plus the varsets of -s.
# Usage: ./check_archive.sh [-b] [-e experiment] [-d remote|ecfs|both] [-t pct] [-v file | -s varsets] [-o dir] [-r repo] <start_year> <end_year>
#   -b submits the check as a job (scripts/run_check_archive.sh, through submit.sh).
#----------------------------------------------------------------

set -euo pipefail

#
#--- Options ----------------------------------------------------
# -b submit as a job, -e experiment, -d which archive(s) to check, -t size
# tolerance (%) for files whose original is gone, -v variable list,
# -s extra varsets (without -v), -o report folder, -r repository.
#
usage() {
  cat >&2 <<EOF
Usage: $0 [-b] [-e <experiment>] [-d remote|ecfs|both] [-t pct] [-v <variables.txt> | -s <varset,...>] [-o <report dir>] [-r <repo dir>] <start_year> <end_year>
  -b  submit the check as a Slurm job (through submit.sh) instead of running it here
  -e  experiment (default: asked for when -v is not given and you are at a
      terminal; otherwise CMOR_EXPERIMENT, EXPERIMENT or EXPERIMENT in env.site.sh)
  -d  archive to check: remote (REMOTE_HOST), ecfs, or both (default: remote)
  -t  allowed size difference from the previous year, in %, for copies whose
      original is no longer in OUTPUT_DIR (default: 5)
  -v  list of variables (e.g. variables.txt next to this script). Without -v:
      every variable of the chained varsets in config/varsets_chain.sh (or
      CMOR_VARSETS) — ORDER, their NEXT links and CP_EXTRA companions
  -s  without -v: also these varsets (comma-separated), e.g. -s fx,lsm
  -o  folder for the reports (default: <ROOT_RUN_DIR>/check_archive_<grid>)
  -r  the CORDEX_Cmor folder (default: the folder above tools/)
EOF
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"; VARS_FILE=""; REPORT_DIR=""
DEST="remote"; THRESHOLD=5; BATCH=0; EXP_OPT=""; EXTRA_VS=""
while getopts "bd:e:s:t:v:o:r:h" opt; do
  case "$opt" in
    b) BATCH=1 ;;
    e) EXP_OPT="$OPTARG" ;;
    s) EXTRA_VS="$OPTARG" ;;
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
if [ -n "$VARS_FILE" ]; then
  [ -f "$VARS_FILE" ] || { echo "Variables file not found: $VARS_FILE." >&2; exit 1; }
  VARS_FILE="$(realpath -- "$VARS_FILE")"   # absolute, for -b (the job runs elsewhere)
  [ -z "$EXTRA_VS" ] || { echo "-s is for the list from the varsets; with -v, list the variables in the file." >&2; exit 1; }
fi
[ -z "$REPORT_DIR" ] || { mkdir -p "$REPORT_DIR"; REPORT_DIR="$(realpath -- "$REPORT_DIR")"; }

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
REMOTE_HOST="${_site[1]}"
# experiment: -e; else, without -v and at a terminal, ask (default: the one
# from the environment or env.site.sh); else CMOR_EXPERIMENT / EXPERIMENT / env.site.sh
EXPERIMENT="${EXP_OPT:-${CMOR_EXPERIMENT:-${EXPERIMENT:-${_site[0]}}}}"
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

#
#--- -b: submit this check as a job -------------------------------
# Through submit.sh (account, qos, mail from env.site.sh; --time from
# CHECK_TIME in the varsets file, default 02:00:00), with the same options
# and the experiment fixed, so the job doesn't ask. The options go to the
# job in CHECK_ARCHIVE_ARGS, not on the command line: sbatch wrappers such
# as ECMWF's ecsbatch take -e, -d, -t, ... after the script name as their own.
#
if [ "$BATCH" = 1 ]; then
  args=(-e "$EXPERIMENT" -d "$DEST" -t "$THRESHOLD" -r "$ROOT_DIR")
  [ -n "$VARS_FILE" ] && args+=(-v "$VARS_FILE")
  [ -n "$EXTRA_VS" ] && args+=(-s "$EXTRA_VS")
  [ -n "$REPORT_DIR" ] && args+=(-o "$REPORT_DIR")
  args+=("$START_YEAR" "$END_YEAR")
  CHECK_ARCHIVE_ARGS="$(printf '%q ' "${args[@]}")"
  echo "Job options: ${CHECK_ARCHIVE_ARGS}"
  CHECK_ARCHIVE_ARGS="$CHECK_ARCHIVE_ARGS" CMOR_EXPERIMENT="$EXPERIMENT" CMOR_VARSETS="$CMOR_VARSETS" \
    exec "$ROOT_DIR/submit.sh" run_check_archive.sh
fi
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
# varset_of[<var>] from config/varsets_chain.sh (or CMOR_VARSETS), the
# running varsets (ORDER and their NEXT links, with their CP_EXTRA
# companions, and the varsets of -s) first, as in check_and_found_var.sh.
# The uava programs also write ua<level>. The variables: those of -v, or
# every variable of the running varsets, in ORDER/NEXT order.
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
# vars_of <varset>: its variables, one per line (and ua<level> for the uava programs)
vars_of() {
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
  echo "Variables from ${VARS_FILE}"
else
  mapfile -t VARS < <(for vs in "${running[@]}"; do vars_of "$vs"; done | awk 'NF && !seen[$0]++')
  echo "Variables of the varsets in config/${CMOR_VARSETS} (experiment ${EXPERIMENT}): ${running[*]}"
fi
[ "${#VARS[@]}" -gt 0 ] || { echo "No variables to check." >&2; exit 1; }
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

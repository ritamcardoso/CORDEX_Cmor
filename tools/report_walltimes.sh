#!/bin/bash
#
# report_walltimes.sh — longest completed run per varset, from sacct.
# Usage (on a login node, not via sbatch):
#   bash report_walltimes.sh [--since <date>] [--margin <percent>] [--clusters <list|all>]
# See README.md §11.
#----------------------------------------------------------------

set -euo pipefail

#
#--- Options ----------------------------------------------------
# --since, --margin and --clusters, with their defaults.
#
since="now-30days"
margin=25
clusters="all"

usage() {
  echo "Usage: bash $0 [--since <date>] [--margin <percent>] [--clusters <list|all>]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --since)    since="$2";    shift 2 ;;
    --margin)   margin="$2";   shift 2 ;;
    --clusters) clusters="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

#
#--- Requirements -----------------------------------------------
# sacct must be available, i.e. run on an HPC login node.
#
if ! command -v sacct >/dev/null 2>&1; then
  echo "ERROR: sacct not found — run this on an HPC login node with Slurm accounting enabled." >&2
  exit 1
fi

#
#--- Configured limits (config/varsets_chain.sh next to this file) -----
# Loads config/varsets_chain.sh, or config/$CMOR_VARSETS (found through a symlink too), to compare
# against TIME[]/CP_TIME[]; skipped if it isn't there.
#
SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
config="${SCRIPT_DIR}/../config/${CMOR_VARSETS:-varsets_chain.sh}"
have_config=0
if [ -f "${config}" ]; then
  # shellcheck source=/dev/null
  source "${config}"
  have_config=1
else
  echo "NOTE: ${config} not found — skipping the comparison with configured limits." >&2
fi

#
#--- Helpers ----------------------------------------------------
# Time conversions, and the limit configured for a wrf-*/cp-* job name.
#
# [DD-]HH:MM:SS -> seconds
to_secs() {
  local t="$1" d=0 h m s
  if [[ "${t}" == *-* ]]; then
    d="${t%%-*}"
    t="${t#*-}"
  fi
  IFS=: read -r h m s <<< "${t}"
  echo $(( 10#${d} * 86400 + 10#${h} * 3600 + 10#${m} * 60 + 10#${s} ))
}

# seconds -> HH:MM:SS (hours may exceed 24)
to_hms() {
  local x="$1"
  printf '%02d:%02d:%02d' $(( x / 3600 )) $(( (x % 3600) / 60 )) $(( x % 60 ))
}

# Configured limit for a job name (wrf-x -> TIME[x], cp-x -> CP_TIME[x])
configured_limit() {
  local jobname="$1" vs
  [ "${have_config}" = "1" ] || return 0
  case "${jobname}" in
    wrf-*) vs="${jobname#wrf-}"; echo "${TIME[$vs]:-}" ;;
    cp-*)  vs="${jobname#cp-}";  echo "${CP_TIME[$vs]:-${DEFAULT_CP_TIME:-}}" ;;
  esac
}

#
#--- Collect runs from sacct (all clusters, top-level jobs) ------
# Reads every wrf-*/cp-* job from sacct: longest completed run, run count,
# clusters used and any non-completed states (TIMEOUT, OUT_OF_MEMORY, ...).
#
declare -A max_elapsed=()
declare -A job_count=()
declare -A other_states=()
declare -A seen_clusters=()

while IFS='|' read -r jobname state elapsed cluster; do
  #
  # Only pipeline jobs (wrf-* / cp-*)
  # Skips every job not submitted by this pipeline.
  #
  [[ "${jobname}" == wrf-* || "${jobname}" == cp-* ]] || continue

  case ",${seen_clusters[$jobname]:-}," in
    *",${cluster},"*) ;;
    *) seen_clusters[$jobname]="${seen_clusters[$jobname]:-}${seen_clusters[$jobname]:+,}${cluster}" ;;
  esac

  # "CANCELLED by 1234" -> "CANCELLED"
  state="${state%% *}"
  if [ "${state}" = "COMPLETED" ]; then
    secs="$(to_secs "${elapsed}")"
    job_count[$jobname]=$(( ${job_count[$jobname]:-0} + 1 ))
    if [ "${secs}" -gt "${max_elapsed[$jobname]:-0}" ]; then
      max_elapsed[$jobname]="${secs}"
    fi
  else
    case ",${other_states[$jobname]:-}," in
      *",${state},"*) ;;
      *) other_states[$jobname]="${other_states[$jobname]:-}${other_states[$jobname]:+,}${state}" ;;
    esac
  fi
done < <(sacct -n -P -X -M "${clusters}" -S "${since}" \
              -o JobName,State,Elapsed,Cluster \
              --state=COMPLETED,TIMEOUT,FAILED,CANCELLED,OUT_OF_MEMORY)

#
#--- Report -----------------------------------------------------
# One row per job name: longest run, suggested limit (+ margin), configured
# limit, clusters, and notes such as LIMIT TOO SHORT.
#
echo "# Walltimes observed since ${since} on cluster(s): ${clusters} (margin: +${margin}%)"
echo "# MaxElapsed is the longest COMPLETED run. A job that hit its time limit"
echo "# (TIMEOUT) needed MORE than its limit — those are flagged, not measured."
echo "#"
printf '%-18s %5s  %-10s %-10s %-10s %-8s %s\n' \
  "JobName" "Runs" "MaxElapsed" "Suggested" "Configured" "Cluster" "Notes"

for jobname in "${!max_elapsed[@]}" "${!other_states[@]}"; do
  echo "${jobname}"
done | sort -u | while read -r jobname; do
  notes=()
  limit="$(configured_limit "${jobname}")"

  if [ -n "${max_elapsed[$jobname]+x}" ]; then
    secs="${max_elapsed[$jobname]}"
    suggested=$(( (secs * (100 + margin) + 99) / 100 ))
    max_s="$(to_hms "${secs}")"
    sug_s="$(to_hms "${suggested}")"
    runs="${job_count[$jobname]}"
    if [ -n "${limit}" ]; then
      limit_secs="$(to_secs "${limit}")"
      if [ "${secs}" -ge "${limit_secs}" ]; then
        notes+=("LIMIT TOO SHORT: longest run exceeds configured limit")
      elif [ "${suggested}" -gt "${limit_secs}" ]; then
        notes+=("tight: less than ${margin}% headroom")
      fi
    fi
  else
    max_s="-"; sug_s="-"; runs=0
    notes+=("no completed runs")
  fi

  [ -n "${limit}" ] || limit="?"
  if [ -n "${other_states[$jobname]+x}" ]; then
    notes+=("also: ${other_states[$jobname]}")
  fi

  note_str=""
  if [ "${#notes[@]}" -gt 0 ]; then
    note_str="$(IFS=';'; echo "${notes[*]}")"
    note_str="${note_str//;/; }"
  fi
  printf '%-18s %5s  %-10s %-10s %-10s %-8s %s\n' \
    "${jobname}" "${runs}" "${max_s}" "${sug_s}" "${limit}" "${seen_clusters[$jobname]:-?}" "${note_str}"
done

echo "#"
echo "# 'wrf-<varset>' rows map to TIME[<varset>]; 'cp-<varset>' rows map to CP_TIME[<varset>]."
echo "# Suggestions only — edit config/varsets_chain.sh (and varsets_single.sh) yourself once you're happy with them."

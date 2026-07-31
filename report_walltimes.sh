#!/bin/bash
#
# scripts/report_walltimes.sh
#
# Most TIME[]/CP_TIME[] values in config/varsets.sh are estimates carried
# over from the original per-variable scripts, not measured against the
# generic pipeline (README.md and config/varsets.sh both flag this — only
# [out]'s TIME and CP_TIME are confirmed against live runs). This script
# pulls real elapsed times from `sacct` for jobs this pipeline has already
# submitted (job names "wrf-<varset>" / "cp-<varset>", per submit.sh) and
# prints a suggested TIME[]/CP_TIME[] line per varset — actual elapsed plus
# a margin — so you can sanity-check/update config/varsets.sh from history
# instead of guesswork. It only reports; it never edits config/varsets.sh.
#
# Usage:
#   scripts/report_walltimes.sh [--since <sacct -S value, default: -30days>] [--margin <percent, default: 25>]
#
# Requires: sacct (run this on the HPC login node, not in CI/locally).

set -euo pipefail

since="-30days"
margin=25

while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --margin) margin="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--since <sacct -S value>] [--margin <percent>]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v sacct >/dev/null 2>&1; then
  echo "ERROR: sacct not found — run this on an HPC login node with Slurm accounting enabled." >&2
  exit 1
fi

echo "# Walltimes observed since ${since} (margin: +${margin}%)"
echo "# COMPLETED jobs only — a job that hit its time limit tells you it needs"
echo "# MORE than what's shown, not the right value; check those separately."
echo "#"
printf '%-20s %-10s %-12s %-12s %-10s\n' "JobName" "Count" "MaxElapsed" "Suggested" "State(s)"

# JobName -> list of elapsed seconds (COMPLETED only) and a note of any
# non-COMPLETED states seen (TIMEOUT most importantly).
declare -A max_elapsed=()
declare -A job_count=()
declare -A other_states=()

while IFS='|' read -r jobid jobname state elapsed; do
  # Only top-level jobs, not sacct's per-job sub-steps (JobID like
  # "12345.batch", "12345.extern") — those report near-duplicate elapsed
  # times for the same job and would just add noise here. A top-level
  # JobID has no ".".
  [[ "${jobid}" != *.* ]] || continue
  # Only our own varset jobs (wrf-* / cp-*, per submit.sh's --job-name).
  [[ "${jobname}" == wrf-* || "${jobname}" == cp-* ]] || continue

  # elapsed is [DD-]HH:MM:SS -> seconds
  d=0
  hms="${elapsed}"
  if [[ "${elapsed}" == *-* ]]; then
    d="${elapsed%%-*}"
    hms="${elapsed#*-}"
  fi
  IFS=: read -r h m s <<< "${hms}"
  secs=$(( 10#${d} * 86400 + 10#${h} * 3600 + 10#${m} * 60 + 10#${s} ))

  if [ "${state}" = "COMPLETED" ]; then
    job_count[$jobname]=$(( ${job_count[$jobname]:-0} + 1 ))
    if [ "${secs}" -gt "${max_elapsed[$jobname]:-0}" ]; then
      max_elapsed[$jobname]="${secs}"
    fi
  else
    other_states[$jobname]="${other_states[$jobname]:-}${other_states[$jobname]:+,}${state}"
  fi
done < <(sacct -n -P -S "${since}" -o JobID,JobName,State,Elapsed --state=COMPLETED,TIMEOUT,FAILED,CANCELLED)

for jobname in "${!max_elapsed[@]}"; do
  secs="${max_elapsed[$jobname]}"
  suggested=$(( secs * (100 + margin) / 100 ))
  sh=$(( suggested / 3600 )); sm=$(( (suggested % 3600) / 60 )); ss=$(( suggested % 60 ))
  eh=$(( secs / 3600 )); em=$(( (secs % 3600) / 60 )); es=$(( secs % 60 ))
  states="COMPLETED${other_states[$jobname]:+, also seen: ${other_states[$jobname]}}"
  printf '%-20s %-10s %02d:%02d:%02d      %02d:%02d:%02d      %s\n' \
    "${jobname}" "${job_count[$jobname]}" "${eh}" "${em}" "${es}" "${sh}" "${sm}" "${ss}" "${states}"
done | sort

for jobname in "${!other_states[@]}"; do
  if [ -z "${max_elapsed[$jobname]+x}" ]; then
    echo "WARN: ${jobname} — no COMPLETED runs found, only: ${other_states[$jobname]} (needs a longer TIME[]/CP_TIME[], can't suggest a value yet)" >&2
  fi
done

echo "#"
echo "# 'wrf-<varset>' rows suggest TIME[<varset>]; 'cp-<varset>' rows suggest CP_TIME[<varset>]."
echo "# These are suggestions only — edit config/varsets.sh yourself once you're happy with them."

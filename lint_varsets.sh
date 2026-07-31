#!/bin/bash
#
# config/lint_varsets.sh
#
# Static consistency check for config/varsets.sh — catches exactly the kind
# of drift that's easy to introduce by hand: a NEXT[]/CP_EXTRA[] pointing at
# a varset that doesn't exist, a VARSETS[] entry with no TIME[], or a
# program/variable referenced there with no matching source/header file on
# disk. Pure static analysis — no Slurm, no compiler, no env.site.sh needed.
# Run it locally before submitting, or via CI (see .github/workflows/).
#
# Usage: config/lint_varsets.sh   (run from anywhere; finds its own repo root)
#
# Exit status: 0 if clean, 1 if any error-level issue found.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_DIR="$(dirname -- "${SCRIPT_DIR}")"

# shellcheck source=/dev/null
source "${REPO_DIR}/config/varsets.sh"

errors=0
warnings=0

err()  { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARN:  $*" >&2; warnings=$((warnings + 1)); }

# ------------------------------------------------------------------
# 1. Every VARSETS[] key that's actually *processed* (in ORDER, or a
#    target of some NEXT[] chain) needs a TIME[] entry, since
#    run_out_generic.sh/submit.sh read TIME[$vs] to set --time when
#    submitting or resubmitting it. Archive-only entries (e.g. plev_ua,
#    reactivated purely for CP_EXTRA[]) are never submitted as their own
#    processing job, so they're exempt — same rule config/README.md
#    documents for a varset you only ever submit manually yourself.
# ------------------------------------------------------------------
declare -A processed=()
for vs in "${ORDER[@]}"; do processed[$vs]=1; done
for vs in "${!NEXT[@]}"; do processed["${NEXT[$vs]}"]=1; done

for vs in "${!VARSETS[@]}"; do
  if [ -n "${processed[$vs]+x}" ] && [ -z "${TIME[$vs]+x}" ]; then
    err "VARSETS[$vs] is processed (in ORDER or a NEXT[] target) but has no TIME[$vs] entry."
  fi
done

# ------------------------------------------------------------------
# 2. Every NEXT[] value points at a real VARSETS[] key.
# ------------------------------------------------------------------
for vs in "${!NEXT[@]}"; do
  target="${NEXT[$vs]}"
  if [ -z "${VARSETS[$target]+x}" ]; then
    err "NEXT[$vs]=\"${target}\" points at an unknown varset (not in VARSETS[])."
  fi
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "NEXT[$vs] is set but '$vs' itself is not in VARSETS[] (dead entry?)."
  fi
done

# ------------------------------------------------------------------
# 3. Every CP_EXTRA[] value points at a real VARSETS[] key.
# ------------------------------------------------------------------
for vs in "${!CP_EXTRA[@]}"; do
  target="${CP_EXTRA[$vs]}"
  if [ -z "${VARSETS[$target]+x}" ]; then
    err "CP_EXTRA[$vs]=\"${target}\" points at an unknown varset (not in VARSETS[])."
  fi
done

# ------------------------------------------------------------------
# 4. Every ADVANCE_YEAR[]/CP_TIME[] key is a real varset (typo guard).
# ------------------------------------------------------------------
for vs in "${!ADVANCE_YEAR[@]}"; do
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "ADVANCE_YEAR[$vs] is set but '$vs' is not in VARSETS[]."
  fi
done
for vs in "${!CP_TIME[@]}"; do
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "CP_TIME[$vs] is set but '$vs' is not in VARSETS[]."
  fi
done

# ------------------------------------------------------------------
# 5. Every varset in ORDER exists, and isn't only an archive-only entry.
# ------------------------------------------------------------------
for vs in "${ORDER[@]}"; do
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "ORDER contains '$vs', which is not in VARSETS[]."
  fi
done

# ------------------------------------------------------------------
# 6. Every program pattern referenced resolves to an actual .f90 file,
#    for every variable it would be substituted with.
# ------------------------------------------------------------------
for vs in "${!VARSETS[@]}"; do
  IFS=';' read -r -a groups <<< "${VARSETS[$vs]}"
  for group in "${groups[@]}"; do
    prog_pattern="${group%%:*}"
    IFS=',' read -r -a vars <<< "${group#*:}"
    for var in "${vars[@]}"; do
      prog_name="${prog_pattern/VAR/${var}}"
      f90_path="${REPO_DIR}/f90_src/${prog_name}.f90"
      if [ ! -f "${f90_path}" ]; then
        err "VARSETS[$vs]: program '${prog_name}' (from pattern '${prog_pattern}', var '${var}') has no f90_src/${prog_name}.f90."
      fi
      header_path="${REPO_DIR}/header/header_${var}"
      if [ ! -f "${header_path}" ]; then
        err "VARSETS[$vs]: variable '${var}' has no header/header_${var}."
      fi
    done
  done
done

# ------------------------------------------------------------------
# 7. Informational only: varsets with no CP_TIME[] fall back to
#    DEFAULT_CP_TIME — not an error, but worth surfacing so it's a
#    deliberate choice rather than an oversight.
# ------------------------------------------------------------------
for vs in "${!VARSETS[@]}"; do
  if [ -z "${CP_TIME[$vs]+x}" ]; then
    warn "VARSETS[$vs] has no CP_TIME[$vs] — archiving will use DEFAULT_CP_TIME=${DEFAULT_CP_TIME:-<unset>}."
  fi
done

echo
echo "config/lint_varsets.sh: ${errors} error(s), ${warnings} warning(s)."
[ "${errors}" -eq 0 ]

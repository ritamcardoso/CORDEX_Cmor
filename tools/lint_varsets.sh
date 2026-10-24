#!/bin/bash
#
# lint_varsets.sh — consistency check of config/varsets.sh (no Slurm needed).
# Usage: bash lint_varsets.sh    (exit 1 if any error)
# See README.md §11.
#----------------------------------------------------------------

set -uo pipefail

#
#--- Load config/varsets.sh -------------------------------------
# Reads the active varsets file from the repo (this script's folder).
#
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_DIR}/config/varsets.sh"

#
#--- Counters ---------------------------------------------------
# err/warn print a message and count it; errors set the exit status.
#
errors=0
warnings=0

err()  { echo "ERROR: $*" >&2; errors=$((errors + 1)); }
warn() { echo "WARN:  $*" >&2; warnings=$((warnings + 1)); }

#
#--- 1. Processed varsets have a TIME[] entry -------------------
# Every varset in ORDER or reached through NEXT needs a TIME entry,
# since submit.sh uses it as --time.
#
declare -A processed=()
for vs in "${ORDER[@]}"; do processed[$vs]=1; done
for vs in "${!NEXT[@]}"; do processed["${NEXT[$vs]}"]=1; done

for vs in "${!VARSETS[@]}"; do
  if [ -n "${processed[$vs]+x}" ] && [ -z "${TIME[$vs]+x}" ]; then
    err "VARSETS[$vs] is processed (in ORDER or a NEXT[] target) but has no TIME[$vs] entry."
  fi
done

#
#--- 2. NEXT[] entries name real varsets ------------------------
# Each NEXT entry must belong to, and point to, an existing varset.
#
for vs in "${!NEXT[@]}"; do
  target="${NEXT[$vs]}"
  if [ -z "${VARSETS[$target]+x}" ]; then
    err "NEXT[$vs]=\"${target}\" points at an unknown varset (not in VARSETS[])."
  fi
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "NEXT[$vs] is set but '$vs' itself is not in VARSETS[] (dead entry?)."
  fi
done

#
#--- 3. CP_EXTRA[] entries name real varsets --------------------
# Each CP_EXTRA companion must be an existing varset.
#
for vs in "${!CP_EXTRA[@]}"; do
  target="${CP_EXTRA[$vs]}"
  if [ -z "${VARSETS[$target]+x}" ]; then
    err "CP_EXTRA[$vs]=\"${target}\" points at an unknown varset (not in VARSETS[])."
  fi
done

#
#--- 4. ADVANCE_YEAR[]/CP_TIME[]/MEM[]/CPUS[] keys are real varsets
# Catches typos in the keys of these arrays.
#
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
for vs in "${!MEM[@]}"; do
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "MEM[$vs] is set but '$vs' is not in VARSETS[]."
  fi
done
for vs in "${!CPUS[@]}"; do
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "CPUS[$vs] is set but '$vs' is not in VARSETS[]."
  elif ! [[ "${CPUS[$vs]}" =~ ^[1-9][0-9]*$ ]]; then
    err "CPUS[$vs]=\"${CPUS[$vs]}\" is not a positive integer."
  fi
done

#
#--- 5. ORDER entries are real varsets --------------------------
# Every varset run_analysis.sh would submit must exist.
#
for vs in "${ORDER[@]}"; do
  if [ -z "${VARSETS[$vs]+x}" ]; then
    err "ORDER contains '$vs', which is not in VARSETS[]."
  fi
done

#
#--- 6. Every program has an .f90 file, every variable a header -
# Each program name (after VAR substitution) needs f90_src/<name>.f90,
# and each variable needs header/header_<var>.
#
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

#
#--- 7. Warning: varsets using DEFAULT_CP_TIME ------------------
# Not an error: lists varsets that fall back to DEFAULT_CP_TIME.
#
for vs in "${!VARSETS[@]}"; do
  if [ -z "${CP_TIME[$vs]+x}" ]; then
    warn "VARSETS[$vs] has no CP_TIME[$vs] — archiving will use DEFAULT_CP_TIME=${DEFAULT_CP_TIME:-<unset>}."
  fi
done

#
#--- Summary ----------------------------------------------------
# Prints the totals; exit status 1 if any error was found.
#
echo
echo "lint_varsets.sh: ${errors} error(s), ${warnings} warning(s)."
[ "${errors}" -eq 0 ]

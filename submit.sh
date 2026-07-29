#!/bin/bash
#
# submit.sh
#
# Thin wrapper that auto-detects ROOT_DIR from where THIS file lives
# and passes it into the Slurm job's environment via `sbatch --export`.
#
# Accepts both direct Slurm flags and target script arguments:
#   ./submit.sh [sbatch options...] <script-name> [script-args...]
#
# Examples:
#   ./submit.sh run_Analysis_v2.sh 20010101 20011231 2005
#   ./submit.sh --job-name=wrf-fx --time=12:00:00 --output=wrf-fx.%j.out run_out_generic.sh 20010101 20011231 2000 fx

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" &>/dev/null && pwd)"
export ROOT_DIR="${SCRIPT_DIR}"

sbatch_args=()
script_name=""

# Separate Slurm options (leading with '-') from the target script name
while [ $# -gt 0 ]; do
  case "$1" in
    -*)
      sbatch_args+=("$1")
      shift
      ;;
    *)
      script_name="$1"
      shift
      break
      ;;
  esac
done

if [ -z "${script_name}" ]; then
  echo "Usage: $0 [sbatch-options...] <script-name> [script-args...]" >&2
  echo "e.g.:  $0 --job-name=wrf-fx --time=12:00:00 run_out_generic.sh 20010101 20011231 2000 fx" >&2
  exit 1
fi

target_path="${ROOT_DIR}/scripts/${script_name}"
if [ ! -f "${target_path}" ]; then
  echo "No such script: ${target_path}" >&2
  echo "(Looked under ROOT_DIR=${ROOT_DIR}, auto-detected from submit.sh's location.)" >&2
  exit 1
fi

echo "ROOT_DIR=${ROOT_DIR} (auto-detected from submit.sh's location)"

# Execute sbatch with collected Slurm flags, export variables, script path, and script args
exec sbatch --export=ALL,ROOT_DIR="${ROOT_DIR}" "${sbatch_args[@]}" "${target_path}" "$@"

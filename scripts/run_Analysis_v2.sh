#!/bin/bash
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --hint=nomultithread
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt

# ------------------------------------------------------------------
#  --account/--mail-user/--chdir above are the only site-specific bits left
#  in this file — edit them directly here (and in run_out_generic.sh /
#  run_cp_generic.sh, the only other two scripts).
#
#  Run using (ROOT_DIR must be exported first — see README.md):
#
#  export ROOT_DIR=/path/to/this/repo
#  sbatch $ROOT_DIR/scripts/run_Analysis_v2.sh \
#         [initial date - yyyymmdd] [final date - yyyymmdd] [loop year limit - yyyy]
#
#  You can submit from anywhere (e.g. $SCRATCH/Analysis) — ROOT_DIR is what
#  tells this script where the actual code/config live; it does not need
#  to match your cwd.
#-------------------------------------------------------------------

set -x

# ROOT_DIR must be set in your environment — Slurm copies the submitted
# script into a spool directory before running it, so $0/dirname can't be
# used to find this repo reliably (especially when submitting from a
# different directory, e.g. $SCRATCH/Analysis, than where the code lives).
: "${ROOT_DIR:?ROOT_DIR is not set. export ROOT_DIR=/path/to/this/repo (e.g. in ~/.bashrc) before submitting — see README.md}"
REPO_DIR="${ROOT_DIR}"

#### Load libraries used by this orchestration step only
intel_v="2021.4"
hdf5_v="1.12.2"
ncdf_v="4.9.3"
jasper_v="2.0.14"
nco_v="4.9.7"
module load prgenv/intel intel/${intel_v} hpcx-openmpi netcdf4/${ncdf_v} hdf5/${hdf5_v} jasper/${jasper_v} cdo nco/${nco_v} python3

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${NETCDF4_DIR}/lib"

date

datebeg=$1
dateend=$2
year_lim=$3

echo "$datebeg"
echo "$dateend"

source "${REPO_DIR}/config/varsets.sh"

for vs in "${ORDER[@]}"; do
  ${REPO_DIR}/submit.sh --job-name="wrf-${vs}" --time="${TIME[$vs]}" \
         --output="wrf-${vs}.%j.out" --error="wrf-${vs}.%j.out" \
         "run_out_generic.sh" "${datebeg}" "${dateend}" "${year_lim}" "${vs}"
  sleep 120
done

echo "$0 done."

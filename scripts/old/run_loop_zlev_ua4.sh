#!/bin/sh

#SBATCH --job-name=cp-zlevua
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=16:50:00
#SBATCH --hint=nomultithread
#SBATCH --output=cp-zlevua.%j.out
#SBATCH --error=cp-zlevua.%j.out
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt

set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

declare -a var=("ua300m" "ua250m" "ua200m" "ua150m" "ua100m" "ua50m")

RUN_DIR=$SCRATCH/WRF/output

cd ${RUN_DIR}

for (( v=0; v<${#var[@]}; v++)); do
#
  emkdir -p ec:CORDEX/eval/output/${var[$v]}
  ecp ${var[$v]}_* ec:CORDEX/eval/output/${var[$v]}/
#
done

for (( v=0; v<${#var[@]}; v++)); do
#
  scp ../output/${var[$v]}_*.nc wrf@nimbus.degge.fc.ul.pt:/media/tor_disk2/data/wrf/CORDEX_CMIP6/output
done

echo "$0 done."                             


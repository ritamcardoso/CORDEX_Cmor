#!/bin/sh
#SBATCH --job-name=wrf-trans
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=30:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=wrf-trans.%j.out
#SBATCH --error=wrf-trans.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt
set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4

declare -a var=("sfcWindmax" "prcmax" "prncmax")
#declare -a var=("prsn" "sund" "snm" "evpsbl" "siconca")
#declare -a var=("tas" "ts" "th" "hurs" "huss" "hfls" "hfss" "psl" "ps" "sfcWind" "uas" "vas" "z0" "zmla")
#declare -a var=("va300m" "va250m" "va200m" "va150m" "va100m" "va50m")
#declare -a var=("ua300m" "ua250m" "ua200m" "ua150m" "ua100m" "ua50m")
#declare -a var=("ua1000" "ua925" "ua850" "ua750" "ua700" "ua600" "ua500" "ua400" "ua300" "ua250" "ua200" "ua150" "ua100" "ua70" "ua50" "ua30")
#declare -a var=("zg1000" "zg925" "zg850" "zg750" "zg700" "zg600" "zg500" "zg400" "zg300" "zg250" "zg200" "zg150" "zg100" "zg70" "zg50" "zg30")
#declare -a var=("rsds" "rlds" "rsus" "rlus" "rlut" "rsdscs" "rsdsdir" "rsdt" "rsut")
#declare -a var=("hus1000" "hus925" "hus850" "hus750" "hus700" "hus600" "hus500" "hus400" "hus300" "hus250" "hus200" "hus150" "hus100" "hus70" "hus50" "hus30")

#RUN_DIR=$SCRATCH/WRF/output
RUN_DIR=$SCRATCH/WRFxtrm

for (( v=0; v<${#var[@]}; v++)); do
#
emkdir -p ec:CORDEX/eval/output/${var[$v]}

ecp ${RUN_DIR}/${var[$v]}_*.nc ec:CORDEX/eval/output/${var[$v]}/
#ecp ${RUN_DIR}/${var[$v]}/* ec:CORDEX/eval/output/${var[$v]}/
#
done

echo "$0 done."

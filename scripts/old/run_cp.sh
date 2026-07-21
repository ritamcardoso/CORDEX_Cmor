#!/bin/sh

#SBATCH --job-name=scp-out
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=25:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=scp-out.%j.out
#SBATCH --error=scp-out.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt



set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

#declare -a var=("prw" "clivi" "clwvi" "hfls" "hfss")
#declare -a var=("snc" "snw" "snd" "mrsos" "mrso" "mrfsos")
#declare -a var=("hus1000" "hus925" "hus850" "hus700" "hus750" "hus600" "hus500" "hus400" "hus300" "hus250" "hus200" "hus150" "hus100" "hus70" "hus50" "hus30")
#declare -a var=("zg1000" "zg925" "zg850" "zg750" "zg700" "zg600" "zg500" "zg400" "zg300" "zg250" "zg200" "zg150" "zg100" "zg70" "zg50" "zg30")
#declare -a var=("wa1000" "wa925" "wa850" "wa750" "wa700" "wa600" "wa500" "wa400" "wa300" "wa250" "wa200" "wa150" "wa100" "wa70" "wa50" "wa30")
#declare -a var=("pr" "prc" "rsds" "rlds" "rsus" "rlus" "rlut" "rsdscs" "rsdsdir" "rsdt" "rsut" "sund")
declare -a var=("ua1000" "ua925" "ua850" "ua750" "ua700" "ua600" "ua500" "ua400" "ua300" "ua250" "ua200" "ua150" "ua100" "ua70" "ua50" "ua30")

RUN_DIR=$SCRATCH/WRF/output


for (( v=0; v<${#var[@]}; v++)); do
#
#  scp ${RUN_DIR}/${var[$v]}/${var[$v]}_*.nc wrf@vortex.degge.fc.ul.pt:/media/tor_disk2/data/wrf/CORDEX_CMIP6/output
  scp ${RUN_DIR}/${var[$v]}_*.nc wrf@nimbus.degge.fc.ul.pt:/media/Synology14/CORDEX_CMIP6/evaluation/output
#
done

echo "$0 done."                             


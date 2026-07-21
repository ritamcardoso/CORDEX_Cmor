#!/bin/sh

#SBATCH --job-name=loop-soil
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=2:50:00
#SBATCH --hint=nomultithread
#SBATCH --output=loop-soil.%j.out
#SBATCH --error=loop-soil.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt

set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

declare -a var=("mrfso" "mrfsos" "mrso" "mrsos" "mrro" "mrros" "tsl" "mrsfl" "mrsol")

RUN_DIR=$SCRATCH/ssp370/output

date

date1=$1
date2=$2
date3=$3

datebeg=${date1}
dateend=${date2}
year_lim=${date3}

echo $datebeg
echo $dateend

yeari=`echo $datebeg | cut -c1-4 `
echo $yeari
yearf=`echo $dateend | cut -c1-4 `
echo $yearf

mmi=`echo $datebeg | cut -c5-6 `
echo $mmi

mmf=`echo $dateend | cut -c5-6 `
echo $mmf

yeari=$(( $yeari + 1 ))
yearf=$(( $yearf + 1 ))


datebeg=${yeari}${mmi}
echo $datebeg
dateend=${yearf}${mmf}
echo $dateend

cd Analysis
#
#if [ $yeari -le $year_lim ]; then
#
#  sbatch run_out.sh ${datebeg} ${dateend} ${year_lim}
#  sbatch run_out_soil.sh ${datebeg} ${dateend} ${year_lim}
#
#fi
#

cd ${RUN_DIR}

for (( v=0; v<${#var[@]}; v++)); do
#
  emkdir -p ec:CORDEX/scenarios/ssp370/output/${var[$v]}
  ecp -o ${var[$v]}_* ec:CORDEX/scenarios/ssp370/output/${var[$v]}/
#
done

yeari=$(( $yeari - 1 ))

for (( v=0; v<${#var[@]}; v++)); do
#
  scp ${var[$v]}_*${yeari}*.nc wrf@nimbus.degge.fc.ul.pt:/media/Synology14/CORDEX_CMIP6/scenarios/output/ssp370/${var[$v]}/raw
#
done

echo "$0 done."                             


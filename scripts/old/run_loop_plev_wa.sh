#!/bin/sh

#SBATCH --job-name=loop-plev_wa
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=50:00
#SBATCH --hint=nomultithread
#SBATCH --output=loop-plev_wa.%j.out
#SBATCH --error=loop-plev_wa.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt

set -x

##### Submit as run_loop_plev_wa.sh date1 date2 date3  (yyyymmdd yyyymmdd yyyy)

#### Load libraries for compiling
intel_v="2021.4";
hdf5_v="1.12.2";
netcdf_v="4.9.3";
jasper_v="2.0.14";
nco_v="4.9.7"
###########

module load prgenv/intel intel/${intel_v} hpcx-openmpi netcdf4/${netcdf_v} hdf5/${hdf5_v} jasper/${jasper_v} cdo nco/${nco_v} python3
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

declare -a var=("wa1000" "wa925" "wa850" "wa750" "wa700" "wa600" "wa500" "wa400" "wa300" "wa250" "wa200" "wa150" "wa100" "wa70" "wa50" "wa30")

RUN_DIR=$SCRATCH/ssp370/plev_wa

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
if [ $yeari -le $year_lim ]; then
#
#  sbatch run_out_plev_wa.sh ${datebeg} ${dateend} ${year_lim}
#
   sbatch run_out_plev_zg.sh ${datebeg} ${dateend} ${year_lim}
#   
fi

cd ${RUN_DIR}

for (( v=0; v<${#var[@]}; v++)); do
#
  emkdir -p ec:CORDEX/scenarios/ssp370/output/${var[$v]}
  ecp ${var[$v]}_* ec:CORDEX/scenarios/ssp370/output/${var[$v]}/

  mv ${var[$v]}_*.nc ../output

#
done

yeari=$(( $yeari - 1 ))

  for (( v=0; v<${#var[@]}; v++)); do
#
  scp ../output/${var[$v]}_*${yeari}*.nc wrf@nimbus.degge.fc.ul.pt:/media/Synology14/CORDEX_CMIP6/scenarios/output/ssp370/${var[$v]}/raw
#
done

echo "$0 done."                             


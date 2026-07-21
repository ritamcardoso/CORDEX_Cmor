#!/bin/sh

#SBATCH --job-name=loop-zlev_ua
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=50:00
#SBATCH --hint=nomultithread
#SBATCH --output=loop-zlev_ua.%j.out
#SBATCH --error=loop-zlev_ua.%j.out
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt

set -x

##### Submit as run_loop_zlev_ua.sh date1 date2 date3  (yyyymmdd yyyymmdd yyyy)

#### Load libraries for compiling
intel_v="2021.4";
hdf5_v="1.12.2";
netcdf_v="4.9.3";
jasper_v="2.0.14";
nco_v="4.9.7"
###########

module load prgenv/intel intel/${intel_v} hpcx-openmpi netcdf4/${netcdf_v} hdf5/${hdf5_v} jasper/${jasper_v} cdo nco/${nco_v} python3
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

declare -a var=("ua300m" "ua250m")

RUN_DIR=$SCRATCH/WRF/zlev_ua

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
if [ `echo $mmi | cut -c1-1` -lt 1 ]; then
  monthi=`echo $mmi | cut -c2-2`
else
  monthi=${mmi}
fi

mmf=`echo $dateend | cut -c5-6 `
echo $mmf
if [ `echo $mmf | cut -c1-1` -lt 1 ]; then
  monthf=`echo $mmf | cut -c2-2`
else
  monthf=${mmf}
fi

yeari=$(( $yeari + 1 ))
yearf=$(( $yearf + 1 ))


datebeg=${yeari}${monthi}
echo $datebeg
dateend=${yearf}${mmf}
echo $dateend

if [ $yeari -le $year_lim ]; then

  sbatch run_out_zlev_ua.sh ${datebeg} ${dateend} ${year_lim}

fi

cd ${RUN_DIR}

for (( v=0; v<${#var[@]}; v++)); do
#
  emkdir -p ec:CORDEX/eval/output/${var[$v]}
  ecp ${var[$v]}_* ec:CORDEX/eval/output/${var[$v]}/

  mv ${var[$v]}_*.nc ../output

#
done

yeari=$(( $yeari - 1 ))

  for (( v=0; v<${#var[@]}; v++)); do
#
  scp ../output/${var[$v]}_*${yeari}*.nc wrf@nimbus.degge.fc.ul.pt:/media/Synology14/CORDEX_CMIP6/evaluation/output
#
done

echo "$0 done."                             


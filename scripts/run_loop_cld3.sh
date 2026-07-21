#!/bin/sh

#SBATCH --job-name=loop-cld3
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=6:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=loop-cld3.%j.out
#SBATCH --error=loop-cld3.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt

set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

declare -a var=("cll")

RUN_DIR=$SCRATCH/WRF/cld3

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

  sbatch run_out_cld3.sh ${datebeg} ${dateend} ${year_lim}

fi

cd ${RUN_DIR}

for (( v=0; v<${#var[@]}; v++)); do
#
  emkdir -p ec:CORDEX/eval/output/${var[$v]}
  ecp ${var[$v]}_* ec:CORDEX/eval/output/${var[$v]}/

  mv ${var[$v]}_*.nc ../output
done

yeari=$(( $yeari - 1 ))
for (( v=0; v<${#var[@]}; v++)); do
#
  scp ../output/${var[$v]}_*${yeari}*.nc wrf@nimbus.degge.fc.ul.pt:/media/Synology14/CORDEX_CMIP6/evaluation/output
done


echo "$0 done."                             


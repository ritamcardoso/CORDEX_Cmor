#!/bin/sh
#SBATCH --job-name=trans_wrf
#SBATCH --qos=nf
#SBATCH --ntasks=32
#SBATCH --time=48:00:00
#SBATCH --hint=nomultithread
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt/WRF
#
########################################################################################
#
# Run with
#
# sbatch transfer_CORDEX.sh 197901 198001
#
#################################################3
set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

date1=$1
date2=$2

datebeg=${date1}
echo $datebeg
datend=${date2}
echo $datend

yyyy=`echo $datebeg | cut -c1-4 `
echo $yyyy
yyyye=`echo $datend | cut -c1-4 `
echo $yyyye

month=`echo $datebeg | cut -c5-6 `
echo $month
if [ `echo $month | cut -c1-1` -lt 1 ]; then
  mm=`echo $month | cut -c2-2`
else
  mm=${month}
fi           

monthe=`echo $datend | cut -c5-6 `
echo $monthe
if [ `echo $monthe | cut -c1-1` -lt 1 ]; then
  mme=`echo $monthe | cut -c2-2`
else
  mme=${monthe}
fi


while [ $yyyy -le $yyyye ]
do


while [ $mm -le 12 ] # month loop
do  

mmf=${mm}

if [ $mmf -lt 10 ]; then
mmf=0${mmf}
fi

ecp --order=tape ec:CORDEX/eval/wrfout/${yyyy}/wrfout_d01_${yyyy}-${mmf}* .


mm=$((${mm} + 1))

if [ $yyyy -ge $yyyye ] && [ $mm -gt $mme ]; then
  exit 0
fi

done

if [ $mm -ge 12 ]; then
mm=1
echo $mm
fi

yyyy=$((${yyyy} + 1))

done

echo "$0 done."

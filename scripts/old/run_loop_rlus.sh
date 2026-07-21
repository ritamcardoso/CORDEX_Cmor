#!/bin/sh

#SBATCH --job-name=wrf-acum
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=6:00
#SBATCH --hint=nomultithread
#SBATCH --output=loop-acum.%j.out
#SBATCH --error=loop-acum.%j.out
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt

set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

date

date1=$1
date2=$2

datebeg=${date1}
dateend=${date2}

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


datebeg=${yeari}${monthf}
echo $datebeg
dateend=${yearf}${mmf}
echo $dateend

if [ $yeari -le 1989 ]; then

  sbatch run_rlus.sh ${datebeg} ${dateend}

fi

echo "$0 done."                             


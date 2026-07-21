#!/bin/sh
#SBATCH --job-name=wrf-3zlevua
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=20:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=wrf-3zlevua.%j.out
#SBATCH --error=wrf-3zlevua.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt
set -x

module load prgenv/intel netcdf4 hpcx-openmpi jasper/2.0.14 hdf5/1.12.2 nco/4.9.7 python3
#module load prgenv/intel intel/2021.4.0 hpcx-openmpi/2.9.0 netcdf4/4.7.4

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

#declare -a var=("ua1000" "ua925" "ua850" "ua750" "ua700" "ua600" "ua500" "ua400" "ua300" "ua250" "ua200" "ua150" "ua100" "ua70" "ua50")
#declare -a var=("ua300m" "ua250m" "ua200m" "ua150m" "ua100m" "ua50m")
declare -a var=("ua100m")
#declare -a var=("ua30")
declare -a run=("d01")

DATA_DIR=$SCRATCH/WRF
RUN_DIR=$SCRATCH/WRF/zlev_ua3
HEADER_DIR=$HPCPERM/CORDEX/Analysis/header
PROG_DIR=$HPCPERM/CORDEX/Analysis

mkdir -p WRF/zlev_ua3
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

for(( j = ${yeari}; j <= ${yearf}; j++ )) ; do
#
START_YY=`echo ${j}`
END_YY=`echo ${j}`
m=$((${yeari} + 1))

#
for (( v=0; v<${#var[@]}; v++)); do
  for (( r=0; r<${#run[@]}; r++)); do
#
    cat ${HEADER_DIR}/header_${run[$r]}.ini | sed s/_START_YY_/$START_YY/ | \
                                              sed s/_END_YY_/$END_YY/  > ${RUN_DIR}/header_out_${run[$r]}
#
    cd ${RUN_DIR}
    ln -sf ${DATA_DIR}/geo_em* .
    ln -sf ${DATA_DIR}/wrfout_d01_${j}* .
    ln -sf ${DATA_DIR}/wrfout_d01_${m}-01-01_00* .

#
    cat header_out_${run[$r]} > outputlist.inp
    echo "#" >> outputlist.inp
    echo "# Variable" >> outputlist.inp
    echo "#" >> outputlist.inp
    cat $HPCPERM/CORDEX/Analysis/header/header_${var[$v]} >> outputlist.inp
    echo "#" >> outputlist.inp
    echo "end" >> outputlist.inp
#
    ifort -check all -traceback ${PROG_DIR}/RCM_zlev_ua.f90 -o RCM_zlev_ua.exe -I/usr/local/apps/netcdf4/4.9.1/INTEL/2021.4/include -L/usr/local/apps/netcdf4/4.9.1/INTEL/2021.4/lib -lnetcdff -lnetcdf
    ./RCM_zlev_ua.exe
#
    for x in `ls ${var[$v]}_*.nc` ; do
#
      nccopy -k 4 -d 1 -s ${x} temp.nc
      rm ${x}
      mv temp.nc ${x}
#
    done
#
#    scp ${var[$v]}_*.nc wrf@vortex.degge.fc.ul.pt:/media/tor_disk2/data/wrf/CORDEX_CMIP6/output
    
#    mv ${var[$v]}_*.nc ../output
    rm outputlist.inp
    rm header_out_${run[$r]}
#    cd ..
#
  done
done
#
done

cd ..
cd ..

sbatch run_loop_zlev_ua3.sh ${datebeg} ${dateend}

echo "$0 done."

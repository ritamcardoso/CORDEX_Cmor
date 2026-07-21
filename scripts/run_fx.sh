#!/bin/sh
#SBATCH --job-name=wrf-o
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=3:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=wrf-o.%j.out
#SBATCH --error=wrf-o.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt
set -x

#### Load libraries for compiling 
intel_v="2021.4"; 
hdf5_v="1.12.2";
ncdf_v="4.9.3";
jasper_v="2.0.14";
nco_v="4.9.7"
module load prgenv/intel intel/${intel_v} hpcx-openmpi netcdf4/${ncdf_v} hdf5/${hdf5_v} jasper/${jasper_v} cdo nco/${nco_v} python3

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib
#

declare -a var=("orog" "sftlaf" "sftlf" "sfturf" "sftgif")
declare -a run=("d01")

DATA_DIR=$SCRATCH/WRF
RUN_DIR=$SCRATCH/WRF/out
HEADER_DIR=$HPCPERM/CORDEX/Analysis/header
PROG_DIR=$HPCPERM/CORDEX/Analysis
#
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
#
    cat header_out_${run[$r]} > outputlist.inp
    echo "#" >> outputlist.inp
    echo "# Variable" >> outputlist.inp
    echo "#" >> outputlist.inp
    cat $HPCPERM/CORDEX/Analysis/header/header_${var[$v]} >> outputlist.inp
    echo "#" >> outputlist.inp
    echo "end" >> outputlist.inp
#
    ifort -O3 ${PROG_DIR}/RCM_fx_${var[$v]}.f90 -o RCM_fx_${var[$v]}.exe -I/usr/local/apps/netcdf4/${ncdf_v}/INTEL/${intel_v}/include -L/usr/local/apps/netcdf4/${ncdf_v}/INTEL/${intel_v}/lib -lnetcdff -lnetcdf
    ./RCM_fx_${var[$v]}.exe
#
    for x in `ls ${var[$v]}*.nc` ; do
#
      nccopy -k 4 -d 1 -s ${x} temp.nc
      rm ${x}
      mv temp.nc ${x}
#
    done
#
    emkdir -p ec:CORDEX/eval/output/${var[$v]}
    ecp ${var[$v]}_* ec:CORDEX/eval/output/${var[$v]}/

#
    scp ${var[$v]}_*.nc wrf@vortex.degge.fc.ul.pt:/media/tor_disk2/data/wrf/CORDEX_CMIP6/output
    
    mv ${var[$v]}_*.nc ../output
    rm outputlist.inp
    rm header_out_${run[$r]}
#    cd ..
#
  done
done
#
done
echo "$0 done."

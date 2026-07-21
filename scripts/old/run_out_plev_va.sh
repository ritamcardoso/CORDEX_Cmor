#!/bin/sh
#SBATCH --job-name=wrf-plevva
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=12:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=wrf-plevva.%j.out
#SBATCH --error=wrf-plevva.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt

#----------------------------------------------------------------
#                          ENVIRONMENT                          |
#----------------------------------------------------------------
set -x
export J="-j 4"
source ~/.bash_compile_wrf

#### Load libraries for compiling
#intel_v="2021.4";
#hdf5_v="1.12.2";
#netcdf_v="4.9.3";
#jasper_v="2.0.14";
#nco_v="4.9.7"
#module load prgenv/intel intel/${intel_v} hpcx-openmpi netcdf4/${netcdf_v} hdf5/${hdf5_v} jasper/${jasper_v} cdo nco/${nco_v} python3
#export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$NETCDF4_DIR/lib

#----------------------------------------------------------------
#                          DIRECTORIES                          |
#----------------------------------------------------------------
DATA_DIR=$SCRATCH/wrf_run
PROG_DIR=$HPCPERM/CORDEX/scenarios/Analysis
HEADER_DIR=$HPCPERM/CORDEX/scenarios/Analysis/header

#----------------------------------------------------------------
#                           TO CHANGE                           |
#----------------------------------------------------------------
RUN_DIR=$SCRATCH/ssp370/plev_va
mkdir -p ssp370/plev_va

declare -a run=("d01")
#declare -a var=("va1000")
declare -a var=("va1000" "va925" "va850" "va750" "va700" "va600" "va500" "va400" "va300" "va250" "va200" "va150" "va100" "va70" "va50" "va30")

#----------------------------------------------------------------
#                             TIME                              |
#----------------------------------------------------------------
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

#----------------------------------------------------------------
#                              LOOP                             |
#----------------------------------------------------------------
cd ${RUN_DIR}

for(( j = ${yeari}; j <= ${yearf}; j++ )) ; do
 START_YY=`echo ${j}`
 END_YY=`echo ${j}`
 m=$((${j} + 1))

 #...............................................................
 #                             dom                              .
 #...............................................................
 for (( r=0; r<${#run[@]}; r++)); do
  ln -sf ${DATA_DIR}/geo_em.${run[$r]}.nc .
  ln -sf ${DATA_DIR}/wrfout_${run[$r]}_${j}* .
  ln -sf ${DATA_DIR}/wrfout_${run[$r]}_${m}-01-01_00* .

  #...............................................................
  #                             var                              .
  #...............................................................
  for (( v=0; v<${#var[@]}; v++)); do
   cat ${HEADER_DIR}/header_${run[$r]}.ini | sed s/_START_YY_/$START_YY/ | \
                                             sed s/_END_YY_/$END_YY/  > ${RUN_DIR}/header_out_${run[$r]}
   cat header_out_${run[$r]} > outputlist.inp
   echo "#" >> outputlist.inp
   echo "# Variable" >> outputlist.inp
   echo "#" >> outputlist.inp
   cat ${HEADER_DIR}/header_${var[$v]} >> outputlist.inp
   echo "#" >> outputlist.inp
   echo "end" >> outputlist.inp
   
#  ifort -O3 ${PROG_DIR}/RCM_plev_va.f90 -o RCM_plev_va.exe -I/usr/local/apps/netcdf4/${netcdf_v}/INTEL/${intel_v}/include -L/usr/local/apps/netcdf4/${netcdf_v}/INTEL/${intel_v}/lib -lnetcdff -lnetcdf
   ifort -O2  ${PROG_DIR}/RCM_plev_va.f90 -o RCM_plev_va.exe -I/usr/local/apps/netcdf4-parallel/4.9.2/INTEL/2023.2/HPCX/2.17/include -L/usr/local/apps/netcdf4-parallel/4.9.2/INTEL/2023.2/HPCX/2.17/lib64 -lnetcdff -lnetcdf -L/usr/local/apps/hdf5-parallel/1.14.3/INTEL/2023.2/HPCX/2.17/lib64 -lhdf5hl_fortran -lhdf5_hl -lhdf5_fortran -lhdf5 -lm -lz
   
   ./RCM_plev_va.exe
   
   rm outputlist.inp
   rm header_out_${run[$r]}
  
  done #var
 
 done #dom

done #year

#----------------------------------------------------------------
#                           END LOOP                            |
#----------------------------------------------------------------
cd ..
cd ..
cd Analysis

sbatch run_loop_plev_va.sh ${datebeg} ${dateend} ${year_lim}
#sbatch run_out_zlev_va0.sh ${datebeg} ${dateend} ${year_lim}

echo "$0 done."

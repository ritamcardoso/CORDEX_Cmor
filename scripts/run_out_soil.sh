#!/bin/sh
#SBATCH --job-name=wrf-soil
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=12:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=wrf-soil.%j.out
#SBATCH --error=wrf-soil.%j.out
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
#
# 0. Load libraries for compiling     
#	
intel_v="2023.2";
hdf5_v="1.14.3";
netcdf_v="4.9.2";
hpx_v="2.17";
#
# 1. Configuration                                              
#
FC="ifort"
#FFLAGS="-O2"
FFLAGS="-traceback -check all"
MOD_NAME="datvar_s"
SUB_NAME="shared_subs_v2"
#
# 2. NetCDF and HDF5 Paths                                      |
#	
NC_INC="-I/usr/local/apps/netcdf4-parallel/${netcdf_v}/INTEL/${intel_v}/HPCX/${hpx_v}/include"
NC_LIB="-L/usr/local/apps/netcdf4-parallel/${netcdf_v}/INTEL/${intel_v}/HPCX/${hpx_v}/lib64 -lnetcdff -lnetcdf"
HDF_LIB="-L/usr/local/apps/hdf5-parallel/${hdf5_v}/INTEL/${intel_v}/HPCX/${hpx_v}/lib64 -lhdf5hl_fortran -lhdf5_hl -lhdf5_fortran -lhdf5"
OTHER_LIBS="-lm -lz"

ALL_LIBS="$NC_INC $NC_LIB $HDF_LIB $OTHER_LIBS"

#----------------------------------------------------------------
#                           TO CHANGE                           |
#----------------------------------------------------------------

PROG_DIR=$HPCPERM/CORDEX/scenarios/Analysis
HEADER_DIR=$HPCPERM/CORDEX/scenarios/Analysis/header
HEADER_INI_DIR=$HPCPERM/CORDEX/scenarios/Analysis/header_ini
RUN_DIR=$SCRATCH/ssp370/soil
mkdir -p ssp370/soil

declare -a run=("d01")
declare -a var=("mrfso" "mrfsos" "mrso" "mrsos" "mrro" "mrros" "tsl" "mrsfl" "mrsol")
#declare -a var=("tsl" "mrsfl" "mrsol")

#---------------------------------------------------------------
#                        Processing                             |
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

cd ${RUN_DIR}
#
#  Time Loop (yeari <= yearf; it is usually =)                            |
#
for(( j = ${yeari}; j <= ${yearf}; j++ )) ; do

 START_YY=`echo ${j}`
 END_YY=`echo ${j}`
#
# Domain
#
 for (( r=0; r<${#run[@]}; r++)); do

  cp ${HEADER_INI_DIR}/global_EUR-11_${run[$r]}.ini  global_data.inp
	 
#
# Variables
# var
  for (( v=0; v<${#var[@]}; v++)); do
#
#  Create list from header_d0?.ini + header_[var]
#
   cat ${HEADER_INI_DIR}/cordex_EUR-11_${run[$r]}.ini | sed s/_START_YY_/$START_YY/ | \
                                             sed s/_END_YY_/$END_YY/  > ${RUN_DIR}/header_${run[$r]}
   cat header_${run[$r]} > inputlist.inp
   echo "!" >> inputlist.inp
   echo "! Variable" >> inputlist.inp
   echo "!" >> inputlist.inp
   cat ${HEADER_DIR}/header_${var[$v]} >> inputlist.inp
   echo "!" >> inputlist.inp
   echo "/" >> inputlist.inp
#
# Compiling
#
# 0. Compile the Module
#
   $FC $FFLAGS -c "${PROG_DIR}/${MOD_NAME}.f90"
#
# 1. Compile the common subroutines
#
    $FC $FFLAGS -c "${PROG_DIR}/${SUB_NAME}.f90" $NC_INC
#
# 2. Compile program
#   
      $FC $FFLAGS ${PROG_DIR}/RCM_sfc_${var[$v]}.f90 ${MOD_NAME}.o ${SUB_NAME}.o -o RCM_sfc_${var[$v]}.exe $ALL_LIBS

   ./RCM_sfc_${var[$v]}.exe
   
   rm inputlist.inp
   rm header_${run[$r]}
  
  done #var
 done #dom
done #year
#
#  Call loop batch to advance time and call the next run script
#
cd ../../Analysis

sbatch run_loop_soil.sh ${datebeg} ${dateend} ${year_lim}
#sbatch run_out.sh ${datebeg} ${dateend} ${year_lim}

echo "$0 done."

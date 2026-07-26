#!/bin/sh
#SBATCH --job-name=wrf-va
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=14:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=wrf-va.%j.out
#SBATCH --error=wrf-va.%j.out

#----------------------------------------------------------------
#                           TO CHANGE                           |
#----------------------------------------------------------------

ROOT_DIR=$HPCPERM/CORDEX/scenarios/Analysis
PROG_DIR=${ROOT_DIR}/f90_src
HEADER_DIR=${ROOT_DIR}/header
HEADER_INI_DIR=${ROOT_DIR}/header_ini
RUN_DIR=$SCRATCH/ssp370/plev_va
mkdir -p ssp370/plev_va

declare -a run=("d01")
declare -a var=("va1000" "va925" "va850" "va750" "va700" "va600" "va500" "va400" "va300" "va250" "va200" "va150" "va100" "va70" "va50" "va30")

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
FFLAGS="-O2"
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
#
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
   $FC $FFLAGS ${PROG_DIR}/RCM_plev_uava.f90 ${MOD_NAME}.o ${SUB_NAME}.o -o RCM_plev_uava.exe $ALL_LIBS
   
   ./RCM_plev_uava.exe

   rm inputlist.inp
   rm header_${run[$r]}
  
  done #var
 done #dom
done #year
#
#  Call loop batch to advance time and call the next run script
#
cd ${ROOT_DIR}/scripts

#sbatch --file=slurm_common.opts run_cp_plev_ua.sh ${datebeg} ${dateend} ${year_lim}
#sbatch --file=slurm_common.opts run_cp_plev_va.sh ${datebeg} ${dateend} ${year_lim}

yeari=$(( $yeari + 1 ))
yearf=$(( $yearf + 1 ))

datebeg=${yeari}
echo $datebeg
dateend=${yearf}
echo $dateend

if [ $yeari -le $year_lim ]; then
 sbatch --file=slurm_common.opts run_out_plev_uava.sh ${datebeg} ${dateend} ${year_lim}
fi

echo "$0 done."

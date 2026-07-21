#!/bin/sh
#SBATCH --job-name=Analysis
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=15:00
#SBATCH --hint=nomultithread
#SBATCH --output=analysis.%j.out
#SBATCH --error=analysis.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt
#
# Usage: ./build_cordex.sh RCM_sfc_rad (name of program without .f90)
#
#----------------------------------------------------------------
#                          ENVIRONMENT                          |
#----------------------------------------------------------------

set -x
export J="-j 4"
source ~/.bash_compile_wrf

# 0. Load libraries for compiling
intel_v="2023.2";
hdf5_v="1.14.3";
netcdf_v="4.9.2";
hpx_v="2.17";

# 1. Configuration
FC="ifort"
FFLAGS="-O2"
MOD_NAME="datvar_s"
SUB_NAME="shared_subs_v2"
PROG_NAME=$1
PROG_DIR="$HPCPERM/CORDEX/scenarios/Analysis"

# 2. NetCDF and HDF5 Paths
NC_INC="-I/usr/local/apps/netcdf4-parallel/${netcdf_v}/INTEL/${intel_v}/HPCX/${hpx_v}/include"
NC_LIB="-L/usr/local/apps/netcdf4-parallel/${netcdf_v}/INTEL/${intel_v}/HPCX/${hpx_v}/lib64 -lnetcdff -lnetcdf"
HDF_LIB="-L/usr/local/apps/hdf5-parallel/${hdf5_v}/INTEL/${intel_v}/HPCX/${hpx_v}/lib64 -lhdf5hl_fortran -lhdf5_hl -lhdf5_fortran -lhdf5"
OTHER_LIBS="-lm -lz"

ALL_LIBS="$NC_INC $NC_LIB $HDF_LIB $OTHER_LIBS"

#------------------------------------------------------------------------------
#                    COMPILING                                                |
#-----------------------------------------------------------------------------

# 1. Compile the Module if it hasn't been compiled yet
if [ ! -f "${MOD_NAME}.o" ]; then
    echo "Compiling shared module..."
    $FC $FFLAGS -c "${PROG_DIR}/${MOD_NAME}.f90"
fi

# 2. Compile the common subroutines
if [ ! -f "${SUB_NAME}.o" ]; then
    echo "Compiling shared subroutines..."
    $FC $FFLAGS -c "${PROG_DIR}/${SUB_NAME}.f90" $NC_INC
fi

# 3. Compile program
echo "Building ${PROG_NAME}.exe..."
$FC $FFLAGS "${PROG_DIR}/${PROG_NAME}.f90" "${MOD_NAME}.o" "${SUB_NAME}.o" -o "${PROG_NAME}.exe" $ALL_LIBS

if [ $? -eq 0 ]; then
    echo "Success: ${PROG_NAME}.exe created."
else
    echo "Error: Compilation failed."
fi

#!/bin/sh
#SBATCH --job-name=Analysis
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=24:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=analysis.%j.out
#SBATCH --error=analysis.%j.out
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

cd Analysis

# out -> plev_ua 
sbatch run_out.sh ${datebeg} ${dateend} ${year_lim}

# acum -> snow -> plev_hus -> zlev_hus
sbatch run_out_acum.sh ${datebeg} ${dateend} ${year_lim}

# cloud -> wpth
sbatch run_out_cloud.sh ${datebeg} ${dateend} ${year_lim}

# soil -> plev_wa -> zlev_va0
sbatch run_out_soil.sh ${datebeg} ${dateend} ${year_lim}

# tau -> plev_va -> zlev_va1
sbatch run_out_tau.sh ${datebeg} ${dateend} ${year_lim}

# zlev_ta -> plev_ta -> zlev_ua0
sbatch run_out_zlev_ta.sh ${datebeg} ${dateend} ${year_lim}

# plev_zg -> zlev_ua1
sbatch run_out_plev_zg.sh ${datebeg} ${dateend} ${year_lim}

echo "$0 done."

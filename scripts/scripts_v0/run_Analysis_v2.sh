#!/bin/sh
#SBATCH --job-name=Analysis
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=30:00
#SBATCH --hint=nomultithread
#SBATCH --output=analysis.%j.out
#SBATCH --error=analysis.%j.out

# ------------------------------------------------------------------
#  Run using 
#
#  sbatch --file=slurm_common.opts run_Analysis_v2.sh [ initial year - yyyy] [ final year - yyyy]  [loop year -  yyyy] 
#
#-------------------------------------------------------------------

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

# out -> soil 
sbatch --file=slurm_common.opts run_out.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# acum -> snw
sbatch --file=slurm_common.opts run_out_acum.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# cloud -> wxtrm
sbatch --file=slurm_common.opts run_out_cloud.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# plev_wa -> plev_zg
sbatch --file=slurm_common.opts run_out_plev_wa.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# plev_ua 
sbatch --file=slurm_common.opts run_out_plev_uava.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# plev_va 
#sbatch --file=slurm_common.opts run_out_plev_va.sh ${datebeg} ${dateend} ${year_lim}

#sleep 120

# zlev_hus -> plev_hus
sbatch --file=slurm_common.opts run_out_zlev_hus.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# zlev_ta -> plev_ta 
sbatch --file=slurm_common.opts run_out_zlev_ta.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# zlev_ua0 
#sbatch --file=slurm_common.opts run_out_zlev_ua0.sh ${datebeg} ${dateend} ${year_lim}
sbatch --file=slurm_common.opts run_out_zlev_uava0.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# zlev_ua1  
#sbatch --file=slurm_common.opts run_out_zlev_ua1.sh ${datebeg} ${dateend} ${year_lim}
sbatch --file=slurm_common.opts run_out_zlev_uava1.sh ${datebeg} ${dateend} ${year_lim}

sleep 120

# zlev_va0
#sbatch --file=slurm_common.opts run_out_zlev_va0.sh ${datebeg} ${dateend} ${year_lim}

#sleep 120

# zlev_va1
#sbatch --file=slurm_common.opts run_out_zlev_va1.sh ${datebeg} ${dateend} ${year_lim}

#sleep 120

# tau -> wpth
sbatch --file=slurm_common.opts run_out_tau.sh ${datebeg} ${dateend} ${year_lim}


echo "$0 done."

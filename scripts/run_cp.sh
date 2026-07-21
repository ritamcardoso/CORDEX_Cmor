#!/bin/sh

#SBATCH --job-name=scp-out2
#SBATCH --qos=nf
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=25:00:00
#SBATCH --hint=nomultithread
#SBATCH --output=scp-out.%j.out
#SBATCH --error=scp-out.%j.out
#SBATCH --account=spptcard
#SBATCH --mail-type=ALL
#SBATCH --mail-user=rmcardoso@fc.ul.pt
#SBATCH --chdir=/ec/res4/scratch/ptrt

set -x

year="$1"

declare -a var=("evspsbl" "hfls" "hfss" "hurs" "huss" "prsn" "ps" "psl" "sfcWind" "siconca" "snc" "snd" "snm" "snw" "tas" "th" "ts" "uas" "vas" "z0" "zmla" )
#declare -a var=("ta100" "ta1000" "ta150" "ta200" "ta250" "ta30" "ta300" "ta400" "ta50" "ta500" "ta600" "ta70" "ta700" "ta750" "ta850" "ta925" )

#declare -a var=("evspsbl" "hfls" "hfss" "hurs" "huss" "prcmax" "prncmax" "ps" "psl" "sfcWind" "sfcWindmax" "tas" "tasmin" "th" "ts" "ua150m" "ua300m" "uas" "va150m" "va300m" "vas" "z0" "zmla" )
#declare -a var=("mrsfl" "prc" "prcmax" "prsn" "snd" "snw" "ua250m" "va100m" "va200m" )
#declare -a var=("evspsbl" "hfls" "hfss" "hurs" "huss" "ps" "psl" "sfcWind" "tas" "th" "ts" "uas" "vas" "z0" "zmla" )
#declare -a var=("ta50m" )
#declare -a var=("pr" "prc" "rlds" "rldscs" "rlus" "rluscs" "rlut" "rlutcs" "rsds" "rsdscs" "rsdsdir" "rsdt" "rsus" "rsuscs" "rsut" "rsutcs" "sund" "ua100" "ua1000" "ua150" "ua200" "ua250" "ua30" "ua300" "ua400" "ua50" "ua500" "ua600" "ua70" "ua700" "ua750" "ua850" "ua925" )

RUN_DIR=$SCRATCH/ssp370/output

#ecp ec:CORDEX/scenarios/ssp370/output/ua250m/ua250m_EUR-12_MPI-ESM1-2-HR_ssp370_r1i1p1f1_IDL-FCUL_WRF451Q_v1-r1_1hr_2067010100-2067123123.nc ${RUN_DIR}

for (( v=0; v<${#var[@]}; v++)); do
#
#  ecp -o ${RUN_DIR}/${var[$v]}_*.nc ec:CORDEX/scenarios/ssp370/output/${var[$v]}

#  scp ${RUN_DIR}/${var[$v]}/${var[$v]}_*.nc wrf@vortex.degge.fc.ul.pt:/media/tor_disk2/data/wrf/CORDEX_CMIP6/output
  scp ${RUN_DIR}/${var[$v]}_*${year}*.nc wrf@nimbus.degge.fc.ul.pt:/media/Synology14/CORDEX_CMIP6/scenarios/output/ssp370/${var[$v]}/raw
#
done

echo "$0 done."                             


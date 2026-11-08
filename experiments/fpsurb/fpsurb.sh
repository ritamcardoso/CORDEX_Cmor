#!/bin/bash
#
# experiments/fpsurb/fpsurb.sh — FPS-URB-RCC urban downscaling (Paris).
# Every array is keyed by grid (d01, d02, ...); each grid in run[] needs an
# entry in all of them. See README.md §2.
#----------------------------------------------------------------

#
#--- Working directory (one subfolder per varset) ---------------
# Each varset works (namelists, compiled programs) in ${ROOT_RUN_DIR}/<varset>.
#
ROOT_RUN_DIR=$SCRATCH/fpsurb
mkdir -p "${ROOT_RUN_DIR}"

#
#--- Grids to process (comment a line out to skip it) ------------
# Only the keys matter; every job processes these grids in order (d01, d02, ...).
# Enabling a second grid makes every job longer: raise TIME[] to match.
#
declare -A run=(
#  [d01]=1
  [d02]=1
)

#
#--- Domain ID per grid (picks the grid's two ini files) --------
# Picks the grid's <name>_<DOMAIN_ID>_<grid>.ini and
# <name>_global_<DOMAIN_ID>_<grid>.ini in this folder.
#
declare -A DOMAIN_ID=(
  [d01]="EUR-12"
  [d02]="PARIS-3"
)

#
#--- WRF input folder per grid ----------------------------------
# Where the raw wrfout_d0N_* / wrfxtrm_d0N_* files are.
#
declare -A OUTPUT_WRF=(
  [d01]=$SCRATCH/urb_wrf_run
  [d02]=$SCRATCH/urb_wrf_run
)

#
#--- Output folder per grid (a different one for each grid) -----
# Where the CMORised files are written; it is also what the archive step
# copies from, so each grid needs its own.
#
declare -A OUTPUT_DIR=(
  [d01]=${ROOT_RUN_DIR}/output_d01
  [d02]=${ROOT_RUN_DIR}/output_d02
)
# create the output folder of every grid in run[]
for g in "${!run[@]}"; do
  mkdir -p "${OUTPUT_DIR[$g]}"
done

#
#--- ECFS archive path per grid ---------------------------------
# ECFS base path; each variable goes to <path>/<var>/.
#
declare -A ECFS_BASE=(
  [d01]="ec:FPS_URBAN/STAGE1/eval/output_d01"
  [d02]="ec:FPS_URBAN/STAGE1/eval/output_d02"
)

#
#--- Remote archive path per grid (on REMOTE_HOST) --------------
# Base path on REMOTE_HOST (env.site.sh); each variable goes to <path>/<var>/raw.
#
declare -A REMOTE_BASE=(
  [d01]="/media/Synology14/FPS_URBAN/eval/output_d01"
  [d02]="/media/Synology14/FPS_URBAN/eval/output_d02"
)

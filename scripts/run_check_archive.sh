#!/bin/bash
#
# scripts/run_check_archive.sh — job: tools/check_archive.sh on a compute node.
# Usage: ./tools/check_archive.sh -b [check_archive options] <start_year> <end_year>
#        ./submit.sh [--time=hh:mm:ss] run_check_archive.sh -e <experiment> [options] <start_year> <end_year>
# The remote check needs ssh from the node to REMOTE_HOST without a password
# (as the archive jobs' scp); the ECFS check needs els. See README.md §11.
#----------------------------------------------------------------

#
#--- Repo location (set by submit.sh) ----------------------------
#
: "${ROOT_DIR:?ROOT_DIR is not set — submit this script through submit.sh or check_archive.sh -b, not plain sbatch (see README.md §0)}"

#
#--- Run ---------------------------------------------------------
#
exec "${ROOT_DIR}/tools/check_archive.sh" "$@"

#!/bin/bash
#
# scripts/run_check_archive.sh — job: tools/check_archive.sh on a compute node.
# Usage: ./tools/check_archive.sh -b [check_archive options] <start_year> <end_year>
#        CHECK_ARCHIVE_ARGS="-e <experiment> [options] <start_year> <end_year>" \
#          ./submit.sh [--time=hh:mm:ss] run_check_archive.sh
# The options come in CHECK_ARCHIVE_ARGS (check_archive.sh -b sets it): on
# the sbatch command line, after the script name, a wrapper such as ECMWF's
# ecsbatch would take -e, -d, -t, ... as its own options.
# The remote check needs ssh from the node to REMOTE_HOST without a password
# (as the archive jobs' scp); the ECFS check needs els. See README.md §11.
#----------------------------------------------------------------

#
#--- Repo location (set by submit.sh) ----------------------------
#
: "${ROOT_DIR:?ROOT_DIR is not set — submit this script through submit.sh or check_archive.sh -b, not plain sbatch (see README.md §0)}"

#
#--- Options -----------------------------------------------------
# From CHECK_ARCHIVE_ARGS (shell-quoted by check_archive.sh -b), or the
# command line if given.
#
if [ $# -eq 0 ]; then
  : "${CHECK_ARCHIVE_ARGS:?no options: set CHECK_ARCHIVE_ARGS, or use tools/check_archive.sh -b}"
  eval "set -- ${CHECK_ARCHIVE_ARGS}"
fi
echo "check_archive.sh $*"

#
#--- Run ---------------------------------------------------------
#
exec "${ROOT_DIR}/tools/check_archive.sh" "$@"

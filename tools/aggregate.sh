#!/bin/bash
# NCO attribute edits are comma-separated (att,var,mode,type,value) on purpose:
# shellcheck disable=SC2054
#
# tools/aggregate.sh — daily files from the sub-daily (1hr, 3hr, 6hr) files and
# monthly files from the daily values, for the variables of the CORDEX-CMIP6
# day and mon tables (tools/aggregation_table.txt).
#
# Usage: tools/aggregate.sh [options] <first year> [<last year>] [<variable> ...]
#   tools/aggregate.sh 2015 2020              every variable that has files
#   tools/aggregate.sh -f mon 2015 2020 tas   monthly tas only
#   EXPERIMENT=lucas tools/aggregate.sh 2015  another experiment
# Run it as a job for many variables: ./submit.sh --time=12:00:00 run_aggregate.sh 2015 2020
# (or ./run.sh -a fpsurb 2015 2020). See README.md §11.
#----------------------------------------------------------------

set -uo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 [options] <first year> [<last year>] [<variable> ...]

Writes, next to the existing files of each grid (OUTPUT_DIR of the experiment):
  daily   files (5 years per file: years 1-5 and 6-0) from the 1hr/3hr/6hr files,
          or from the daily files already there (e.g. tasmax from wrfxtrm);
  monthly files (10 years per file: years 1-0) from the daily values.
The files covering the years asked for are (re)built whole: a daily file of
2011-2015 needs 2011-2015, a monthly file of 2011-2020 needs 2011-2020 (the
years that have data). Daily or monthly files they replace are moved to
<OUTPUT_DIR>/superseded/ (never deleted).

Options:
  -f day|mon|both  which frequencies to write (default: both)
  -j <n>           variables processed at the same time (default: 1)
  -w <dir>         folder for temporary files (default: \$TMPDIR, else /tmp; a local disk)
  -p <path>        ncrepack-cordex to repack the new files (default: tools/ncrepack-cordex
                   when REPACK is not "off" in env.site.sh; "-p off" to skip)
  -s               daily values from the sub-daily files even where daily files exist
  -n               dry run: show what would be written
  -r <repo>        the CORDEX_Cmor folder (default: the folder above tools/)
EOF
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FREQS=both; NJOB=1; WORK_BASE="${TMPDIR:-/tmp}"; NCREPACK=""; FROM_SUB=0; DRY=0
while getopts "f:j:w:p:snr:h" opt; do
  case "$opt" in
    f) FREQS="$OPTARG" ;;
    j) NJOB="$OPTARG" ;;
    w) WORK_BASE="$OPTARG" ;;
    p) NCREPACK="$OPTARG" ;;
    s) FROM_SUB=1 ;;
    n) DRY=1 ;;
    r) REPO="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || usage
Y1="$1"; shift; Y2="$Y1"
if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]{4}$ ]]; then Y2="$1"; shift; fi
VARS_ASKED=("$@")
[[ "$Y1" =~ ^[0-9]{4}$ && "$Y2" =~ ^[0-9]{4}$ && "$Y1" -le "$Y2" ]] || { echo "Give the years as 4 digits, first <= last." >&2; exit 1; }
case "$FREQS" in day|mon|both) ;; *) usage ;; esac
[[ "$NJOB" =~ ^[1-9][0-9]*$ ]] || usage
WANT_DAY=0; WANT_MON=0
[ "$FREQS" != mon ] && WANT_DAY=1
[ "$FREQS" != day ] && WANT_MON=1

for t in ncks ncra ncrcat ncap2 ncatted ncrename awk; do
  command -v "$t" >/dev/null || { echo "$t not found — load NCO first (e.g. module load nco)." >&2; exit 1; }
done
TABLE="${SCRIPT_DIR}/aggregation_table.txt"
[ -f "$TABLE" ] || { echo "No $TABLE." >&2; exit 1; }

#
#--- Experiment: OUTPUT_DIR of every grid ------------------------
# EXPERIMENT from env.site.sh (read in a subshell), or from the environment.
#
ROOT_DIR="$(cd -- "$REPO" && pwd)"
[ -f "$ROOT_DIR/scripts/load_experiment.sh" ] || { echo "$ROOT_DIR is not the CORDEX_Cmor folder; give it with -r." >&2; exit 1; }
SITE_REPACK=on
if [ -f "$ROOT_DIR/env.site.sh" ]; then
  # shellcheck source=/dev/null
  read -r site_exp SITE_REPACK <<< "$(set +eu; source "$ROOT_DIR/env.site.sh" >/dev/null 2>&1; echo "${EXPERIMENT:-} ${REPACK:-on}")"
  EXPERIMENT="${CMOR_EXPERIMENT:-${EXPERIMENT:-$site_exp}}"
fi
: "${EXPERIMENT:?No EXPERIMENT (env.site.sh or EXPERIMENT=<name>).}"
export ROOT_DIR EXPERIMENT CMOR_EXPERIMENT="$EXPERIMENT"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/load_experiment.sh" || exit 1

if [ -z "$NCREPACK" ] && [ "$SITE_REPACK" != off ]; then NCREPACK="$ROOT_DIR/tools/ncrepack-cordex"; fi
[ "$NCREPACK" = off ] && NCREPACK=""
if [ -n "$NCREPACK" ] && [ "$DRY" = 0 ]; then
  [ -x "$NCREPACK" ] || { echo "ncrepack-cordex not found: $NCREPACK" >&2; exit 1; }
  for t in h5repack h5stat h5dump; do
    command -v "$t" >/dev/null || { echo "$t not found — load an HDF5 module, or use -p off." >&2; exit 1; }
  done
fi

#
#--- Aggregation rules (tools/aggregation_table.txt) -------------
# T_SRC, T_DM, T_DCM, T_DLN, T_MM, T_MCM, T_MLN[<var>]: source variable, day
# method / cell_methods / long_name, mon method / cell_methods / long_name.
#
declare -A T_SRC=() T_DM=() T_DCM=() T_DLN=() T_MM=() T_MCM=() T_MLN=()
while IFS='|' read -r v s dm dcm dln mm mcm mln; do
  [[ -z "$v" || "$v" == \#* ]] && continue
  T_SRC[$v]=$s; T_DM[$v]=$dm; T_DCM[$v]=$dcm; T_DLN[$v]=$dln; T_MM[$v]=$mm; T_MCM[$v]=$mcm; T_MLN[$v]=$mln
done < "$TABLE"

#
#--- Helpers -----------------------------------------------------
#
step() { "$@" || { echo "ERROR in: $*" >&2; return 1; }; }
gatt() { ncks -M -m "$2" 2>/dev/null | sed -n "s/^[[:space:]]*:$1 = \"\(.*\)\" ;.*/\1/p" | sed -n '1p'; }
has_var() { ncks -m "$2" 2>/dev/null | grep -qE "^[[:space:]]+[a-z0-9]+ $1( ;|\()"; }
has_dim() { ncks -m "$2" 2>/dev/null | sed -n '/dimensions:/,/variables:/p' | grep -qE "^[[:space:]]+$1 = "; }
ntime() { ncks -m "$1" 2>/dev/null | sed -n 's/^[[:space:]]*time = UNLIMITED ; \/\/ (\([0-9]*\) currently)/\1/p; s/^[[:space:]]*time = \([0-9]*\) ;/\1/p' | head -1; }
times() { ncks -H -C -v time -s '%.6f\n' "$1" 2>/dev/null | sed '/^[[:space:]]*$/d'; }
# the global history attribute, all its lines (the CDL listing shortens multi-line text)
hist_of() {
  ncks --trd -M -m "$1" 2>/dev/null | awk '
    /^Global attribute [0-9]+: history, / {sub(/^.*value = /, ""); h=1; print; next}
    h && (/^Global attribute [0-9]+: / || /^$/) {exit}
    h {print}'
}
new_uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())'; }
# days since 1950-01-01 <-> civil date (proleptic Gregorian)
AWK_CIVIL='
function dfc(y,m,d,  era,yoe,doy,doe){ y-=(m<=2); era=int((y>=0?y:y-399)/400); yoe=y-era*400;
  doy=int((153*(m+(m>2?-3:9))+2)/5)+d-1; doe=yoe*365+int(yoe/4)-int(yoe/100)+doy; return era*146097+doe-719468-(-7305) }
function cfd(z,  era,doe,yoe,y,doy,mp,d,m){ z+=719468-7305; era=int((z>=0?z:z-146096)/146097); doe=z-era*146097;
  yoe=int((doe-int(doe/1460)+int(doe/36524)-int(doe/146096))/365); y=yoe+era*400; doy=doe-(365*yoe+int(yoe/4)-int(yoe/100));
  mp=int((5*doy+2)/153); d=doy-int((153*mp+2)/5)+1; m=mp+(mp<10?3:-9); y+=(m<=2); return sprintf("%04d %02d %02d",y,m,d) }'
days_from() { awk -v y="$1" -v m="$2" -v d="$3" "$AWK_CIVIL"' BEGIN{print dfc(y+0,m+0,d+0)}'; }
# years a file covers, from its name: <...>_<start>-<end>.nc
name_years() {
  [[ "$1" =~ _([0-9]{4})[0-9]*-([0-9]{4})[0-9]*\.nc$ ]] || return 1
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
}
# block of year y: daily 5 years (1-5, 6-0), monthly 10 years (1-0), from the first year
block() {  # block <len> <year> <first available> <last available> -> "start end"
  local n=$1 y=$2 a=$3 b=$4 s e
  s=$(( y - (y - 1) % n )); e=$(( s + n - 1 ))
  [ "$s" -lt "$a" ] && s=$a; [ "$e" -gt "$b" ] && e=$b
  echo "$s $e"
}

#
#--- One variable --------------------------------------------------
# agg_var <OUTPUT_DIR> <variable>: daily values per year (from daily files, or
# sub-daily ones), then the daily and monthly block files.
#
agg_var() {
  local dir=$1 v=$2 src dm mm f y
  src=${T_SRC[$v]}; dm=${T_DM[$v]}; mm=${T_MM[$v]}
  local do_day=$WANT_DAY do_mon=$WANT_MON
  [ "$dm" = "-" ] && do_day=0
  [ "$mm" = "-" ] && do_mon=0
  [ $do_day = 1 ] || [ $do_mon = 1 ] || { echo "$v: not in the day or mon tables — skipped"; return 0; }

  # sources per year: daily files of v (unless -s), else sub-daily files of src (1hr, then 3hr, then 6hr)
  declare -A day_src=() sub_src=() sub_n=()
  local yrs a b fr nn
  if [ "$FROM_SUB" = 0 ]; then
    while IFS= read -r f; do
      read -r a b <<< "$(name_years "$(basename "$f")")" || continue
      for ((y = a; y <= b; y++)); do day_src[$y]=${day_src[$y]:-$f}; done
    done < <(find "$dir" -maxdepth 1 -name "${v}_*_day_*.nc" | sort)
  fi
  if [ "$dm" != "-" ]; then
    for fr in 1hr:24 3hr:8 6hr:4; do
      nn=${fr#*:}; fr=${fr%:*}
      while IFS= read -r f; do
        read -r a b <<< "$(name_years "$(basename "$f")")" || continue
        for ((y = a; y <= b; y++)); do
          [ -z "${sub_src[$y]:-}" ] && { sub_src[$y]=$f; sub_n[$y]=$nn; }
        done
      done < <(find "$dir" -maxdepth 1 -name "${src}_*_${fr}_*.nc" | sort)
    done
  fi
  yrs=$(printf '%s\n' "${!day_src[@]}" "${!sub_src[@]}" | sed '/^$/d' | sort -n | uniq)
  [ -n "$yrs" ] || { echo "$v: no daily or sub-daily files of ${src} in ${dir} — skipped"; return 0; }
  local first last
  first=$(head -1 <<< "$yrs"); last=$(tail -1 <<< "$yrs")

  # blocks touching the years asked for, and the years they need
  local dblocks=() mblocks=() need=() blk
  for ((y = Y1; y <= Y2; y++)); do
    [ "$y" -lt "$first" ] || [ "$y" -gt "$last" ] && continue
    [ $do_day = 1 ] && dblocks+=("$(block 5 "$y" "$first" "$last")")
    [ $do_mon = 1 ] && mblocks+=("$(block 10 "$y" "$first" "$last")")
  done
  mapfile -t dblocks < <(printf '%s\n' "${dblocks[@]+"${dblocks[@]}"}" | sed '/^$/d' | sort -u)
  mapfile -t mblocks < <(printf '%s\n' "${mblocks[@]+"${mblocks[@]}"}" | sed '/^$/d' | sort -u)
  [ ${#dblocks[@]} -gt 0 ] || [ ${#mblocks[@]} -gt 0 ] || { echo "$v: no data for ${Y1}-${Y2} (files cover ${first}-${last}) — skipped"; return 0; }
  for blk in "${dblocks[@]+"${dblocks[@]}"}" "${mblocks[@]+"${mblocks[@]}"}"; do
    read -r a b <<< "$blk"
    for ((y = a; y <= b; y++)); do
      if [ -n "${day_src[$y]:-}" ] || [ -n "${sub_src[$y]:-}" ]; then need+=("$y"); fi
    done
  done
  mapfile -t need < <(printf '%s\n' "${need[@]}" | sort -nu)

  echo "$v (${dir}): years ${need[*]}"
  for y in "${need[@]}"; do
    if [ -n "${day_src[$y]:-}" ]; then echo "  $y daily from $(basename "${day_src[$y]}")"
    else echo "  $y daily from $(basename "${sub_src[$y]}") (${dm} of ${sub_n[$y]} steps per day)"; fi
  done
  [ ${#dblocks[@]} -gt 0 ] && echo "  day files: ${dblocks[*]}"
  [ ${#mblocks[@]} -gt 0 ] && echo "  mon files: ${mblocks[*]}"
  [ "$DRY" = 1 ] && return 0

  local prefix="" sample
  sample=${sub_src[${need[0]}]:-${day_src[${need[0]}]}}
  prefix=$(basename "$sample" | sed -E 's/_(1hr|3hr|6hr|day|mon)_[0-9]+-[0-9]+\.nc$//')
  [ "$src" != "$v" ] && prefix="${v}${prefix#"$src"}"

  # daily values of each year: $wk/d_<year>.nc
  local i0 i1 t0 d0 nt op
  for y in "${need[@]}"; do
    f="$wk/d_${y}.nc"
    if [ -n "${day_src[$y]:-}" ]; then
      read -r i0 i1 <<< "$(times "${day_src[$y]}" | awk -v Y="$y" "$AWK_CIVIL"' {split(cfd(int($1+1e-6)),c," "); if (c[1]==Y) {if (s=="") s=NR-1; e=NR-1}} END{print s, e}')"
      [ -n "$i0" ] || { echo "ERROR $v: no ${y} records in ${day_src[$y]}" >&2; return 1; }
      step ncks -O -h -d time,"$i0","$i1" "${day_src[$y]}" "$f" || return 1
    else
      nn=${sub_n[$y]}; nt=$(ntime "${sub_src[$y]}")
      t0=$(times "${sub_src[$y]}" | head -1)
      # whole days only, starting at 00:00 (instantaneous) or within the first step (interval data)
      if ! awk -v t="$t0" -v n="$nn" 'BEGIN{f=t-int(t+1e-6); exit !(f < 1.0/n - 1e-6)}' || [ $(( nt % nn )) -ne 0 ]; then
        echo "ERROR $v ${y}: $(basename "${sub_src[$y]}") does not hold whole days (${nt} steps, first at ${t0})" >&2; return 1
      fi
      d0=$(awk -v t="$t0" 'BEGIN{printf "%d", int(t+1e-6)}')
      case "$dm" in mean) op=avg ;; max) op=max ;; min) op=min ;; sum) op=ttl ;; esac
      step ncra -O -h --mro -d time,,,"$nn","$nn" -y "$op" "${sub_src[$y]}" "$f" || return 1
      [ "$src" != "$v" ] && { step ncrename -O -h -v "${src},${v}" "$f" >/dev/null || return 1; }
      # time at 12:00 of each day, bounds 00:00-00:00
      nt=$(ntime "$f")
      local s='*d0=array('"$d0"'.0,1.0,$time); time=d0+0.5;'
      has_var time_bnds "$f" || { has_dim bnds "$f" || s+=' defdim("bnds",2);'; s+=' time_bnds[$time,$bnds]=0.0;'; }
      s+=" time_bnds(0:$((nt - 1)),0)=d0; time_bnds(0:$((nt - 1)),1)=d0+1.0;"
      step ncap2 -O -h -s "$s" "$f" "$f.t" || return 1; mv "$f.t" "$f"
    fi
  done

  # finish a file: attributes, NetCDF-4 classic deflate 1, repack, name; then replace older files
  finish() {  # finish <file> <frequency> <cell_methods> <long_name> <first year> <last year>
    local g=$1 fq=$2 cm=$3 ln=$4 ya=$5 yb=$6 now hist old t1 t2 out
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # earlier lines for this table (a re-run) are replaced, not repeated
    old=$(hist_of "$g" | grep -v "found in table CORDEX-CMIP6_${fq}\.$" | sed '/^$/d')
    hist="${now};rewrote data to be consistent with $(gatt activity_id "$g") for variable ${v} found in table CORDEX-CMIP6_${fq}."
    [ -n "$old" ] && hist="${hist}"$'\n'"${old}"
    step ncatted -O -h -a "cell_methods,${v},o,c,${cm}" -a "long_name,${v},o,c,${ln}" \
         -a bounds,time,o,c,time_bnds -a cell_methods,time,d,, -a cell_methods,time_bnds,d,, \
         -a frequency,global,o,c,"$fq" -a variable_id,global,o,c,"$v" -a creation_date,global,o,c,"$now" \
         -a tracking_id,global,o,c,"hdl:21.14103/$(new_uuid)" -a history,global,o,c,"$hist" \
         -a NCO,global,d,, -a history_of_appended_files,global,d,, -a nco_openmp_thread_number,global,d,, "$g" || return 1
    step ncks -O -h -7 -L 1 "$g" "$g.k" || return 1; mv "$g.k" "$g"
    step ncatted -O -h -a NCO,global,d,, "$g" || return 1
    read -r t1 t2 <<< "$(times "$g" | awk "$AWK_CIVIL"' NR==1{a=$1} {b=$1} END{split(cfd(int(a+1e-6)),x," "); split(cfd(int(b+1e-6)),z," "); print x[1] x[2] x[3], z[1] z[2] z[3]}')"
    [ "$fq" = mon ] && { t1=${t1:0:6}; t2=${t2:0:6}; }
    out="${dir}/${prefix}_${fq}_${t1}-${t2}.nc"
    # repacked under its final name (ncrepack-cordex chunks by the _mon_ / _day_ in the name)
    mv "$g" "$wk/$(basename "$out")"; g="$wk/$(basename "$out")"
    if [ -n "$NCREPACK" ]; then
      "$NCREPACK" -o "$g" > "$wk/repack.log" 2>&1 || { cat "$wk/repack.log" >&2; return 1; }
    fi
    # older daily/monthly files of this variable inside these years go to superseded/
    local o oa ob
    while IFS= read -r o; do
      [ "$o" = "$out" ] && continue
      read -r oa ob <<< "$(name_years "$(basename "$o")")" || continue
      if [ "$oa" -ge "$ya" ] && [ "$ob" -le "$yb" ]; then
        mkdir -p "${dir}/superseded"; mv "$o" "${dir}/superseded/" && echo "  moved $(basename "$o") to superseded/"
      fi
    done < <(find "$dir" -maxdepth 1 -name "${v}_*_${fq}_*.nc")
    mv "$g" "$out" && echo "  wrote $(basename "$out")"
  }

  # daily files
  local files=()
  for blk in "${dblocks[@]+"${dblocks[@]}"}"; do
    read -r a b <<< "$blk"; files=()
    for ((y = a; y <= b; y++)); do [ -f "$wk/d_${y}.nc" ] && files+=("$wk/d_${y}.nc"); done
    [ ${#files[@]} -gt 0 ] || continue
    step ncrcat -O -h "${files[@]}" "$wk/day_out.nc" || return 1
    finish "$wk/day_out.nc" day "${T_DCM[$v]}" "${T_DLN[$v]}" "$a" "$b" || return 1
  done

  # monthly files: complete months of the daily values, mean/min/max/sum of the days
  local mo cnt ms me mfiles
  for blk in "${mblocks[@]+"${mblocks[@]}"}"; do
    read -r a b <<< "$blk"; mfiles=()
    for ((y = a; y <= b; y++)); do
      [ -f "$wk/d_${y}.nc" ] || continue
      case "$mm" in mean) op=avg ;; max) op=max ;; min) op=min ;; sum) op=ttl ;; esac
      # month, first and last record, number of days in it
      while read -r mo i0 i1 cnt; do
        ms=$(days_from "$y" "$mo" 1)
        if [ "$mo" = 12 ]; then me=$(days_from $((y + 1)) 1 1); else me=$(days_from "$y" $((10#$mo + 1)) 1); fi
        if [ "$cnt" -ne $(( me - ms )) ]; then
          echo "  ${y}-${mo}: only ${cnt} of $(( me - ms )) days — month left out"; continue
        fi
        g="$wk/m_${y}${mo}.nc"
        step ncra -O -h -d time,"$i0","$i1" -y "$op" "$wk/d_${y}.nc" "$g" || return 1
        step ncap2 -O -h -s "time(0)=$(( ms + me ))*0.5; time_bnds(0,0)=${ms}.0; time_bnds(0,1)=${me}.0;" "$g" "$g.t" || return 1
        mv "$g.t" "$g"; mfiles+=("$g")
      done < <(times "$wk/d_${y}.nc" | awk "$AWK_CIVIL"' {split(cfd(int($1+1e-6)),c," "); m=c[2]; if (!(m in s)) {s[m]=NR-1; o[++k]=m}; e[m]=NR-1; n[m]++}
                                      END{for (i=1;i<=k;i++) print o[i], s[o[i]], e[o[i]], n[o[i]]}')
    done
    [ ${#mfiles[@]} -gt 0 ] || { echo "  mon ${a}-${b}: no complete months"; continue; }
    step ncrcat -O -h "${mfiles[@]}" "$wk/mon_out.nc" || return 1
    finish "$wk/mon_out.nc" mon "${T_MCM[$v]}" "${T_MLN[$v]}" "$a" "$b" || return 1
  done
  return 0
}

# agg_one <OUTPUT_DIR> <variable>: agg_var in its own temporary folder ($wk)
agg_one() {
  local wk rc
  wk=$(mktemp -d "${WORK_BASE%/}/aggregate_${2}.XXXXXX") || return 1
  agg_var "$1" "$2"; rc=$?
  rm -rf "$wk"
  return $rc
}

#
#--- Every grid, every variable -------------------------------------
# Several variables at once with -j (each in its own process; log in the output).
#
nfail=0
for grid in "${GRIDS[@]}"; do
  dir="${OUTPUT_DIR[$grid]%/}"
  [ -d "$dir" ] || { echo "Grid ${grid}: ${dir} does not exist — skipped." >&2; continue; }
  if [ ${#VARS_ASKED[@]} -gt 0 ]; then
    vars=("${VARS_ASKED[@]}")
  else
    # every table variable with daily or sub-daily files (of its source variable)
    mapfile -t vars < <(
      find "$dir" -maxdepth 1 -name '*.nc' -printf '%f\n' | sed -nE 's/^([A-Za-z0-9]+)_.*_(1hr|3hr|6hr|day)_[0-9].*/\1/p' | sort -u > "${WORK_BASE%/}/.agg_have.$$"
      for v in "${!T_SRC[@]}"; do grep -qx "${T_SRC[$v]}" "${WORK_BASE%/}/.agg_have.$$" && echo "$v"; done | sort
      rm -f "${WORK_BASE%/}/.agg_have.$$")
  fi
  for v in "${vars[@]}"; do
    [ -n "${T_SRC[$v]:-}" ] || { echo "$v: not in ${TABLE} — skipped" >&2; nfail=$((nfail + 1)); }
  done
  echo "Grid ${grid}: ${dir}, years ${Y1}-${Y2}, ${FREQS}, ${#vars[@]} variables${NCREPACK:+, repacked}"
  running=0
  for v in "${vars[@]}"; do
    [ -n "${T_SRC[$v]:-}" ] || continue
    if [ "$NJOB" -le 1 ]; then
      agg_one "$dir" "$v" || { echo "FAILED $v" >&2; nfail=$((nfail + 1)); }
    else
      ( agg_one "$dir" "$v" > "${WORK_BASE%/}/aggregate_${grid}_${v}.log" 2>&1 \
          && echo "OK     $v" || { echo "FAILED $v (log: ${WORK_BASE%/}/aggregate_${grid}_${v}.log)"; exit 1; } ) &
      running=$((running + 1))
      if [ "$running" -ge "$NJOB" ]; then wait -n || nfail=$((nfail + 1)); running=$((running - 1)); fi
    fi
  done
  while [ "$running" -gt 0 ]; do wait -n || nfail=$((nfail + 1)); running=$((running - 1)); done
done
[ "$DRY" = 1 ] && echo "Dry run: nothing written."
[ "$nfail" -eq 0 ] || { echo "${nfail} variable(s) failed." >&2; exit 1; }
echo "$0 done."

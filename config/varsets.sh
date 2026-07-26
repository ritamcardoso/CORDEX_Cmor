#!/bin/bash
#
# config/varsets.sh
#
# Single source of truth for every "run_out_*" variant.
# To add/remove/change a variable set, edit ONLY this file — nothing else.
#
#----------------------------------------------------------------
# VARSETS[name] format
#
# One or more "groups", separated by ';'. Each group is:
#
#     <program-pattern>:<var1>,<var2>,...
#
# <program-pattern> is either:
#   - a literal program name (used as-is for every var in the group), or
#   - a name containing the literal string VAR, which gets substituted with
#     each variable in turn.
#
# Most sfc varsets are per-variable programs (RCM_sfc_VAR), but several are
# not — and *every* plev/zlev varset uses one fixed program across all its
# levels, keyed off the family name rather than the variable:
#
#   [out]      -> RCM_sfc_VAR            (one program per variable)
#   [cloud]    -> RCM_sfc_cloud          (one program, 4 variables)
#   [plev_ta]  -> RCM_plev_ta            (one program, 16 pressure levels)
#   [zlev_uava0] -> RCM_zlev_uava        (one program, 3 height levels)
#----------------------------------------------------------------

declare -A VARSETS=(
  [out]="RCM_sfc_VAR:tas,ts,th,hurs,huss,hfls,hfss,evspsbl,psl,ps,sfcWind,uas,vas,z0,zmla,od550aer"
  [soil]="RCM_sfc_VAR:mrfso,mrfsos,mrso,mrsos,mrro,mrros,tsl,mrsfl,mrsol"
  [rad]="RCM_sfc_rad:rsds,rlds,rsus,rlus,rldscs,rluscs,rlut,rlutcs,rsdscs,rsdsdir,rsdt,rsuscs,rsut,rsutcs"
  [snw]="RCM_sfc_VAR:prsn,snm,snc,snw,snd,siconca,pr,prc,sund"
  [cloud]="RCM_sfc_cloud:clh,clm,cll,clt"
  [wxtrm]="RCM_sfc_xtrm:tasmax,tasmin,sfcWindmax,prcmax,prncmax"
  [tau]="RCM_sfc_VAR:tauu,tauv"
  [wpth]="RCM_sfc_VAR:clivi,clwvi,prw"
  [plev_wa]="RCM_plev_wa:wa1000,wa925,wa850,wa750,wa700,wa600,wa500,wa400,wa300,wa250,wa200,wa150,wa100,wa70,wa50,wa30"
  [plev_zg]="RCM_plev_zg:zg1000,zg925,zg850,zg750,zg700,zg600,zg500,zg400,zg300,zg250,zg200,zg150,zg100,zg70,zg50,zg30"
  [plev_uava]="RCM_plev_uava:va1000,va925,va850,va750,va700,va600,va500,va400,va300,va250,va200,va150,va100,va70,va50,va30"
  [plev_hus]="RCM_plev_hus:hus1000,hus925,hus850,hus750,hus700,hus600,hus500,hus400,hus300,hus250,hus200,hus150,hus100,hus70,hus50,hus30"
  [plev_ta]="RCM_plev_ta:ta1000,ta925,ta850,ta750,ta700,ta600,ta500,ta400,ta300,ta250,ta200,ta150,ta100,ta70,ta50,ta30"
  [zlev_hus]="RCM_zlev_hus:hus50m"
  [zlev_ta]="RCM_zlev_ta:ta50m"
  [zlev_uava0]="RCM_zlev_uava:va50m,va150m,va100m"
  [zlev_uava1]="RCM_zlev_uava:va200m,va250m,va300m"
  #
  # Archive-only companions — NOT for processing (not in ORDER/NEXT/TIME,
  # so run_out_generic.sh never runs these as their own job). They exist
  # purely so run_cp_generic.sh can archive the "u" files alongside the
  # "v" files that plev_uava/zlev_uava0/zlev_uava1 actually produce — see
  # CP_EXTRA[] below. Var lists are otherwise identical to the deprecated
  # entries further down.
  [plev_ua]="RCM_plev_ua:ua1000,ua925,ua850,ua750,ua700,ua600,ua500,ua400,ua300,ua250,ua200,ua150,ua100,ua70,ua50,ua30"
  [zlev_ua0]="RCM_zlev_ua:ua50m,ua150m,ua100m"
  [zlev_ua1]="RCM_zlev_ua:ua200m,ua250m,ua300m"
)
# formerly [acum]: pr/prc/sund moved into [snw]; the radiation-only group
# was renamed [rad] and no longer carries a second per-variable group.
#
# DEPRECATED — old/superseded versions, disabled on purpose. Left here for
# reference only; not in VARSETS/TIME/NEXT, so run_out_generic.sh will
# reject them if ever called by name. Re-enable by moving a line back up
# into VARSETS (and re-adding matching TIME/NEXT entries) if ever needed.
# (plev_ua/zlev_ua0/zlev_ua1 were already re-enabled above, archive-only —
# see the comment there.)
#
#   [plev_va]="RCM_plev_va:va1000,va925,va850,va750,va700,va600,va500,va400,va300,va250,va200,va150,va100,va70,va50,va30"
#   [zlev_va0]="RCM_zlev_va:va50m,va150m,va100m"
#   [zlev_va1]="RCM_zlev_va:va200m,va250m,va300m"
#
# run_out_fx.sh (orog, sftlaf, sftlf, sfturf, sftgif -> RCM_fx_<var>) is
# intentionally NOT included below: those RCM_fx_*.f90 sources don't exist
# in f90_src/ yet, so wiring it up here would just fail at compile time.
# Add an [fx]="RCM_fx_VAR:orog,sftlaf,sftlf,sfturf,sftgif" entry once they do.

declare -A TIME=(
  [out]="18:00:00"
  [soil]="12:00:00"
  [rad]="12:00:00"      # was 20:00:00 for acum's two groups combined; now one group, re-check
  [snw]="12:00:00"      # bumped from 08:00:00: snw now also carries pr/prc/sund, re-check
  [cloud]="06:00:00"
  [wxtrm]="08:00:00"
  [tau]="06:00:00"
  [wpth]="06:00:00"
  [plev_wa]="18:00:00"
  [plev_zg]="14:00:00"
  [plev_uava]="14:00:00"
  [plev_hus]="14:00:00"
  [plev_ta]="14:00:00"
  [zlev_hus]="04:00:00"
  [zlev_ta]="04:00:00"
  [zlev_uava0]="06:00:00"
  [zlev_uava1]="06:00:00"
)
# out/plev_ta walltimes confirmed against the live scripts; the rest are
# carried over/estimated — worth a check, especially [rad] and [snw] above
# which just changed what they cover.

#----------------------------------------------------------------
# CP_TIME[name] — walltime for this varset's archive/copy job
# (run_cp_generic.sh). Only [out] is confirmed against the live
# run_cp_out.sh (20:00:00); everything else falls back to DEFAULT_CP_TIME
# until you've checked how long each one actually takes.
#----------------------------------------------------------------
DEFAULT_CP_TIME="04:00:00"
declare -A CP_TIME=(
  [out]="20:00:00"
)

#----------------------------------------------------------------
# CP_EXTRA[name] — an additional varset to archive alongside this one.
# plev_uava/zlev_uava0/zlev_uava1 only ever *process* the v-component
# (their VARSETS[] entry lists va* variables), but the underlying programs
# produce matching u-component files too. So archiving needs both: the
# varset itself (v) plus its CP_EXTRA companion (u, from the reactivated
# archive-only plev_ua/zlev_ua0/zlev_ua1 entries above). run_out_generic.sh
# submits run_cp_generic.sh twice when CP_EXTRA[$VARSET] is set.
#----------------------------------------------------------------
declare -A CP_EXTRA=(
  [plev_uava]="plev_ua"
  [zlev_uava0]="zlev_ua0"
  [zlev_uava1]="zlev_ua1"
)

#----------------------------------------------------------------
# ADVANCE_YEAR[name] — whether this varset's own script increments
# yeari/yearf by 1 before resubmitting. Only about half of them do — the
# other half in each pair/chain link keeps the year unchanged and relies on
# the *next* link to advance it, so a 2-cycle advances one year per full
# round-trip, not per hop.
#----------------------------------------------------------------
declare -A ADVANCE_YEAR=(
  [soil]=1        [wpth]=1        [wxtrm]=1
  [snw]=1
  [plev_zg]=1     [plev_uava]=1
  [plev_hus]=1    [plev_ta]=1
  [zlev_uava0]=1  [zlev_uava1]=1
  # out, rad, cloud, tau, plev_wa, zlev_hus, zlev_ta: unset -> 0 (no advance)
)

#----------------------------------------------------------------
# NEXT[name] — what a varset's own year-loop resubmits when it finishes.
# Mostly 2-cycles (A resubmits B, B resubmits A) or self-loops (A
# resubmits itself).
#----------------------------------------------------------------
declare -A NEXT=(
  [out]="soil"          [soil]="out"
  [rad]="snw"           [snw]="rad"
  [cloud]="wxtrm"       [wxtrm]="cloud"
  [tau]="wpth"          [wpth]="tau"
  [plev_wa]="plev_zg"   [plev_zg]="plev_wa"
  [plev_uava]="plev_uava"
  [zlev_uava0]="zlev_uava0"
  [zlev_uava1]="zlev_uava1"
  [zlev_hus]="plev_hus" [plev_hus]="zlev_hus"   # 2-cycle
  [zlev_ta]="plev_ta"   [plev_ta]="zlev_ta"     # 2-cycle
)

# The set (and order) run_Analysis_v2.sh submits directly.
ORDER=(out rad cloud plev_wa plev_uava zlev_hus zlev_ta zlev_uava0 zlev_uava1 tau)

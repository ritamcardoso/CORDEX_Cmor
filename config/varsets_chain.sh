#!/bin/bash
#
# Varsets — chained streams layout.
# Active as config/varsets.sh (the only file the scripts read); saved copy in
# config/varsets_chain.sh. See config/README.md.
#----------------------------------------------------------------

#
#--- VARSETS: name -> "PROGRAM:var1,var2;PROGRAM:var3" ------
# Each varset: one or more groups of a program pattern and its variables.
# VAR in a pattern is replaced by each variable (RCM_sfc_VAR -> RCM_sfc_tas).
#
declare -A VARSETS=(
  [out1]="RCM_sfc_VAR:tas,ts,th,hurs,huss,hfls,hfss,evspsbl,psl,zmla,od550aer,uas,vas"
  [out2]="RCM_sfc_VAR:ps,sfcWind,z0,tauu,tauv,evspsblpot"
  [soil]="RCM_sfc_VAR:mrfso,mrfsos,mrso,mrsos,mrro,mrros,tsl,mrsfl,mrsol,mrsofc"
  [rad]="RCM_sfc_rad:rsds,rlds,rsus,rlus,rldscs,rluscs,rlut,rlutcs,rsdscs,rsdsdir,rsdt,rsuscs,rsut,rsutcs"
  [snw]="RCM_sfc_VAR:prsn,snm,snc,snw,snd,siconca,pr,prc,sund"
  [cloud1]="RCM_sfc_cloud:clh,clm"
  [cloud2]="RCM_sfc_cloud:cll,clt"
  [wxtrm]="RCM_sfc_xtrm:tasmax,tasmin,sfcWindmax,prcmax,prncmax"
  [wpth1]="RCM_sfc_VAR:clivi"
  [wpth2]="RCM_sfc_VAR:prw"
  [wpth3]="RCM_sfc_VAR:clwvi"
  [plev_wa]="RCM_plev_wa:wa1000,wa925,wa850,wa750,wa700,wa600,wa500,wa400,wa300,wa250,wa200,wa150,wa100,wa70,wa50,wa30"
  [plev_zg]="RCM_plev_zg:zg1000,zg925,zg850,zg750,zg700,zg600,zg500,zg400,zg300,zg250,zg200,zg150,zg100,zg70,zg50,zg30"
  [plev_uava]="RCM_plev_uava:va1000,va925,va850,va750,va700,va600,va500,va400,va300,va250,va200,va150,va100,va70,va50,va30"
  [plev_hus]="RCM_plev_hus:hus1000,hus925,hus850,hus750,hus700,hus600,hus500,hus400,hus300,hus250,hus200,hus150,hus100,hus70,hus50,hus30"
  [plev_ta]="RCM_plev_ta:ta1000,ta925,ta850,ta750,ta700,ta600,ta500,ta400,ta300,ta250,ta200,ta150,ta100,ta70,ta50,ta30"
  [zlev_hus]="RCM_zlev_hus:hus50m"
  [zlev_ta]="RCM_zlev_ta:ta50m"
  [zlev_uava0]="RCM_zlev_uava:va50m,va100m,va150m"
  [zlev_uava1]="RCM_zlev_uava:va200m,va250m,va300m"
  [fx]="RCM_fx_VAR:orog,sftlaf,sftlf,sfturf,sftgif;RCM_fx_landuse:treeFrac,shrubFrac,grassFrac,cropFrac,baresoilFrac,urbanFrac,cnc,luindex"
  [testex]="RCM_sfc_xtrm:tasmax,tasmin,sfcWindmax,prcmax,prncmax"
  [teste]="RCM_sfc_rad:rsds"
  # Manual runs only (not in any stream)
  [cloud]="RCM_sfc_cloud:clh,clm,cll,clt"
  [tau]="RCM_sfc_VAR:tauu,tauv"
  [zlev_va0]="RCM_zlev_va:va50m,va100m,va150m"
  [zlev_va1]="RCM_zlev_va:va200m,va250m,va300m"
  # Archive-only (CP_EXTRA companions, never processed)
  [plev_ua]="RCM_plev_ua:ua1000,ua925,ua850,ua750,ua700,ua600,ua500,ua400,ua300,ua250,ua200,ua150,ua100,ua70,ua50,ua30"
  [zlev_ua0]="RCM_zlev_ua:ua100m,ua150m,ua50m"
  [zlev_ua1]="RCM_zlev_ua:ua300m,ua250m,ua200m"
  # FPS-URB-RCC urban variables (WRF BEP+BEM output; fpsurb only, so not in ORDER):
  # run with ./run.sh fpsurb <first year> <last year> urban
  [urban]="RCM_sfc_VAR:tasroof;RCM_sfc_urb:taspav,tasgree,tasblue,tascan,hurscan,husscan,sfcWindcan,tsskin,tspav,tsroof,tsgree,tsblue"
  # Noah-MP land-surface variables (LUCAS; needs LAI, FVEG, ALBEDO, EDIR/ECAN/ETRAN
  # in wrfout), not in ORDER: run with ./run.sh lucas <first year> <last year> lsm
  [lsm]="RCM_sfc_lsmflx:evspsblsoi,evspsblveg,tran;RCM_sfc_lsm:lai,vegFrac,alb"
  # Hourly land-cover fractions for land-use change runs (LUCAS), not in ORDER:
  # run with ./run.sh lucas <first year> <last year> landuse
  [landuse]="RCM_sfc_landuse:treeFrac,shrubFrac,grassFrac,cropFrac,baresoilFrac,urbanFrac,cnc,luindex"
)

#
#--- TIME: processing job --time (one model year) -------------
# Walltime of the processing job, used by submit.sh as --time.
# Values are for one model year; config/README.md gives the basis of each.
#
declare -A TIME=(
  [out1]="14:00:00"
  [out2]="10:00:00"
  [soil]="12:00:00"
  [rad]="18:00:00"
  [snw]="12:00:00"
  [cloud1]="17:00:00"
  [cloud2]="17:00:00"
  [wxtrm]="08:00:00"
  [wpth1]="13:00:00"
  [wpth2]="10:00:00"
  [wpth3]="13:00:00"
  [plev_wa]="22:00:00"
  [plev_zg]="22:00:00"
  [plev_uava]="28:00:00"
  [plev_hus]="18:00:00"
  [plev_ta]="18:00:00"
  [zlev_hus]="10:00:00"
  [zlev_ta]="10:00:00"
  [zlev_uava0]="25:00:00"
  [zlev_uava1]="25:00:00"
  [fx]="01:00:00"
  [testex]="08:00:00"
  [teste]="08:00:00"
  # Manual runs only
  [cloud]="28:00:00"
  [tau]="16:00:00"
  [zlev_va0]="19:00:00"
  [zlev_va1]="19:00:00"
  [urban]="14:00:00"
  [lsm]="08:00:00"
  [landuse]="10:00:00"
)

#
#--- CP_TIME: archive job --time (default DEFAULT_CP_TIME) ----
# Walltime of the archive job (run_cp_generic.sh), used by submit.sh.
# Varsets not listed use DEFAULT_CP_TIME.
#
DEFAULT_CP_TIME="20:00:00"
declare -A CP_TIME=(
  [out1]="20:00:00"
  [out2]="20:00:00"
)

#
#--- MEM: processing job --mem (default DEFAULT_MEM) ----------
# Memory of the processing job, used by submit.sh as --mem.
# Only varsets needing more than DEFAULT_MEM are listed.
#
DEFAULT_MEM="8G"
declare -A MEM=(
  [zlev_uava0]="16G"
  [zlev_uava1]="16G"
  [soil]="16G"
)

#
#--- CP_EXTRA: extra varset archived with this one ------------
# Second varset archived after this one: the ua* files that the
# uava programs write alongside the va* files they are named for.
#
declare -A CP_EXTRA=(
  [plev_uava]="plev_ua"
  [zlev_uava0]="zlev_ua0"
  [zlev_uava1]="zlev_ua1"
)

#
#--- ADVANCE_YEAR: the link that advances the year ------------
# 1 = this link moves on to the next year(s) when it resubmits.
# Exactly one link per stream advances; the stream stops after year_lim.
#
declare -A ADVANCE_YEAR=(
  [wxtrm]=1        [zlev_uava0]=1  [zlev_uava1]=1
  [wpth1]=1        [wpth3]=1       [snw]=1
  [wpth2]=1        [out1]=1        [zlev_ta]=1
  [out2]=1
  [testex]=1       [teste]=1
  [urban]=1
  [lsm]=1
  [landuse]=1
)

#
#--- NEXT: varset submitted when this one finishes ------------
# Varset that run_out_generic.sh submits when this one finishes.
# Together these form the streams; a varset pointing to itself loops on itself.
#
declare -A NEXT=(
  [plev_uava]="wxtrm"   [wxtrm]="plev_uava"
  [zlev_uava0]="zlev_uava0"
  [zlev_uava1]="zlev_uava1"
  [cloud1]="wpth1"      [wpth1]="cloud1"
  [cloud2]="wpth3"      [wpth3]="cloud2"
  [plev_zg]="snw"       [snw]="plev_zg"
  [plev_ta]="wpth2"     [wpth2]="plev_ta"
  [rad]="out1"          [out1]="rad"
  [plev_wa]="zlev_hus"  [zlev_hus]="zlev_ta"  [zlev_ta]="plev_wa"
  [plev_hus]="soil"     [soil]="out2"         [out2]="plev_hus"
#  [testex]="testex"
  [teste]="teste"
  [urban]="urban"
  [lsm]="lsm"
  [landuse]="landuse"
)

#
#--- ORDER: first link of each stream (run_analysis.sh) -------
# Varsets run_analysis.sh submits, one per stream; the rest of each
# stream follows through NEXT.
#
ORDER=(plev_uava zlev_uava0 zlev_uava1 cloud1 cloud2 plev_zg plev_ta rad plev_wa plev_hus)

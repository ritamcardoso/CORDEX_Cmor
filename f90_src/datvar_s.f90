module datvar_s
implicit none

! =====================================================================
! --- Module Grid & Time Array Dimensions & Constants ---
! =====================================================================
integer, parameter :: nseason = 4
integer, parameter :: tmonths = 12

! --- Physical & Environmental Constants ---
real, parameter :: earth_radius      = 6370000.0     ! WRF sphere radius (m)
real, parameter :: epsilon           = 0.6220         
real, parameter :: Rd                = 287.04
real, parameter :: g                 = 9.81
real, parameter :: gamma             = 0.0065
real, parameter :: pconst            = 1.0e5
real, parameter :: cp                = 1004.0
real, parameter :: rcp               = 0.285714
real, parameter :: missing_value     = -1.0e20         
real, parameter :: huge_val          = 1.0e20
real, parameter :: min_val           = 1.0e-7

! --- Fixed Calendar Data Arrays & Parameters ---
integer, dimension(tmonths) :: days
integer, dimension(tmonths), parameter :: days1   = [31,28,31,30,31,30,31,31,30,31,30,31]
integer, dimension(tmonths), parameter :: days2   = [31,29,31,30,31,30,31,31,30,31,30,31]
integer, dimension(nseason), parameter :: sedays1 = [90,92,92,91]
integer, dimension(nseason), parameter :: sedays2 = [91,92,92,91]
integer, dimension(nseason)            :: sedays
integer, dimension(nseason)            :: sedays2_var  ! Renamed slightly to avoid conflict with parameter sedays2

! Constant String Name Labels
character(len=3), dimension(nseason), parameter :: snames = ['Win','Spr','Sum','Aut']
character(len=3), dimension(tmonths), parameter :: aname  = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

character(len=8), dimension(4), parameter :: rad_Jm = ['ACSWDNB ', 'ACSWUPB ', 'ACLWDNB ', 'ACLWUPB ']
real, dimension(4), parameter :: rad_sign = [1., -1., 1., -1.]

! =====================================================================
! --- 1. Dimensions and Grid Arrays ---
! =====================================================================
integer :: nlon, nlat, nz, nzt, nsoil
integer :: latid, lonid, timeid, levid, timedim, latdim, londim, levdim, level
integer :: nlon_u, nlat_v

real :: rhours, factor, heightl, presl, pres, p_top
integer :: wp_step     ! hours between the output times of the 3-hourly/6-hourly programs (grid ini; default 6)
real, dimension(1) :: height, pressure
real, dimension(2) :: pressure_bounds
real, dimension(:),   allocatable :: rlon, rlat
real, dimension(:,:), allocatable :: lon, lat, tlon, tlat, cosalp, sinalp, landmask, urb_frac, luindex
! land-use table of the geo_em file (MMINLU) and whether it is USGS (else MODIS), from read_geog
character(len=80) :: lu_table
logical :: lu_usgs
! cell corners (4 per cell, counterclockwise), from the geo_em corner points
real(kind=8), dimension(:,:,:), allocatable :: vlon, vlat

! --- Map projection of the output grid (set per grid in &cordex_config) ---
! projection: CF grid_mapping_name, 'rotated_latitude_longitude' or
! 'lambert_conformal_conic'; it also names the grid-mapping variable.
character(len=40) :: projection
real :: pole_lat, pole_lon                     ! rotated pole (grid_north_pole_*)
real :: truelat1, truelat2, stand_lon, cen_lat ! Lambert (standard parallels, central meridian, origin)
real :: false_easting, false_northing          ! Lambert, metres

! Scalar area-type coordinate for sftlaf/sfturf (set in their header)
character(len=40) :: area_type
integer :: outstep   ! header: output step in hours (1, 3, 6 or 24 = daily); 0 = wp_step of the grid ini
integer :: ostep     ! the step used: outstep, or wp_step for outstep = 0 (-1: no outstep in the header)

real, dimension(4), parameter :: sdepth = [0.1, 0.3, 0.6, 1.0]
real, dimension(2,4) :: sdepth_bounds
! Number of soil layers with roots per land-use class (NROOT of WRF VEGPARM.TBL and
! Noah-MP NoahmpTable.TBL), MODIFIED_IGBP_MODIS_NOAH (1-20) and USGS (1-27): RCM_fx_rootd
integer, dimension(20), parameter :: nroot_modis = [4,4,4,4,4,3,3,3,3,3,2,3,1,3,1,1,0,3,3,2]
integer, dimension(27), parameter :: nroot_usgs  = [1,3,3,3,3,3,3,3,3,3,4,4,4,4,4,0,2,2,1,3,3,3,2,1,1,0,0]

! =====================================================================
! --- 2. Date, Time, and Offset Control ---
! =====================================================================
integer :: yeari, iniyear, yearf, nmonths, imonth, iday, ihour, pyear
integer :: xoffset, yoffset, ndays, nyr
integer :: ish, isd, is3, is6, issh, iss3, iss6, issd, isdm, it, iz, isx, isy, iyl
integer :: loop_year
integer :: year, month, day, hour, dhour, nhours, mydays, yhours
integer :: ntime, ntime3, ntime6
! --- Variable calendar (programs of f90_src_varcalendar) ---
! sim_start, sim_end: first and last wrfout file of the simulation, 'YYYY-MM-DD_HH' (UTC),
! set in the grid ini. Each year yeari..yearf of a run is one chunk: the part of that year
! inside the simulation period (time_chunk, set_time_step in shared_subs_v2.f90).
character(len=13) :: sim_start = '', sim_end = ''
integer :: t_sim0, t_sim1          ! sim_start, sim_end in hours since iniyear-01-01 00 UTC
integer :: t_ch0, t_ch1            ! first and last time step of the chunk (hours since iniyear)
integer :: vc_step                 ! hours between the files read
integer :: vc_nfiles, vc_ifl       ! files read in the chunk, and the current one
integer :: vc_year                 ! year of the chunk (the loop over yeari..yearf)
logical :: vc_interval             ! .true.: interval values from two files (accumulated, means)
logical :: rs_complete = .false.   ! resample_time: drop windows with missing time steps
integer :: vc_d0, vc_nd            ! daily programs: first day (hours since iniyear), days
integer :: vc_k, vc_kf, vc_rec, vc_tf ! ... day, first day of the month, record, file start

! =====================================================================
! --- 3. Scientific Data Arrays ---
! =====================================================================
! Integer Arrays
integer :: ir
integer, dimension(8) :: values
integer, dimension(:,:), allocatable :: bdtime, outvar_a

! Real Scalars 
real :: tv, tc, slope
real :: t2_C, q2_m, psf_kPa, wind2, Rn_MJ, ghf, vpres, es_kPa, gam, ET0   ! RCM_sfc_evspsblpot (slope above)
real(kind=8) :: es_pa, des_pa                                            ! RCM_sfc_evspsblpot: es (Pa) and d es / dT (Pa K-1), es_wexler_dt
real :: dx_geo, dy_geo                                                      ! RCM_fx_areacella
real :: vo_dx, vo_dy, vo_dudy, vo_dvdx                                     ! RCM_plev_vortmen: grid spacing (m), derivatives
integer :: vo_hw, vo_he, vo_hs, vo_hn, vo_nxh, vo_nyh, vo_nxf, vo_nyf     ! RCM_plev_vortmen: halo (0/1) W E S N, sizes with halo, full grid
integer :: vo_i, vo_j, vo_ip, vo_im, vo_jp, vo_jm, vo_dimid                ! RCM_plev_vortmen: indices with halo and neighbours, dimension id
integer :: plev_kg, plev_it, plev_steps, plev_scan              ! plev_map: first guess, iterations, steps walked, full scans
integer :: plev_k1, plev_k2, plev_nk          ! plev_map_s: the model levels plev_interp_s needs (all points), and their number
logical :: plev_sfc                           ! plev_map_s: some point is between the surface (level 0) and level 1
real :: ws10, wsp, dws, tke_int, vpt_int                                    ! RCM_sfc_wsgsmax
integer :: nlevs, ilev                                                      ! RCM_sfc_wsgsmax (Brasseur)
logical :: fx_exists                                                        ! fx programs: output already there
! RCM_sfc_cape: surface parcel of one column (double precision)
real(kind=8) :: p_par, t_par, r_par, th_par, the_par, z_lcl, t_lcl, p_lcl
real(kind=8) :: t_lift, q_lift, z_lift, tv_lift, t_env, q_env, tv_env, fac1, fac2, fden
real(kind=8) :: ben_min, t500, te500
integer :: kk, klcl, kel, klfc, kmax
logical :: lcl_in, found_el
real :: wp_v, wp_i, wp_c, dpk                                             ! RCM_sfc_wpth: column sums, layer thickness
integer :: nv, ncomb                                                      ! RCM_sfc_wpth, RCM_sfc_clouds: variable index, number of variables
logical :: gust_b01                                                         ! RCM_sfc_wsgsmax: QKE in wrfout -> Brasseur

! Real 1D Allocatable Arrays
real, dimension(:), allocatable :: ttime, ttime3, ttime6, ttimed, ttimem, ttimes
real, dimension(:), allocatable :: vpt, zcol, dzcol, dvpt   ! one column (RCM_sfc_wsgsmax, Brasseur)
real(kind=8), dimension(:), allocatable :: buoy_c, zrel_c, ben_c   ! one column, with inserted levels (RCM_sfc_cape)

! Real 2D Allocatable Arrays
real, dimension(:,:), allocatable :: sftlf, hgt, runsf, pblh
real, dimension(:,:), allocatable :: msftx, msfty     ! map scale factors (RCM_fx_areacella)
real, dimension(:,:), allocatable :: lsm_a, lsm_b, lsm_c   ! further Noah-MP 2-D fields (RCM_sfc_interception, RCM_sfc_cVeg)
real, dimension(:,:), allocatable :: vo_mu, vo_mv, vo_mt  ! map factors at U, V and mass points, with halo (RCM_plev_vortmen)
real, dimension(:,:), allocatable :: wrfv2D, i_wrfv2D, outvar, outvar_i
real, dimension(:,:), allocatable :: u_s, v_s, wind10, ust, t2, q2, uas, vas, ro, psf
real, dimension(:,:), allocatable :: t2_i, q2_i, psf_i, wind10_i
real, dimension(:,:), allocatable :: rainc, rainnc, i_rainc, i_rainnc, rainsh
real, dimension(:,:), allocatable :: outvar_u, outvar_v
real, dimension(:,:), allocatable :: t_l, pres_s, phi_s  
real, dimension(:,:), allocatable :: mr, mr_sat, e_sfc, esat

real(kind=8), dimension(:,:), allocatable :: Rn, Rn_i

! Real 3D Allocatable Arrays
real, dimension(:,:,:), allocatable :: outvar_h, wrfv3D
real, dimension(:,:,:), allocatable :: cin_h, li_h, lcl_h   ! RCM_sfc_cape (cape in outvar_h)
real, dimension(:,:,:), allocatable :: outvar_n, outvar_n_i  ! one time step of several variables (RCM_sfc_wpth, RCM_sfc_clouds)
real, dimension(:,:,:), allocatable :: outvar_r          ! resample_time: the output at the step of outstep
real, dimension(:), allocatable :: ttime_r                 ! ... its times (hours since iniyear)
integer, dimension(:,:), allocatable :: bdtime_r          ! ... its time bounds
integer :: nt_r                                           ! ... its number of time steps
integer, dimension(:,:), allocatable :: plev_k          ! plev_map: model level k with p(k) >= presl > p(k+1), 0 = missing;
                                                        ! plev_map_s: k = 0..nz-1 (0: surface), -1 below the surface, -2 above the top
real, dimension(:,:), allocatable :: plev_w             ! plev_map: log(p) weight of level k+1
real, dimension(:,:,:), allocatable :: lc_frac          ! LANDUSEF of every category, % (RCM_fx_landCoverFrac)
real, dimension(:), allocatable :: sl_dz                  ! soil layer thicknesses DZS, m (RCM_fx_slthick)
integer :: lc_ncat                                        ! number of land-use categories (RCM_fx_landCoverFrac)
character(len=48), dimension(:), allocatable :: lc_names ! names of the land-use categories (RCM_fx_landCoverFrac)
character(len=80) :: lc_scheme                            ! MMINLU of the wrfout file (RCM_fx_landCoverFrac)
integer :: lc_lcz1, lc_nnamed, lc_dimid                  ! first LCZ class, named classes, land_cat dimension
logical :: lc_modis                                       ! MODIS (else USGS) land-use table
! names of the land-use categories, MODIFIED_IGBP_MODIS_NOAH and USGS (RCM_fx_landCoverFrac)
character(len=48), dimension(21), parameter :: lc_md_names = [character(len=48) :: &
  'evergreen needleleaf forest', 'evergreen broadleaf forest', 'deciduous needleleaf forest', &
  'deciduous broadleaf forest', 'mixed forest', 'closed shrubland', 'open shrubland', &
  'woody savanna', 'savanna', 'grassland', 'permanent wetland', 'cropland', 'urban', &
  'cropland/natural vegetation mosaic', 'snow and ice', 'barren', 'water', 'wooded tundra', &
  'mixed tundra', 'barren tundra', 'lakes']
character(len=48), dimension(24), parameter :: lc_us_names = [character(len=48) :: &
  'urban', 'dryland cropland and pasture', 'irrigated cropland and pasture', &
  'mixed dryland/irrigated cropland and pasture', 'cropland/grassland mosaic', &
  'cropland/woodland mosaic', 'grassland', 'shrubland', 'mixed shrubland/grassland', 'savanna', &
  'deciduous broadleaf forest', 'deciduous needleleaf forest', 'evergreen broadleaf forest', &
  'evergreen needleleaf forest', 'mixed forest', 'water', 'herbaceous wetland', 'wooded wetland', &
  'barren or sparsely vegetated', 'herbaceous tundra', 'wooded tundra', 'mixed tundra', &
  'bare ground tundra', 'snow or ice']
real, dimension(:,:,:), allocatable :: p, pb, press, p_iface, phb, ph, phi, zhgt, ua, va, u, v, w, t
real, dimension(:,:,:), allocatable :: qv,qc, qi, qr, qs, smois, tke
real, dimension(:,:,:), allocatable :: outvar_3, outvar_6, outvar_d, outvar_m, outvar_d_max
real, dimension(:,:,:), allocatable :: outvar_h_u, outvar_h_v
real, dimension(:,:,:), allocatable :: wrfv3D_u, wrfv3D_v

! Real 4D Allocatable Arrays
real, dimension(:,:,:,:), allocatable :: outvar_h_4d  

! NetCDF File/Variable ID Tracking
integer :: ncid, varid, status
integer :: i, inperr, ichlef

! =====================================================================
! --- 4. Character Strings and Metadata ---
! =====================================================================
character(len=2) :: ahouri, adayi, amonthi, ahourf, adayf, amonthf
character(len=2) :: ahour, aday, amonth, aday_pad, aiday, aimonth, dom, mm, dd, hh, mn, ss
character(len=4) :: ayear, ayearf, ayeari, aiyear, yyyy, ayearini
character(len=5) :: zone
character(len=8) :: date
character(len=10) :: times

character(len=20)  :: vaid, varname, vunts, vunits
character(len=25)  :: wrfile, wrffile, geo, geog, wrfvar, wrfvarname, subrname, subname, fname, iwrfvar
character(len=100) :: longname, standardname, cellmethods, timeunits, frequency, experiment, dexperiment, creationdate
character(len=100) :: lname, stname, cmethods, tunts, freq, exper, dexper, cdate, experiment_id, experi

! =====================================================================
! --- 5. File Paths and Directories ---
! =====================================================================
character(len=400) :: infile, filename, outfile, outdom, fnameout, fnameout_u, fnameout_v
character(len=400) :: dir_in, dir_out, gfile, geofile, aexp, adexp

! --- Global Metadata Strings ---
character(len=100)  :: conventions, activity_id, contact, cordex_domain
character(len=100)  :: domain_name, domain_id, driving_inst_id, driving_source_id
character(len=100)  :: driving_variant, further_info_url, grid_desc
character(len=100)  :: institution, institution_id, label, label_ext
character(len=100)  :: license, mip_era, product, project_id, release_year
character(len=100)  :: source_id, source_type, version_real, sim_start_date
character(len=500)  :: source_desc
character(len=1000) :: driving_source
character(len=300)  :: title, references   ! optional in the global ini (title: built if empty)

! --- Global Metadata Numerics ---
real    :: dx_val, dy_val
integer :: we_dim, sn_dim, bt_dim

! -------------------------------------------------------------
! Namelist Group Definitions
! -------------------------------------------------------------
namelist /cordex_config/ &
    yeari, yearf, iniyear, nmonths, imonth, iday, ihour, sim_start, sim_end, &
    nz, nsoil, nlon, nlat, xoffset, yoffset, p_top, &
    dir_in, dir_out, geog, wrffile, wrfile, dom, outdom, &
    wrfvar, vaid, height, pres, vunits, vunts, &
    lname, stname, cmethods, factor, &
    projection, pole_lat, pole_lon, truelat1, truelat2, stand_lon, cen_lat, &
    false_easting, false_northing, area_type, wp_step, outstep

namelist /global_metadata/ &
    conventions, activity_id, contact, cordex_domain, domain_name, &
    domain_id, driving_inst_id, driving_source_id, driving_variant, &
    experiment_id, experiment, further_info_url, grid_desc, institution, &
    institution_id, label, label_ext, license, mip_era, product, &
    project_id, release_year, source_desc, source_id, source_type, &
    version_real, sim_start_date, dx_val, dy_val, we_dim, sn_dim, &
    bt_dim, driving_source, title, references

contains

pure function pad_int(i, width) result(str)
    integer, intent(in) :: i, width
    character(len=10) :: str
    write(str, '(I0)') i
    str = repeat('0', width - len_trim(str)) // trim(str)
end function pad_int

end module datvar_s

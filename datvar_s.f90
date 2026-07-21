module datvar_s
implicit none

! =====================================================================
! --- Module Grid & Time Array Dimensions & Constants ---
! =====================================================================
integer, parameter :: nseason = 4
integer, parameter :: tmonths = 12

! --- Physical & Environmental Constants ---
real, parameter :: earth_radius      = 6372795.0    
real, parameter :: epsilon           = 0.6220         
real, parameter :: Rd                = 287.04
real, parameter :: g                 = 9.81
real, parameter :: gamma             = 0.0065
real, parameter :: pconst            = 1.0e5
real, parameter :: cp                = 1004.0
real, parameter :: rcp               = 0.285714
real, parameter :: missing_value     = 1.e20         
real, parameter :: huge_val          = 1.e20         

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

! =====================================================================
! --- 1. Dimensions and Grid Arrays ---
! =====================================================================
integer :: nlon, nlat, nz, nzt, nsoil
integer :: latid, lonid, timeid, levid, timedim, latdim, londim, levdim, level
integer :: nlon_u, nlat_v

real :: rhours, factor, heightl, presl, pres
real, dimension(1) :: height, pressure
real, dimension(2) :: pressure_bounds
real, dimension(:),   allocatable :: rlon, rlat
real, dimension(:,:), allocatable :: lon, lat, tlon, tlat, cosalp, sinalp, landmask

real, dimension(4), parameter :: sdepth = [0.1, 0.3, 0.6, 1.0]
real, dimension(2,4) :: sdepth_bounds

! =====================================================================
! --- 2. Date, Time, and Offset Control ---
! =====================================================================
integer :: yeari, iniyear, yearf, nmonths, imonth, iday, ihour, pyear
integer :: xoffset, yoffset, ndays, nyr
integer :: ish, isd, is3, is6, issh, iss3, iss6, issd, isdm, it, iz, isx, isy, iyl
integer :: loop_year
integer :: year, month, day, hour, dhour, nhours, mydays, yhours
integer :: ntime, ntime3, ntime6

! =====================================================================
! --- 3. Scientific Data Arrays ---
! =====================================================================
! Integer Arrays
integer, dimension(8) :: values
integer, dimension(:,:), allocatable :: bdtime, outvar_a

! Real Scalars 
real :: tc, slope

! Real 1D Allocatable Arrays
real, dimension(:), allocatable :: ttime, ttime3, ttime6, ttimed, ttimem, ttimes

! Real 2D Allocatable Arrays
real, dimension(:,:), allocatable :: sftlf, hgt, runsf
real, dimension(:,:), allocatable :: wrfv2D, i_wrfv2D, outvar, outvar_i
real, dimension(:,:), allocatable :: u_s, v_s, wind10, ust, t2, q2, uas, vas, ro, psf
real, dimension(:,:), allocatable :: rainc, rainnc, i_rainc, i_rainnc, rainsh
real, dimension(:,:), allocatable :: outvar_u, outvar_v
real, dimension(:,:), allocatable :: t_l, pres_s, phi_s  
real, dimension(:,:), allocatable :: mr, mr_sat, e_sfc, esat

! Real 3D Allocatable Arrays
real, dimension(:,:,:), allocatable :: outvar_h, wrfv3D
real, dimension(:,:,:), allocatable :: p, pb, press, p_iface, phb, ph, phi, zhgt, ua, va, u, v
real, dimension(:,:,:), allocatable :: qc, qi, qr, qs, smois
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

character(len=10)  :: vaid, varname, vunts, vunits
character(len=25)  :: wrfile, wrffile, geo, geog, wrfvar, wrfvarname, subrname, subname, fname, iwrfvar
character(len=100) :: longname, standardname, cellmethods, timeunits, frequency, experiment, dexperiment, creationdate
character(len=100) :: lname, stname, cmethods, tunts, freq, exper, dexper, cdate, experiment_id, experi

! =====================================================================
! --- 5. File Paths and Directories ---
! =====================================================================
character(len=400) :: infile, filename, outfile, outdom, fnameout, fnameout_u, fnameout_v
character(len=400) :: dir, dir2, gfile, geofile, aexp, adexp

! --- Global Metadata Strings ---
character(len=100)  :: conventions, activity_id, contact, cordex_domain
character(len=100)  :: domain_name, domain_id, driving_inst_id, driving_source_id
character(len=100)  :: driving_variant, further_info_url, grid_desc
character(len=100)  :: institution, institution_id, label, label_ext
character(len=100)  :: license, mip_era, product, project_id, release_year
character(len=100)  :: source_id, source_type, version_real, sim_start_date
character(len=500)  :: source_desc
character(len=1000) :: driving_source

! --- Global Metadata Numerics ---
real    :: dx_val, dy_val
integer :: we_dim, sn_dim, bt_dim

! -------------------------------------------------------------
! Namelist Group Definitions
! -------------------------------------------------------------
namelist /cordex_config/ &
    yeari, yearf, iniyear, nmonths, imonth, iday, ihour, &
    nz, nsoil, nlon, nlat, xoffset, yoffset, &
    dir, dir2, geog, wrffile, wrfile, dom, outdom, &
    wrfvar, vaid, height, pres, vunits, vunts, &
    lname, stname, cmethods, factor

namelist /global_metadata/ &
    conventions, activity_id, contact, cordex_domain, domain_name, &
    domain_id, driving_inst_id, driving_source_id, driving_variant, &
    experiment_id, experiment, further_info_url, grid_desc, institution, &
    institution_id, label, label_ext, license, mip_era, product, &
    project_id, release_year, source_desc, source_id, source_type, &
    version_real, sim_start_date, dx_val, dy_val, we_dim, sn_dim, &
    bt_dim, driving_source

contains

pure function pad_int(i, width) result(str)
    integer, intent(in) :: i, width
    character(len=10) :: str
    write(str, '(I0)') i
    str = repeat('0', width - len_trim(str)) // trim(str)
end function pad_int

end module datvar_s

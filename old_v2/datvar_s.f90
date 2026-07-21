module datvar_s
implicit none

! --- Module Grid & Time Array Dimensions ---
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
real, parameter :: missing_value     = 1.e20         
real, parameter :: huge_val          = 1.e20         


! --- Fixed Calendar Data Arrays ---
integer, dimension(tmonths) :: days
integer, dimension(tmonths), parameter :: days1   = [31,28,31,30,31,30,31,31,30,31,30,31]
integer, dimension(tmonths), parameter :: days2   = [31,29,31,30,31,30,31,31,30,31,30,31]
integer, dimension(nseason), parameter :: sedays1 = [90,92,92,91]
integer, dimension(nseason), parameter :: sedays2 = [91,92,92,91]

! Constant String Name Labels
character(len=3), dimension(nseason), parameter :: snames = ['Win','Spr','Sum','Aut']
character(len=3), dimension(tmonths), parameter :: aname  = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

! --- 1. Dimensions and Grid Arrays ---
integer :: nlon, nlat, nz, nzt, nsoil
integer :: latid, lonid, timeid, levid, timedim, latdim, londim, levdim, level

real :: rhours, factor, heightl, presl, pres
real, dimension(1) :: height, pressure
real, dimension(:),   allocatable :: rlon, rlat
real, dimension(:,:), allocatable :: lon, lat, tlon, tlat, cosalp, sinalp, landmask

real, dimension(4), parameter :: sdepth = [0.1, 0.3, 0.6, 1.0]
real, dimension(2,4) :: sdepth_bounds

! --- 2. Date, Time, and Offset Control ---
integer :: yeari, iniyear, yearf, nmonths, imonth, iday, ihour
integer :: xoffset, yoffset, ndays, nyr
integer :: ish, issh, it, iz, isx, isy, iyl
integer :: loop_year
integer :: year, month, day, mydays, hour, nhours, yhours
integer :: ntime
! Physical Constants and calculation arrays
!
! --- 3. Scientific Data Arrays ---
! Integer Arrays
integer, dimension(8) :: values
integer, dimension(:,:), allocatable :: bdtime, outvar_a

! Real Arrays
real, dimension(:)  , allocatable :: ttime

! Real Scalars 
real :: rcp, tc, slope

! 2D WRF In/Out Arrays
real, dimension(:,:), allocatable :: sftlf,hgt
real, dimension(:,:), allocatable :: wrfv2D, i_wrfv2D, outvar, outvar_i
real, dimension(:,:), allocatable :: u_s,v_s,wind10,ust,t2,q2,uas,vas,ro,psf
real, dimension(:,:), allocatable :: rainc, rainnc, i_rainc, i_rainnc, rainsh

! 3D WRF In/Out Arrays
real, dimension(:,:,:), allocatable :: outvar_h, wrfv3D
real, dimension(:,:,:), allocatable :: p, pb, press, p_iface, phb, ph, phi, zhgt, ua, va, u, v
real, dimension(:,:,:), allocatable :: qc, qi, qr, qs

integer :: ncid, varid, status
integer :: i, inperr, ichlef

! --- 4. Character Strings and Metadata (Short) ---
! Date and string formatting
character(len=2) :: ahouri, adayi, amonthi, ahourf, adayf, amonthf
character(len=2) :: ahour, aday, amonth, aiday, mm, dd, hh, mn, ss
character(len=4) :: ayear,ayearf,ayeari,yyyy

! System/Date stamps
character(len=5)  :: zone
character(len=8)  :: date
character(len=10) :: times

character   (len=4) :: ayearini
character (len=100) :: varname, vunits, vunts, vaid, timeunits, creationdate
character (len=100) :: experiment, experiment_id, frequency, cellmethods
character (len=100) :: longname, standardname, lname, stname, cmethods, tunts, freq
character (len=100) :: experi, exper, cdate

! --- 5. File Paths and Directories (Long) ---
character (len=400) :: infile, filename, outfile, outdom, fnameout
character (len=400) :: dir, dir2, gfile, geofile
character (len=400) :: dom, geo, geog, wrffile, wrfile, wrfvar, wrfvarname

! --- 6. Global Metadata Strings ---
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

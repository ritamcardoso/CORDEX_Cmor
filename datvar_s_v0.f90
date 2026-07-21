module datvar_s
!implicit none

! --- 1. Dimensions and Grid Arrays ---
integer :: nlon, nlat, nz, nsoil
integer :: latid, lonid, timeid, levid, timedim, latdim, londim, levdim

real :: rhours, factor, heightl, presl
real, dimension(1) :: height, pressure
real, dimension(:),   allocatable :: rlon, rlat
real, dimension(:,:), allocatable :: lon, lat, tlon, tlat, cosalp, sinalp, landmask

real, parameter :: p_top = 2000.

! --- 2. Date, Time, and Offset Control ---
! offsets must be integers to be used as NetCDF array indices
integer :: yeari, iniyear, yearf, nmonths, imonth, iday, ihour
integer :: xoffset, yoffset, ndays, nyr

! --- 3. Logical Flags for Input Verification (Required for readdata) ---
logical :: ok_iniyear, ok_yeari, ok_yearf, ok_nmonth, ok_imonth, ok_ihour
logical :: ok_ndays, ok_iday, ok_nlon, ok_nlat, ok_nz, ok_xoffset, ok_yoffset
logical :: ok_dir, ok_dir2, ok_dom, ok_outdom, ok_nsoil
logical :: ok_wrfvar, ok_vaid, ok_vunts, ok_lname, ok_stname, ok_cmethods
logical :: ok_geog, ok_wrffile, ok_exp, ok_dexp

! --- 4. NetCDF Specifics & Helper Variables ---
integer :: ncid, varid, status
integer :: i, inperr, ichlef
real, dimension(4), parameter :: sdepth = [0.1, 0.3, 0.6, 1.0]
real, dimension(2,4) :: sdepth_bounds

! --- 5. Character Strings and Metadata (Short) ---
character   (len=4) :: ayearini
character (len=100) :: varname, vunits, vaid, vunts, timeunits, creationdate
character (len=100) :: experiment, experiment_id, frequency, cellmethods
character (len=100) :: longname, standardname, lname, stname, cmethods, tunts, freq
character (len=100) :: experi, exper, cdate

! --- 6. File Paths and Directories (Long) ---
character (len=400) :: infile, filename, outfile, outdom, fnameout
character (len=400) :: dir, dir2, gfile, geofile, dexp_id, adexp
character (len=400) :: dom, geo, geog, wrffile, wrfile, wrfvar, wrfvarname

! --- 7. Global Metadata Strings (Lowercase) ---
character(len=100)  :: conventions, activity_id, contact, cordex_domain
character(len=100)  :: domain_name, domain_id, driving_inst_id, driving_source_id
character(len=100)  :: driving_variant, further_info_url, grid_desc
character(len=100)  :: institution, institution_id, label, label_ext
character(len=100)  :: license, mip_era, product, project_id, release_year
character(len=100)  :: source_id, source_type, version_real, sim_start_date
character(len=500)  :: source_desc
character(len=1000) :: driving_source   ! Long description for model details
    
! --- Global Metadata Numerics ---
real    :: dx_val, dy_val
integer :: we_dim, sn_dim, bt_dim

contains
pure function pad_int(i, width) result(str)
  integer, intent(in) :: i, width
  character(len=10) :: str
  write(str, '(I0)') i
  if (len_trim(str) < width) then
     str = repeat('0', width - len_trim(str)) // trim(str)
  else
     str = trim(str)
  endif
end function pad_int

end module datvar_s

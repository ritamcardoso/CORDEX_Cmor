module shared_subs
    use datvar_s
    implicit none
    ! ids of the horizontal bounds variables (set in def_horizontal_vars)
    integer, private :: vlonID, vlatID, xbndID, ybndID

contains

subroutine init_cordex_environment
    implicit none
    logical, save :: is_initialized = .false.

    ! Ensure the files are only read once per program run execution
    if (.not. is_initialized) then
        call read_cordex_config('inputlist.inp')
        call read_global_metadata('global_data.inp')
        is_initialized = .true.
    end if
end subroutine init_cordex_environment
!
!-----------------------------------------------------------------------
!
subroutine read_cordex_config(cfg_filename)
    character(len=*), intent(in) :: cfg_filename
    integer :: unit_id, status_id

    open(newunit=unit_id, file=trim(cfg_filename), status='old', action='read', iostat=status_id)
    if (status_id /= 0) then
        print *, "ERROR: Could not open cordex run config file: ", trim(cfg_filename)
        stop 91
    end if

    ! Initialize both to the target missing_value flag before testing namelist file content
    height(1) = missing_value
    pres      = missing_value
    projection = ''
    area_type  = ''
    pole_lat = missing_value;  pole_lon = missing_value
    truelat1 = missing_value;  truelat2 = missing_value
    stand_lon = missing_value; cen_lat = missing_value
    false_easting = 0.;        false_northing = 0.
    wp_step = 6
    outstep = -1
    cape_ice = 0

    read(unit_id, nml=cordex_config, iostat=status_id)
    if (status_id /= 0) then
        print *, "ERROR: Failed to parse namelist &cordex_config from: ", trim(cfg_filename)
        close(unit_id)
        stop 92
    end if

    ! Step of the sub-daily (3hr/6hr) programs: a divisor of 24 hours
    if (wp_step < 1 .or. mod(24, wp_step) /= 0) then
        print *, "ERROR: wp_step = ", wp_step, " in ", trim(cfg_filename), ": it must divide 24 (e.g. 3 or 6)"
        stop 95
    end if

    if (cape_ice /= 0 .and. cape_ice /= 1) then
        print *, "ERROR: cape_ice = ", cape_ice, " in ", trim(cfg_filename), ": it must be 0 (liquid) or 1 (ice)"
        stop 95
    end if

    ! Output step of the variable (header, hours): 1, 3, 6 ... 24 (daily); 0 = wp_step of the
    ! grid ini (variables whose step differs between experiments, e.g. CORDEX 6hr, LUCAS 1hr)
    if (outstep == 0) then
        ostep = wp_step
    else if (outstep > 0) then
        ostep = outstep
        if (mod(24, ostep) /= 0) then
            print *, "ERROR: outstep = ", outstep, " in ", trim(cfg_filename), ": it must divide 24 (1, 3, 6, 24)"
            stop 95
        end if
    else
        ostep = -1                       ! no outstep in the header: the program's own step
    end if

    ! The projection must be set in the grid's ini (see experiments/README.md)
    projection = trim(adjustl(projection))
    select case (trim(projection))
    case ('rotated_latitude_longitude')
        if (pole_lat == missing_value .or. pole_lon == missing_value) then
            print *, "ERROR: projection = 'rotated_latitude_longitude' needs pole_lat and pole_lon in ", trim(cfg_filename)
            stop 95
        end if
    case ('lambert_conformal_conic')
        continue   ! missing parameters are read from the geo_em file (read_geog)
    case default
        print *, "ERROR: set projection = 'rotated_latitude_longitude' or 'lambert_conformal_conic' in ", trim(cfg_filename)
        stop 95
    end select

    close(unit_id)
    print *, "Successfully loaded run configurations from: ", trim(cfg_filename)

    ! Automatically populate secondary targets if variables existed in the namelist file
    if (height(1) /= missing_value) then
        heightl = height(1)
        write(*,*) heightl
    end if

    if (pres /= missing_value) then
        presl       = pres
        pressure(1) = pres/100.
    end if

    wrfile = trim(adjustl(wrffile))

    ! Clean up character variables for NetCDF use
    varname       = trim(adjustl(vaid))
    vunits        = trim(adjustl(vunts))
    longname      = trim(adjustl(lname))
    standardname  = trim(adjustl(stname))
    cellmethods   = trim(adjustl(cmethods))

    write(ayearini,'(i4)')iniyear
    tunts='hours since '//ayearini//'-01-01 00:00'
    timeunits=trim(adjustl(tunts))                    

end subroutine read_cordex_config
!
!-----------------------------------------------------------------------
!
subroutine read_global_metadata(meta_filename)
    character(len=*), intent(in) :: meta_filename
    integer :: unit_id, status_id

    open(newunit=unit_id, file=trim(meta_filename), status='old', action='read', iostat=status_id)
    if (status_id /= 0) then
        print *, "ERROR: Could not open global compliance metadata file: ", trim(meta_filename)
        stop 93
    end if

    ! optional entries: empty unless the ini file sets them
    title = ''
    references = ''
    read(unit_id, nml=global_metadata, iostat=status_id)
    if (status_id /= 0) then
        print *, "ERROR: Failed to parse namelist &global_metadata from: ", trim(meta_filename)
        close(unit_id)
        stop 94
    end if

    close(unit_id)

    print *, "Successfully loaded global metadata compliance paths from: ", trim(meta_filename)
end subroutine read_global_metadata
!
!-----------------------------------------------------------------------
!
subroutine read_geog
use netcdf
use datvar_s
integer :: j
!
! Read geog file
gfile = trim(dir_in)//trim(geog)//'.nc'
geofile = gfile(1:len_trim(gfile))

status = nf90_open(geofile, nf90_nowrite, ncid)
call ncerror(status, 'opening ' // trim(geofile))
!
! Lambert projection parameters not set in the ini: take them from the
! geo_em file (WRF's TRUELAT1, TRUELAT2, STAND_LON, MOAD_CEN_LAT)
if (trim(projection) == 'lambert_conformal_conic') then
  if (truelat1 == missing_value) then
    status = nf90_get_att(ncid, nf90_global, 'TRUELAT1', truelat1)
    call ncerror(status, 'reading TRUELAT1 from '//trim(geofile))
  end if
  if (truelat2 == missing_value) then
    status = nf90_get_att(ncid, nf90_global, 'TRUELAT2', truelat2)
    call ncerror(status, 'reading TRUELAT2 from '//trim(geofile))
  end if
  if (stand_lon == missing_value) then
    status = nf90_get_att(ncid, nf90_global, 'STAND_LON', stand_lon)
    call ncerror(status, 'reading STAND_LON from '//trim(geofile))
  end if
  if (cen_lat == missing_value) then
    status = nf90_get_att(ncid, nf90_global, 'MOAD_CEN_LAT', cen_lat)
    call ncerror(status, 'reading MOAD_CEN_LAT from '//trim(geofile))
  end if
end if
!
! Computational coordinates (CLONG/CLAT of the geo_em file): for the rotated pole grid
! these are the rotated longitudes/latitudes, the 1-D rlon/rlat axes of the output.
! Not needed for lambert_conformal_conic, whose x/y axes come from lambert_xy.
allocate(rlon(nlon), rlat(nlat))
if (trim(projection) /= 'lambert_conformal_conic') then
  allocate(tlon(nlon, nlat), tlat(nlon, nlat))

  status=nf90_inq_varid(ncid,'CLONG',varid)
  call ncerror(status,'getting var id CLONG in '//trim(geofile))
  status=nf90_get_var(ncid,varid,tlon,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
  call ncerror(status,'reading CLONG from '//trim(geofile))
!
  status=nf90_inq_varid(ncid,'CLAT',varid)
  call ncerror(status,'getting var id CLAT in '//trim(geofile))
  status=nf90_get_var(ncid,varid,tlat,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
  call ncerror(status,'reading CLAT from '//trim(geofile))
!
  do i=1,nlon
   rlon(i)=tlon(i,1)
  enddo
  do j=1,nlat
   rlat(j)=tlat(1,j)
  enddo
  deallocate(tlon, tlat)
else
  rlon = 0.; rlat = 0.        ! not used (x/y axes)
endif
!
! Get geographical coordinates
!
allocate(lon(nlon,nlat), lat(nlon,nlat), landmask(nlon,nlat), urb_frac(nlon,nlat), luindex(nlon,nlat))

status = nf90_inq_varid(ncid, 'XLONG_M', varid)
call ncerror(status,'getting var id XLONG_M in '//trim(geofile))
status = nf90_get_var(ncid, varid, lon, (/xoffset, yoffset/), (/nlon, nlat/), (/1, 1/))
call ncerror(status,'reading XLONG_M from '//trim(geofile))

status = nf90_inq_varid(ncid, 'XLAT_M', varid)
call ncerror(status,'getting var id XLAT_M in '//trim(geofile))
status = nf90_get_var(ncid, varid, lat, (/xoffset, yoffset/), (/nlon, nlat/), (/1, 1/))
call ncerror(status,'reading XLAT_M from '//trim(geofile))

status=nf90_inq_varid(ncid,'LANDMASK',varid)
call ncerror(status,'getting var id LANDMASK in '//trim(geofile))

status=nf90_get_var(ncid,varid,landmask,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading LANDMASK from '//trim(geofile))

! Dominant land-use category (required, as in WRF) and its table (MMINLU attribute:
! MODIFIED_IGBP_MODIS_NOAH or USGS), used by urban_cell (landuse_subs.f90)
status=nf90_inq_varid(ncid,'LU_INDEX',varid)
call ncerror(status,'getting var id LU_INDEX in '//trim(geofile))
status=nf90_get_var(ncid,varid,luindex,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading LU_INDEX from '//trim(geofile))

lu_table = ''
status = nf90_get_att(ncid, nf90_global, 'MMINLU', lu_table)
if (status /= nf90_noerr) lu_table = 'MODIFIED_IGBP_MODIS_NOAH'
lu_usgs = (index(lu_table, 'USGS') > 0)

! Urban fraction (urban variables). Optional: without it there are no urban cells.

status = nf90_inq_varid(ncid, 'FRC_URB2D', varid)
if (status == nf90_noerr) then
  status = nf90_get_var(ncid, varid, urb_frac, (/xoffset,yoffset/), (/nlon,nlat/), (/1,1/))
  call ncerror(status,'reading FRC_URB2D from '//trim(geofile))
else
  urb_frac = 0.
  print *, 'Note: no FRC_URB2D in '//trim(geofile)//' (set to 0: no urban cells)'
endif
!
! Cell corners for vertices_lon/vertices_lat: WRF's corner points XLONG_C/XLAT_C
! (one more than the mass points in each direction); if the geo_em file has
! none, each corner is the mean of the 4 mass points around it.
call read_corners(ncid)

status = nf90_close(ncid)
call ncerror(status,'closing '//trim(geofile))

end subroutine read_geog
!
!-----------------------------------------------------------------------
!
subroutine read_corners(ncid)
use netcdf
integer, intent(in) :: ncid
real, allocatable :: clon(:,:), clat(:,:), mlon(:,:), mlat(:,:)
integer :: i, j, idlon, idlat

allocate(clon(nlon+1,nlat+1), clat(nlon+1,nlat+1))
if (nf90_inq_varid(ncid, 'XLONG_C', idlon) == nf90_noerr .and. &
    nf90_inq_varid(ncid, 'XLAT_C',  idlat) == nf90_noerr) then
    status = nf90_get_var(ncid, idlon, clon, (/xoffset, yoffset/), (/nlon+1, nlat+1/))
    call ncerror(status,'reading XLONG_C from '//trim(geofile))
    status = nf90_get_var(ncid, idlat, clat, (/xoffset, yoffset/), (/nlon+1, nlat+1/))
    call ncerror(status,'reading XLAT_C from '//trim(geofile))
else
    if (xoffset < 2 .or. yoffset < 2) then
        print *, "ERROR: no XLONG_C/XLAT_C in the geo_em file and xoffset/yoffset < 2: cannot compute cell corners"
        stop 96
    end if
    allocate(mlon(nlon+2,nlat+2), mlat(nlon+2,nlat+2))
    status = nf90_inq_varid(ncid, 'XLONG_M', idlon)
    call ncerror(status,'getting var id XLONG_M in '//trim(geofile))
    status = nf90_get_var(ncid, idlon, mlon, (/xoffset-1, yoffset-1/), (/nlon+2, nlat+2/))
    call ncerror(status,'reading XLONG_M for the cell corners from '//trim(geofile))
    status = nf90_inq_varid(ncid, 'XLAT_M', idlat)
    call ncerror(status,'getting var id XLAT_M in '//trim(geofile))
    status = nf90_get_var(ncid, idlat, mlat, (/xoffset-1, yoffset-1/), (/nlon+2, nlat+2/))
    call ncerror(status,'reading XLAT_M for the cell corners from '//trim(geofile))
    do j = 1, nlat+1
        do i = 1, nlon+1
            clon(i,j) = 0.25*(mlon(i,j) + mlon(i+1,j) + mlon(i,j+1) + mlon(i+1,j+1))
            clat(i,j) = 0.25*(mlat(i,j) + mlat(i+1,j) + mlat(i,j+1) + mlat(i+1,j+1))
        end do
    end do
    deallocate(mlon, mlat)
end if

! 4 corners per cell, counterclockwise: SW, SE, NE, NW
allocate(vlon(4,nlon,nlat), vlat(4,nlon,nlat))
do j = 1, nlat
    do i = 1, nlon
        vlon(:,i,j) = dble((/ clon(i,j), clon(i+1,j), clon(i+1,j+1), clon(i,j+1) /))
        vlat(:,i,j) = dble((/ clat(i,j), clat(i+1,j), clat(i+1,j+1), clat(i,j+1) /))
    end do
end do
deallocate(clon, clat)
end subroutine read_corners
!
!-----------------------------------------------------------------------
!
subroutine ncerror(status,info)
use netcdf
integer :: status
character(len=*),optional :: info

if( status /= 0 ) then
  print *, trim(nf90_strerror(status))
  if( present(info) ) print*,trim(info)
  stop 99
endif

end subroutine ncerror
!
!-----------------------------------------------------------------------
!
! Horizontal grid, shared by all write routines. The projection comes from
! the grid's ini (&cordex_config: projection and its parameters):
!   rotated_latitude_longitude: 1-D rlon/rlat (degrees) + pole_lat/pole_lon
!   lambert_conformal_conic:    1-D x/y (m)         + truelat1/2, stand_lon, cen_lat
! Both write 2-D lon/lat and a grid-mapping variable named after the projection.
!
subroutine def_horizontal_dims(ncid, XDimID, YDimID, BDimID, VDimID)
use netcdf
integer, intent(in)  :: ncid
integer, intent(out) :: XDimID, YDimID, BDimID, VDimID
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "vertices", 4, VDimID)
if (trim(projection) == 'lambert_conformal_conic') then
    status = nf90_def_dim(ncid, "x", nlon, XDimID)
    status = nf90_def_dim(ncid, "y", nlat, YDimID)
else
    status = nf90_def_dim(ncid, "rlon", nlon, XDimID)
    status = nf90_def_dim(ncid, "rlat", nlat, YDimID)
end if
call handle_err(status)
end subroutine def_horizontal_dims
!
!-----------------------------------------------------------------------
!
subroutine def_horizontal_vars(ncid, XDimID, YDimID, BDimID, VDimID, LonVarID, LatVarID, XVarID, YVarID, gmVarID)
use netcdf
integer, intent(in)  :: ncid, XDimID, YDimID, BDimID, VDimID
character(len=4) :: xn, yn
integer, intent(out) :: LonVarID, LatVarID, XVarID, YVarID, gmVarID

status = nf90_def_var(ncid, "lon", nf90_double, (/ XDimID, YDimID /), LonVarID)
status = nf90_def_var(ncid, "lat", nf90_double, (/ XDimID, YDimID /), LatVarID)
status = nf90_put_att(ncid, LonVarID, "long_name","longitude")
status = nf90_put_att(ncid, LonVarID, "standard_name","longitude")
status = nf90_put_att(ncid, LonVarID, "units","degrees_east")
status = nf90_put_att(ncid, LonVarID, "_CoordinateAxisType","Lon")
status = nf90_put_att(ncid, LatVarID, "long_name","latitude")
status = nf90_put_att(ncid, LatVarID, "standard_name","latitude")
status = nf90_put_att(ncid, LatVarID, "units","degrees_north")
status = nf90_put_att(ncid, LatVarID, "_CoordinateAxisType","Lat")
status = nf90_put_att(ncid, LonVarID, "bounds","vertices_lon")
status = nf90_put_att(ncid, LatVarID, "bounds","vertices_lat")
call handle_err(status)

! cell corners of lon/lat: vertices_lon/lat(vertices, x, y) in Fortran order
status = nf90_def_var(ncid, "vertices_lon", nf90_double, (/ VDimID, XDimID, YDimID /), vlonID)
status = nf90_def_var(ncid, "vertices_lat", nf90_double, (/ VDimID, XDimID, YDimID /), vlatID)
call handle_err(status)

status = nf90_def_var(ncid, trim(projection), nf90_char, gmVarID)
status = nf90_put_att(ncid, gmVarID, "grid_mapping_name", trim(projection))

if (trim(projection) == 'lambert_conformal_conic') then
    status = nf90_def_var(ncid, "x", nf90_double, (/ XDimID /), XVarID)
    status = nf90_def_var(ncid, "y", nf90_double, (/ YDimID /), YVarID)
    status = nf90_put_att(ncid, XVarID, "long_name","x coordinate of projection")
    status = nf90_put_att(ncid, XVarID, "standard_name","projection_x_coordinate")
    status = nf90_put_att(ncid, XVarID, "units","m")
    status = nf90_put_att(ncid, XVarID, "axis","X")
    status = nf90_put_att(ncid, YVarID, "long_name","y coordinate of projection")
    status = nf90_put_att(ncid, YVarID, "standard_name","projection_y_coordinate")
    status = nf90_put_att(ncid, YVarID, "units","m")
    status = nf90_put_att(ncid, YVarID, "axis","Y")
    if (truelat1 == truelat2) then
        status = nf90_put_att(ncid, gmVarID, "standard_parallel", truelat1)
    else
        status = nf90_put_att(ncid, gmVarID, "standard_parallel", (/ truelat1, truelat2 /))
    end if
    status = nf90_put_att(ncid, gmVarID, "longitude_of_central_meridian", stand_lon)
    status = nf90_put_att(ncid, gmVarID, "latitude_of_projection_origin", cen_lat)
    status = nf90_put_att(ncid, gmVarID, "false_easting", false_easting)
    status = nf90_put_att(ncid, gmVarID, "false_northing", false_northing)
else
    status = nf90_def_var(ncid, "rlon", nf90_double, (/ XDimID /), XVarID)
    status = nf90_def_var(ncid, "rlat", nf90_double, (/ YDimID /), YVarID)
    status = nf90_put_att(ncid, XVarID, "long_name","longitude in rotated pole grid")
    status = nf90_put_att(ncid, XVarID, "standard_name","grid_longitude")
    status = nf90_put_att(ncid, XVarID, "units","degrees")
    status = nf90_put_att(ncid, XVarID, "axis","X")
    status = nf90_put_att(ncid, YVarID, "long_name","latitude in rotated pole grid")
    status = nf90_put_att(ncid, YVarID, "standard_name","grid_latitude")
    status = nf90_put_att(ncid, YVarID, "units","degrees")
    status = nf90_put_att(ncid, YVarID, "axis","Y")
    status = nf90_put_att(ncid, gmVarID, "grid_north_pole_latitude", pole_lat)
    status = nf90_put_att(ncid, gmVarID, "grid_north_pole_longitude", pole_lon)
end if
status = nf90_put_att(ncid, gmVarID, "earth_radius", earth_radius)
call handle_err(status)

! bounds of the 1-D axes: rlon_bnds/rlat_bnds or x_bnds/y_bnds
if (trim(projection) == 'lambert_conformal_conic') then
    xn = 'x'; yn = 'y'
else
    xn = 'rlon'; yn = 'rlat'
end if
status = nf90_put_att(ncid, XVarID, "bounds", trim(xn)//'_bnds')
status = nf90_put_att(ncid, YVarID, "bounds", trim(yn)//'_bnds')
status = nf90_def_var(ncid, trim(xn)//'_bnds', nf90_double, (/ BDimID, XDimID /), xbndID)
status = nf90_def_var(ncid, trim(yn)//'_bnds', nf90_double, (/ BDimID, YDimID /), ybndID)
call handle_err(status)
end subroutine def_horizontal_vars
!
!-----------------------------------------------------------------------
!
subroutine put_horizontal_vars(ncid, LonVarID, LatVarID, XVarID, YVarID)
use netcdf
integer, intent(in) :: ncid, LonVarID, LatVarID, XVarID, YVarID
real(kind=8) :: xc(nlon), yc(nlat)

status = nf90_put_var(ncid, LonVarID, lon)
call handle_err(status)
status = nf90_put_var(ncid, LatVarID, lat)
call handle_err(status)
if (trim(projection) == 'lambert_conformal_conic') then
    call lambert_xy(xc, yc)
else
    xc = dble(rlon); yc = dble(rlat)
end if
status = nf90_put_var(ncid, XVarID, xc)
call handle_err(status)
status = nf90_put_var(ncid, YVarID, yc)
call handle_err(status)
status = nf90_put_var(ncid, xbndID, axis_bounds(xc, nlon))
call handle_err(status)
status = nf90_put_var(ncid, ybndID, axis_bounds(yc, nlat))
call handle_err(status)
status = nf90_put_var(ncid, vlonID, vlon)
call handle_err(status)
status = nf90_put_var(ncid, vlatID, vlat)
call handle_err(status)
end subroutine put_horizontal_vars
!
!-----------------------------------------------------------------------
!
! bounds of a regular 1-D axis: half-way to the neighbours (edges extrapolated)
function axis_bounds(c, n) result(b)
integer, intent(in) :: n
real(kind=8), intent(in) :: c(n)
real(kind=8) :: b(2,n)
integer :: k
do k = 2, n
    b(1,k) = 0.5d0*(c(k-1) + c(k))
    b(2,k-1) = b(1,k)
end do
b(1,1) = c(1) - (b(2,1) - c(1))
b(2,n) = c(n) + (c(n) - b(1,n))
end function axis_bounds
!
!-----------------------------------------------------------------------
!
! x/y (m) of the grid columns/rows: lon/lat of the middle row/column projected
! with the Lambert conformal conic formulas (sphere of radius earth_radius).
subroutine lambert_xy(xc, yc)
real(kind=8), intent(out) :: xc(nlon), yc(nlat)
real(kind=8), parameter :: pi = 3.14159265358979d0, d2r = pi/180.d0
real(kind=8) :: phi1, phi2, phi0, n, f, rho0, rho, th
integer :: i, j, im, jm

phi1 = truelat1*d2r; phi2 = truelat2*d2r; phi0 = cen_lat*d2r
if (abs(truelat1 - truelat2) < 1.e-6) then
    n = sin(phi1)
else
    n = log(cos(phi1)/cos(phi2)) / log(tan(pi/4 + phi2/2)/tan(pi/4 + phi1/2))
end if
f    = cos(phi1)*tan(pi/4 + phi1/2)**n / n
rho0 = earth_radius*f / tan(pi/4 + phi0/2)**n

jm = (nlat + 1)/2; im = (nlon + 1)/2
do i = 1, nlon
    rho = earth_radius*f / tan(pi/4 + dble(lat(i,jm))*d2r/2)**n
    th  = n*(dble(lon(i,jm)) - stand_lon)*d2r
    xc(i) = false_easting + rho*sin(th)
end do
do j = 1, nlat
    rho = earth_radius*f / tan(pi/4 + dble(lat(im,j))*d2r/2)**n
    th  = n*(dble(lon(im,j)) - stand_lon)*d2r
    yc(j) = false_northing + rho0 - rho*cos(th)
end do
end subroutine lambert_xy
!
!-----------------------------------------------------------------------
!
subroutine def_area_type(ncid, TypeVarID)
! scalar coordinate "type" (standard_name area_type) of the header's area_type, if set
use netcdf
integer, intent(in) :: ncid
integer, intent(out) :: TypeVarID
integer :: TypeDimID, status
TypeVarID = -1
if (len_trim(area_type) == 0) return
status = nf90_def_dim(ncid, "strlen", len_trim(area_type), TypeDimID)
status = nf90_def_var(ncid, "type", nf90_char, (/ TypeDimID /), TypeVarID)
status = nf90_put_att(ncid, TypeVarID, "standard_name", "area_type")
select case (trim(area_type))
case ('lake_and_inland_sea')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Lake and Inland Sea area type")
case ('urban')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Urban area type")
case ('tree')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Tree area type")
case ('shrubs')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Shrub area type")
case ('natural_grasses')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Natural grass area type")
case ('crops')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Crop area type")
case ('bare_ground')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Bare ground area type")
case ('vegetation')
    status = nf90_put_att(ncid, TypeVarID, "long_name", "Vegetation area type")
case default
    status = nf90_put_att(ncid, TypeVarID, "long_name", "area type")
end select
call handle_err(status)
end subroutine def_area_type
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_2D(uvar)
use netcdf
use datvar_s
!
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID,VDimID,TypeDimID,TypeVarID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
real, dimension(nlon,nlat) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(IOR(nf90_noclobber, nf90_netcdf4), nf90_classic_model), ncid)
call handle_err(status)

call def_horizontal_dims(ncid, LonDimID, LatDimID, BDimID, VDimID)

call def_horizontal_vars(ncid, LonDimID, LatDimID, BDimID, VDimID, LonVarID, LatVarID, rlonVarID, rlatVarID, rpVarID)

! sftlaf/sfturf/land-cover fractions: scalar coordinate "type" (area_type from the header)
call def_area_type(ncid, TypeVarID)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 1)
call handle_err(status)                 

if (len_trim(standardname) > 0) status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
if (trim(vunits) == 'K') status = nf90_put_att(ncid, uVarID, "units_metadata","temperature: on_scale")
status = nf90_put_att(ncid, uVarID, "grid_mapping",trim(projection))
if (len_trim(area_type) > 0) then
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon type")
else
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon")
end if
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",huge_val)
status = nf90_put_att(ncid, uVarID, "missing_value",huge_val)


call write_global_attributes

status = nf90_enddef(ncid)

call put_horizontal_vars(ncid, LonVarID, LatVarID, rlonVarID, rlatVarID)
if (len_trim(area_type) > 0) then
    status = nf90_put_var(ncid, TypeVarID, trim(area_type))
    call handle_err(status)
end if
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
return
end subroutine write_netcdf_2D
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_fx_soil(uvar)
! fx variable on the soil layers (lon, lat, depth), e.g. slthick: depth = middle of each
! layer, depth_bnds from the layer thicknesses sl_dz (datvar_s, from DZS)
use netcdf
use datvar_s
!
integer :: LatDimID,LonDimID,BDimID,VDimID,depth_dimid,SVarId,SBVarId
integer :: LonVarID,LatVarID,rlatVarId,rlonVarID,uVarID,rpVarID,ks
real, dimension(:,:,:) :: uvar
real(kind=8), dimension(2,size(sl_dz)) :: zb

zb(1,1) = 0.d0
do ks = 1, size(sl_dz)
  if (ks > 1) zb(1,ks) = zb(2,ks-1)
  zb(2,ks) = zb(1,ks) + dble(sl_dz(ks))
enddo

status = nf90_create(fnameout, IOR(IOR(nf90_noclobber, nf90_netcdf4), nf90_classic_model), ncid)
call handle_err(status)

call def_horizontal_dims(ncid, LonDimID, LatDimID, BDimID, VDimID)
status = nf90_def_dim(ncid, "depth", size(sl_dz), depth_dimid)
call handle_err(status)

call def_horizontal_vars(ncid, LonDimID, LatDimID, BDimID, VDimID, LonVarID, LatVarID, rlonVarID, rlatVarID, rpVarID)

status = nf90_def_var(ncid, "depth", nf90_double, (/ depth_dimid /), SVarId)
call handle_err(status)
status = nf90_def_var(ncid, "depth_bnds", nf90_double, (/ BDimID, depth_dimid /), SBVarId)
call handle_err(status)
status = nf90_put_att(ncid, SVarId, "standard_name", "depth")
status = nf90_put_att(ncid, SVarId, "long_name", "depth")
status = nf90_put_att(ncid, SVarId, "bounds", "depth_bnds")
status = nf90_put_att(ncid, SVarId, "units", "m")
status = nf90_put_att(ncid, SVarId, "positive", "down")
status = nf90_put_att(ncid, SVarId, "axis", "Z")

status = nf90_def_var(ncid, varname, nf90_float, (/ LonDimId, LatDimID, depth_dimid /), uVarId)
call handle_err(status)
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 1)
call handle_err(status)

if (len_trim(standardname) > 0) status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping",trim(projection))
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",huge_val)
status = nf90_put_att(ncid, uVarID, "missing_value",huge_val)

call write_global_attributes

status = nf90_enddef(ncid)

call put_horizontal_vars(ncid, LonVarID, LatVarID, rlonVarID, rlatVarID)
status = nf90_put_var(ncid, SVarID, anint(5.d5*(zb(1,:)+zb(2,:)))/1.d6 )
call handle_err(status)
status = nf90_put_var(ncid, SBVarID, anint(1.d6*zb)/1.d6 )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
end subroutine write_netcdf_fx_soil
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_fx_cat(uvar)
! fx variable per land-use category (lon, lat, vegtype), e.g. landCoverFrac: lc_ncat
! categories named lc_names (datvar_s) in the string coordinate vegtype
use netcdf
use datvar_s
!
integer :: LatDimID,LonDimID,BDimID,VDimID,cat_dimid,str_dimid,CVarId
integer :: LonVarID,LatVarID,rlatVarId,rlonVarID,uVarID,rpVarID,kc
real, dimension(:,:,:) :: uvar

status = nf90_create(fnameout, IOR(IOR(nf90_noclobber, nf90_netcdf4), nf90_classic_model), ncid)
call handle_err(status)

call def_horizontal_dims(ncid, LonDimID, LatDimID, BDimID, VDimID)
status = nf90_def_dim(ncid, "vegtype", lc_ncat, cat_dimid)
call handle_err(status)
status = nf90_def_dim(ncid, "strlen", len(lc_names), str_dimid)
call handle_err(status)

call def_horizontal_vars(ncid, LonDimID, LatDimID, BDimID, VDimID, LonVarID, LatVarID, rlonVarID, rlatVarID, rpVarID)

status = nf90_def_var(ncid, "vegtype", nf90_char, (/ str_dimid, cat_dimid /), CVarId)
call handle_err(status)
status = nf90_put_att(ncid, CVarId, "long_name", "land-use category of the WRF land-use table")

status = nf90_def_var(ncid, varname, nf90_float, (/ LonDimId, LatDimID, cat_dimid /), uVarId)
call handle_err(status)
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 1)
call handle_err(status)

if (len_trim(standardname) > 0) status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping",trim(projection))
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon vegtype")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",huge_val)
status = nf90_put_att(ncid, uVarID, "missing_value",huge_val)

call write_global_attributes

status = nf90_enddef(ncid)

call put_horizontal_vars(ncid, LonVarID, LatVarID, rlonVarID, rlatVarID)
do kc = 1, lc_ncat
  status = nf90_put_var(ncid, CVarId, lc_names(kc), start=(/1,kc/), count=(/len(lc_names),1/))
  call handle_err(status)
enddo
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
end subroutine write_netcdf_fx_cat
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime_3d(uvar,mtime,utime,btime)
use netcdf
use datvar_s
!
integer :: LatDimID,LonDimID,BDimID,HDimID,VDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,rpVarID
integer :: HVarID, TypeVarID
integer :: mtime
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
character(len=40) :: day_units
real(kind=8) :: tfac
logical :: point

if (mtime < 1) then                ! variable calendar: no (complete) time step in this chunk
  write(*,*) 'no time step to write: ', trim(fnameout), ' is not written'
  return
endif
! Time axis in days since <iniyear>-01-01T00:00:00Z: values that the
! programs count in hours are divided by 24 (tfac), daily ones are kept.
day_units = 'days since '//ayearini//'-01-01T00:00:00Z'
tfac = 1.d0
if (timeunits(1:5) == 'hours') tfac = 24.d0

! Instantaneous variables (cell_methods "time: point") have no time bounds
point = index(cellmethods, 'time: point') > 0

status = nf90_create(fnameout, IOR(IOR(nf90_clobber, nf90_netcdf4), nf90_classic_model), ncid)
call handle_err(status)

call def_horizontal_dims(ncid, LonDimID, LatDimID, BDimID, VDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, (/ HDimID /), TVarId)
if (.not. point) status = nf90_def_var(ncid, "time_bnds", nf90_double, (/ BDimID, HDimID /), TBVarId)

call def_horizontal_vars(ncid, LonDimID, LatDimID, BDimID, VDimID, LonVarID, LatVarID, rlonVarID, rlatVarID, rpVarID)
call def_area_type(ncid, TypeVarID)     ! hourly land-cover fractions (RCM_sfc_landuse)

! Check for optional Z coordinate conditions
if (height(1) > 0.0) then
    status = nf90_def_var(ncid, "height", nf90_double, HVarId)
elseif (pressure(1) > 0.0) then
    status = nf90_def_var(ncid, "plev", nf90_double, HVarId)
end if

status = nf90_def_var(ncid, varname, nf90_float, (/ LonDimId, LatDimID, HDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 1)
call handle_err(status)

status = nf90_put_att(ncid, TVarID, "standard_name","time")
status = nf90_put_att(ncid, TVarID, "long_name","time")
if (.not. point) status = nf90_put_att(ncid, TVarID, "bounds","time_bnds")
status = nf90_put_att(ncid, TVarID, "units",trim(day_units))
status = nf90_put_att(ncid, TVarID, "calendar","proleptic_gregorian")
status = nf90_put_att(ncid, TVarID, "units_metadata","leap_seconds: none")
status = nf90_put_att(ncid, TVarID, "axis","T")

if (len_trim(standardname) > 0) status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
if (trim(vunits) == 'K') status = nf90_put_att(ncid, uVarID, "units_metadata","temperature: on_scale")
status = nf90_put_att(ncid, uVarID, "grid_mapping",trim(projection))

! Dynamically update coordinates attribute string matching configuration state
if (height(1) > 0.0) then
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time height")
elseif (pressure(1) > 0.0) then
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time plev")
elseif (len_trim(area_type) > 0) then
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time type")
else
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time")
end if

status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",huge_val)
status = nf90_put_att(ncid, uVarID, "missing_value",huge_val)

! Set attributes on the dynamic variable layer if it was initialized
if (height(1) > 0.0) then
    status = nf90_put_att(ncid, HVarID, "long_name","height")
    status = nf90_put_att(ncid, HVarID, "standard_name","height")
    status = nf90_put_att(ncid, HVarID, "positive","up")
    status = nf90_put_att(ncid, HVarID, "axis","Z")
    status = nf90_put_att(ncid, HVarID, "units","m")
elseif (pressure(1) > 0.0) then
    status = nf90_put_att(ncid, HVarID, "long_name","pressure")
    status = nf90_put_att(ncid, HVarID, "standard_name","air_pressure")
    status = nf90_put_att(ncid, HVarID, "positive","down")
    status = nf90_put_att(ncid, HVarID, "axis","Z")
    status = nf90_put_att(ncid, HVarID, "units","Pa")
end if


call write_global_attributes

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, dble(utime)/tfac )
call handle_err(status)
if (.not. point) then
    status = nf90_put_var(ncid, TBVarID, dble(btime)/tfac )
    call handle_err(status)
end if
call put_horizontal_vars(ncid, LonVarID, LatVarID, rlonVarID, rlatVarID)
call handle_err(status)
if (len_trim(area_type) > 0) then
    status = nf90_put_var(ncid, TypeVarID, trim(area_type))
    call handle_err(status)
end if

! Write the values to the variable array if initialized
if (height(1) > 0.0) then
    status = nf90_put_var(ncid, HVarID, height )
    call handle_err(status)
elseif (pressure(1) > 0.0) then
    status = nf90_put_var(ncid, HVarID, dble(pressure)*100.d0 )   ! hPa -> Pa
    call handle_err(status)
end if

status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)

return
end subroutine write_netcdf_rtime_3d
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime_soil(uvar,mtime,utime,btime)
use netcdf
use datvar_s
!
integer :: LatDimID,LonDimID,BDimID,HDimID,VDimID,depth_dimid,SVarId,SBVarId
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,rpVarID
integer :: mtime
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,nsoil,mtime) :: uvar
character(len=40) :: day_units
real(kind=8) :: tfac
logical :: point

if (mtime < 1) then                ! variable calendar: no (complete) time step in this chunk
  write(*,*) 'no time step to write: ', trim(fnameout), ' is not written'
  return
endif
! Time axis in days since <iniyear>-01-01T00:00:00Z: values that the
! programs count in hours are divided by 24 (tfac), daily ones are kept.
day_units = 'days since '//ayearini//'-01-01T00:00:00Z'
tfac = 1.d0
if (timeunits(1:5) == 'hours') tfac = 24.d0

! Instantaneous variables (cell_methods "time: point") have no time bounds
point = index(cellmethods, 'time: point') > 0

status = nf90_create(fnameout, IOR(IOR(nf90_clobber, nf90_netcdf4), nf90_classic_model), ncid)
call handle_err(status)

call def_horizontal_dims(ncid, LonDimID, LatDimID, BDimID, VDimID)
status = nf90_def_dim(ncid, "depth", nsoil, depth_dimid)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, (/ HDimID /), TVarId)
if (.not. point) status = nf90_def_var(ncid, "time_bnds", nf90_double, (/ BDimID, HDimID /), TBVarId)

call def_horizontal_vars(ncid, LonDimID, LatDimID, BDimID, VDimID, LonVarID, LatVarID, rlonVarID, rlatVarID, rpVarID)

status = nf90_def_var(ncid, "depth", nf90_double, (/ depth_dimid /), SVarId)
status = nf90_def_var(ncid, "depth_bnds", nf90_double, (/ BDimID, depth_dimid /), SBVarId)

status = nf90_def_var(ncid, varname, nf90_float, (/ LonDimId, LatDimID, depth_dimid, HDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, nsoil, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 1)
call handle_err(status)

status = nf90_put_att(ncid, TVarID, "standard_name","time")
status = nf90_put_att(ncid, TVarID, "long_name","time")
if (.not. point) status = nf90_put_att(ncid, TVarID, "bounds","time_bnds")
status = nf90_put_att(ncid, TVarID, "units",trim(day_units))
status = nf90_put_att(ncid, TVarID, "calendar","proleptic_gregorian")
status = nf90_put_att(ncid, TVarID, "units_metadata","leap_seconds: none")
status = nf90_put_att(ncid, TVarID, "axis","T")

status = nf90_put_att(ncid, SVarId, "standard_name", "depth")
status = nf90_put_att(ncid, SVarId, "long_name", "depth")
status = nf90_put_att(ncid, SVarId, "bounds", "depth_bnds")
status = nf90_put_att(ncid, SVarId, "units", "m")
status = nf90_put_att(ncid, SVarId, "positive", "down")
status = nf90_put_att(ncid, SVarId, "axis", "Z")


if (len_trim(standardname) > 0) status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
if (trim(vunits) == 'K') status = nf90_put_att(ncid, uVarID, "units_metadata","temperature: on_scale")
status = nf90_put_att(ncid, uVarID, "grid_mapping",trim(projection))
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",huge_val)
status = nf90_put_att(ncid, uVarID, "missing_value",huge_val)


call write_global_attributes

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, dble(utime)/tfac )
call handle_err(status)
if (.not. point) then
    status = nf90_put_var(ncid, TBVarID, dble(btime)/tfac )
    call handle_err(status)
end if
call put_horizontal_vars(ncid, LonVarID, LatVarID, rlonVarID, rlatVarID)
call handle_err(status)
! depth coordinate = middle of each soil layer (sdepth holds the layer thicknesses)
status = nf90_put_var(ncid, SVarID, anint(5.d5*(dble(sdepth_bounds(1,:))+dble(sdepth_bounds(2,:))))/1.d6 )
call handle_err(status)
status = nf90_put_var(ncid, SBVarID, anint(1.d6*dble(sdepth_bounds))/1.d6 )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)

return
end subroutine write_netcdf_rtime_soil
!
!-----------------------------------------------------------------------
!
subroutine write_global_attributes
    use netcdf
    use datvar_s
!
    character(len=20)  :: utc_now
    character(len=49)  :: tracking
    character(len=400) :: history_str
    character(len=300) :: title_str

    ! Dynamically trigger namelist reading cleanly right before writing attributes
    call init_cordex_environment

    ! Creation time (UTC, YYYY-MM-DDThh:mm:ssZ), tracking_id and history
    call utc_timestamp(utc_now)
    call new_tracking_id(tracking)
    history_str = trim(utc_now)//';rewrote data to be consistent with '//trim(activity_id)// &
                  ' for variable '//trim(varname)//' found in table CORDEX-CMIP6_'//trim(frequency)//'.'

    ! Title: from the global ini, or built from its entries, e.g.
    ! "IDL-FCUL WRF451Q downscaling of MPI-ESM1-2-HR ssp370 for CORDEX-CMIP6 EUR-12"
    if (len_trim(title) > 0) then
        title_str = trim(title)
    else
        title_str = trim(institution_id)//' '//trim(source_id)//' downscaling of '// &
                    trim(driving_source_id)//' '//trim(experiment_id)//' for '// &
                    trim(project_id)//' '//trim(domain_id)
    end if

    ! String Attributes
    status = nf90_put_att(ncid, nf90_global, "Conventions", trim(conventions))
    status = nf90_put_att(ncid, nf90_global, "activity_id", trim(activity_id))
    status = nf90_put_att(ncid, nf90_global, "contact", trim(contact))
    status = nf90_put_att(ncid, nf90_global, "creation_date", trim(utc_now))
    status = nf90_put_att(ncid, nf90_global, "CORDEX_domain", trim(CORDEX_domain))
    status = nf90_put_att(ncid, nf90_global, "domain", trim(domain_name))
    status = nf90_put_att(ncid, nf90_global, "domain_id", trim(domain_id))
    status = nf90_put_att(ncid, nf90_global, "driving_experiment", trim(experiment))
    status = nf90_put_att(ncid, nf90_global, "driving_experiment_id", trim(experiment_id))
    status = nf90_put_att(ncid, nf90_global, "driving_institution_id", trim(driving_inst_id))
    status = nf90_put_att(ncid, nf90_global, "driving_source_id", trim(driving_source_id))
    status = nf90_put_att(ncid, nf90_global, "driving_source", trim(driving_source))
    status = nf90_put_att(ncid, nf90_global, "driving_variant_label", trim(driving_variant))
    status = nf90_put_att(ncid, nf90_global, "external_variables", "areacella")
    status = nf90_put_att(ncid, nf90_global, "frequency", trim(frequency))
    status = nf90_put_att(ncid, nf90_global, "further_info_url", trim(further_info_url))
    status = nf90_put_att(ncid, nf90_global, "grid", trim(grid_desc))
    status = nf90_put_att(ncid, nf90_global, "history", trim(history_str))
    status = nf90_put_att(ncid, nf90_global, "institution", trim(institution))
    status = nf90_put_att(ncid, nf90_global, "institution_id", trim(institution_id))
    status = nf90_put_att(ncid, nf90_global, "label", trim(label))
    status = nf90_put_att(ncid, nf90_global, "label_extended", trim(label_ext))
    status = nf90_put_att(ncid, nf90_global, "license", trim(license))
    status = nf90_put_att(ncid, nf90_global, "mip_era", trim(mip_era))
    status = nf90_put_att(ncid, nf90_global, "product", trim(product))
    if (len_trim(references) > 0) &
        status = nf90_put_att(ncid, nf90_global, "references", trim(references))
    status = nf90_put_att(ncid, nf90_global, "project_id", trim(project_id))
    status = nf90_put_att(ncid, nf90_global, "release_year", trim(release_year))
    status = nf90_put_att(ncid, nf90_global, "source", trim(source_desc))
    status = nf90_put_att(ncid, nf90_global, "source_id", trim(source_id))
    status = nf90_put_att(ncid, nf90_global, "source_type", trim(source_type))
    status = nf90_put_att(ncid, nf90_global, "title", trim(title_str))
    status = nf90_put_att(ncid, nf90_global, "tracking_id", trim(tracking))
    status = nf90_put_att(ncid, nf90_global, "variable_id", trim(varname))
    status = nf90_put_att(ncid, nf90_global, "version_realization", trim(version_real))
    status = nf90_put_att(ncid, nf90_global, "simulation_start_date", trim(sim_start_date))

    ! Numeric Attributes
    status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension", we_dim)
    status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension", sn_dim)
    status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension", bt_dim)
    status = nf90_put_att(ncid, nf90_global, "dx", dx_val)
    status = nf90_put_att(ncid, nf90_global, "dy", dy_val)

end subroutine write_global_attributes
!
!-----------------------------------------------------------------------
!
! File-name time range "<first>-<last>" from the first and last time values
! (in timeunits since <iniyear>-01-01): YYYYMMDDhhmm for sub-daily files,
! YYYYMMDD for daily and YYYYMM for monthly ones (CORDEX-CMIP6 file names).
!
function time_label(t1, t2) result(label)
    real, intent(in) :: t1, t2
    character(len=25) :: label
    label = trim(time_stamp(t1))//'-'//trim(time_stamp(t2))
end function time_label
!
! time_label of the first and the last of the n time values tt (variable calendar: n may be 0
! when no time step is left, e.g. a daily variable of a simulation shorter than a day)
function time_range(tt, n) result(label)
    real, dimension(:), intent(in) :: tt
    integer, intent(in) :: n
    character(len=25) :: label
    label = ''
    if (n >= 1) label = time_label(tt(1), tt(n))
end function time_range
!
!-----------------------------------------------------------------------
!
function time_stamp(t) result(stamp)
    real, intent(in) :: t
    character(len=12) :: stamp
    integer(kind=8) :: mins
    integer :: iy, days, y, m, d
    real(kind=8) :: tfac

    tfac = 1.d0
    if (timeunits(1:5) == 'hours') tfac = 24.d0
    read(ayearini,*) iy
    mins = nint(dble(t)/tfac*1440.d0, kind=8)
    days = days_from_civil(iy, 1, 1) + int(floor(dble(mins)/1440.d0))
    mins = modulo(mins, 1440_8)
    call civil_from_days(days, y, m, d)
    select case (trim(frequency))
    case ('day')
        write(stamp,'(i4.4,2i2.2)') y, m, d
    case ('mon')
        write(stamp,'(i4.4,i2.2)') y, m
    case default
        write(stamp,'(i4.4,4i2.2)') y, m, d, int(mins/60), int(mod(mins,60_8))
    end select
end function time_stamp
!
!-----------------------------------------------------------------------
!
! Number of output times of a sub-daily program in the months m1..m2 of year y, with an
! output every step hours from h0 UTC on the first day and from 00 UTC on the others
! (the loops "do hour = ihour, 23, wp_step" of the 3hr/6hr programs).
function n_time_steps(y, m1, m2, h0, step) result(n)
    integer, intent(in) :: y, m1, m2, h0, step
    integer :: n, nd
    nd = days_from_civil(merge(y + 1, y, m2 == 12), merge(1, m2 + 1, m2 == 12), 1) - days_from_civil(y, m1, 1)
    n = (nd - 1) * (24 / step) + (23 - h0) / step + 1
end function n_time_steps
!
!-----------------------------------------------------------------------
!
! Hours since <iniyear>-01-01 00 UTC of the date y-m-d h UTC (the time axis of the programs)
function hours_since_ini(y, m, d, h) result(hrs)
    integer, intent(in) :: y, m, d, h
    integer :: hrs
    hrs = 24 * (days_from_civil(y, m, d) - days_from_civil(iniyear, 1, 1)) + h
end function hours_since_ini
!
!-----------------------------------------------------------------------
!
! --- Variable calendar (programs of f90_src_varcalendar) ---
! The simulation period is set in the grid ini by sim_start and sim_end ('YYYY-MM-DD_HH',
! UTC: the first and the last wrfout file), and may start and end at any hour. A run
! processes the years yeari..yearf; each year is one chunk, the part of the year inside the
! simulation period, written to one file per variable:
!
!   do vc_year = yeari, yearf
!     if (.not. time_chunk(vc_year, step, interval)) cycle   ! no time step of this year
!     ... allocate(ttime(ntime), ...) ...
!     loop_h: do vc_ifl = 1, vc_nfiles
!       call set_time_step(vc_ifl)       ! year, month, day, hour, ayear ... ahour, infile
!       ...
!
! step: hours between the files read (1, or ostep for the programs that read every ostep
! hours). interval = .true. for values over the interval between two files (accumulated
! fields, interval means): the chunk then has the intervals [t, t + step] that start in the
! year, and the last one ends at sim_end; one more file is read than there are values.
!
function sim_time_hours(s, key) result(t)
! hours since iniyear-01-01 00 UTC of 'YYYY-MM-DD_HH' (namelist key key)
    character(len=*), intent(in) :: s, key
    integer :: t, y, m, d, h, ios, nd
    logical :: bad
    bad = len_trim(s) /= 13
    if (.not. bad) bad = s(5:5) /= '-' .or. s(8:8) /= '-' .or. s(11:11) /= '_'
    if (.not. bad) then
        read(s, '(i4,1x,i2,1x,i2,1x,i2)', iostat=ios) y, m, d, h
        bad = ios /= 0
    endif
    if (.not. bad) bad = m < 1 .or. m > 12 .or. h < 0 .or. h > 23
    if (.not. bad) then
        nd = days_from_civil(merge(y + 1, y, m == 12), merge(1, m + 1, m == 12), 1) - days_from_civil(y, m, 1)
        bad = d < 1 .or. d > nd
    endif
    if (bad) then
        print *, "ERROR: ", key, " = '", trim(s), "' in inputlist.inp: it must be 'YYYY-MM-DD_HH'", &
                 " (the grid ini of the experiment)"
        stop 95
    endif
    if (y < iniyear) then
        print *, "ERROR: ", key, " = '", trim(s), "' is before iniyear = ", iniyear
        stop 95
    endif
    t = hours_since_ini(y, m, d, h)
end function sim_time_hours
!
!-----------------------------------------------------------------------
!
subroutine sim_period
! checks sim_start and sim_end of the namelist and sets t_sim0, t_sim1 (hours since iniyear)
    if (len_trim(sim_start) == 0 .or. len_trim(sim_end) == 0) then
        print *, "ERROR: sim_start and sim_end ('YYYY-MM-DD_HH', the first and the last wrfout file)", &
                 " must be set in the grid ini for the programs of f90_src_varcalendar"
        stop 95
    endif
    t_sim0 = sim_time_hours(sim_start, 'sim_start')
    t_sim1 = sim_time_hours(sim_end, 'sim_end')
    if (t_sim1 < t_sim0) then
        print *, "ERROR: sim_end = '", sim_end, "' is before sim_start = '", sim_start, "'"
        stop 95
    endif
end subroutine sim_period
!
!-----------------------------------------------------------------------
!
logical function time_chunk(cy, step, interval)
! The chunk of year cy: sets t_ch0, t_ch1, ntime (time values), vc_nfiles (files to read),
! vc_step, vc_interval, and resets issh and ish (= t_ch0), and it for interval values (it = 0:
! the first file of the chunk, only read; in instantaneous programs it is a once-per-run
! flag, as in f90_src, and is left as it is). The first time step is the
! first multiple of step (from 00 UTC) at or after sim_start, the last one the last at or
! before sim_end (sim_end - step for interval values). .false. if the year has none.
! resample_time then drops the windows with missing time steps (rs_complete): a day,
! 6 hours or month that is not complete in the simulation period is not written.
    integer, intent(in) :: cy, step
    logical, intent(in) :: interval
    integer :: ty0, ty1
    call sim_period
    if (step < 1 .or. mod(24, step) /= 0) then
        print *, "ERROR: time_chunk: step = ", step, " hours must divide 24"
        stop 95
    endif
    ty0 = hours_since_ini(cy, 1, 1, 0)                 ! first and last hour of the year
    ty1 = hours_since_ini(cy + 1, 1, 1, 0) - 1
    t_ch0 = max(t_sim0, ty0)
    t_ch0 = t_ch0 + modulo(-t_ch0, step)               ! up to a multiple of step
    if (interval) then
        t_ch1 = min(t_sim1 - step, ty1)                  ! the last interval ends at sim_end
    else
        t_ch1 = min(t_sim1, ty1)
    endif
    t_ch1 = t_ch1 - modulo(t_ch1, step)                 ! down to a multiple of step
    if (t_ch1 >= t_ch0) then
        ntime = (t_ch1 - t_ch0) / step + 1
    else
        ntime = 0
    endif
    vc_step = step
    vc_interval = interval
    vc_nfiles = ntime + merge(1, 0, interval)
    rs_complete = .true.
    issh = 0
    if (interval) it = 0
    ish = t_ch0
    if (ntime > 0) then
        write(*,'(a,i4,a,a,a,a,a,i0,a,i0,a)') ' year ', cy, ': ', trim(hours_label(t_ch0)), ' to ', &
            trim(hours_label(t_ch1 + merge(step, 0, interval))), ', ', ntime, ' time steps (', vc_nfiles, ' files)'
    else
        write(*,'(a,i4,a,a,a,a,a)') ' year ', cy, ': outside the simulation period (', trim(sim_start), &
            ' to ', trim(sim_end), '), nothing to write'
    endif
    time_chunk = ntime > 0
end function time_chunk
!
!-----------------------------------------------------------------------
!
subroutine set_time_step(k)
! Date of file k (1 .. vc_nfiles) of the chunk, t_ch0 + (k - 1) vc_step: year, month, day,
! hour, ayear, amonth, aday, ahour, days (of that year), filename and infile (the wrfout file)
    integer, intent(in) :: k
    integer :: t
    t = t_ch0 + (k - 1) * vc_step
    call civil_from_days(days_from_civil(iniyear, 1, 1) + t / 24, year, month, day)
    hour = mod(t, 24)
    write(ayear, '(i4.4)') year
    amonth = pad_int(month, 2)
    aday = pad_int(day, 2)
    ahour = pad_int(hour, 2)
    if (mod(year, 4) == 0 .and. (mod(year, 100) /= 0 .or. mod(year, 400) == 0)) then
        days = days2
        mydays = 366
    else
        days = days1
        mydays = 365
    endif
    ndays = days(month)
    filename = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
    infile = trim(filename)
    if (k == 1 .or. (day == 1 .and. hour < vc_step)) write(*,*) year, month
end subroutine set_time_step
!
!-----------------------------------------------------------------------
!
function hours_label(t) result(label)
! 'YYYY-MM-DD_HH' of t hours since iniyear-01-01 00 UTC
    integer, intent(in) :: t
    character(len=13) :: label
    integer :: y, m, d
    call civil_from_days(days_from_civil(iniyear, 1, 1) + t / 24, y, m, d)
    write(label, '(i4.4,a,i2.2,a,i2.2,a,i2.2)') y, '-', m, '-', d, '_', mod(t, 24)
end function hours_label
!
!-----------------------------------------------------------------------
!
! Days since 1970-01-01 of a (proleptic Gregorian) date, and back.
pure function days_from_civil(yy, m, d) result(days)
    integer, intent(in) :: yy, m, d
    integer :: days, y, era, yoe, doy, doe
    y = yy
    if (m <= 2) y = y - 1
    era = merge(y, y - 399, y >= 0) / 400
    yoe = y - era*400
    doy = (153*mod(m + 9, 12) + 2)/5 + d - 1
    doe = yoe*365 + yoe/4 - yoe/100 + doy
    days = era*146097 + doe - 719468
end function days_from_civil
!
!-----------------------------------------------------------------------
!
pure subroutine civil_from_days(days_in, y, m, d)
    integer, intent(in)  :: days_in
    integer, intent(out) :: y, m, d
    integer :: days, era, doe, yoe, doy, mp
    days = days_in + 719468
    era = merge(days, days - 146096, days >= 0) / 146097
    doe = days - era*146097
    yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365
    y   = yoe + era*400
    doy = doe - (365*yoe + yoe/4 - yoe/100)
    mp  = (5*doy + 2)/153
    d   = doy - (153*mp + 2)/5 + 1
    m   = merge(mp + 3, mp - 9, mp < 10)
    if (m <= 2) y = y + 1
end subroutine civil_from_days
!
!-----------------------------------------------------------------------
!
! Current time in UTC as YYYY-MM-DDThh:mm:ssZ (date_and_time gives local
! time plus its offset from UTC, which is removed here).
!
subroutine utc_timestamp(stamp)
    character(len=20), intent(out) :: stamp
    integer :: v(8), days, mins, y, m, d

    call date_and_time(values=v)
    ! local date and minutes of the day, minus the UTC offset v(4) (minutes)
    mins = v(5)*60 + v(6) - v(4)
    days = days_from_civil(v(1), v(2), v(3)) + floor(real(mins)/1440.)
    mins = modulo(mins, 1440)
    call civil_from_days(days, y, m, d)
    write(stamp,'(i4.4,"-",i2.2,"-",i2.2,"T",i2.2,":",i2.2,":",i2.2,"Z")') &
          y, m, d, mins/60, mod(mins,60), v(7)
end subroutine utc_timestamp
!
!-----------------------------------------------------------------------
!
! tracking_id = "hdl:21.14103/" + a new random UUID (version 4) for every file.
! Uses the Linux kernel's UUID generator; falls back to random_number.
!
subroutine new_tracking_id(tid)
    character(len=49), intent(out) :: tid
    character(len=36) :: uuid
    character(len=16), parameter :: hexd = '0123456789abcdef'
    logical, save :: seeded = .false.
    integer :: u, ios, i, k
    real :: r

    uuid = ''
    open(newunit=u, file='/proc/sys/kernel/random/uuid', status='old', action='read', iostat=ios)
    if (ios == 0) then
        read(u,'(a36)', iostat=ios) uuid
        close(u)
    end if
    if (ios /= 0 .or. len_trim(uuid) /= 36) then
        if (.not. seeded) then
            call random_seed()
            seeded = .true.
        end if
        do i = 1, 36
            select case (i)
            case (9, 14, 19, 24)
                uuid(i:i) = '-'
            case (15)
                uuid(i:i) = '4'                        ! version 4
            case default
                call random_number(r)
                k = int(r*16.)
                if (i == 20) k = 8 + mod(k, 4)         ! variant 10xx
                uuid(i:i) = hexd(k+1:k+1)
            end select
        end do
    end if
    tid = 'hdl:21.14103/'//uuid
end subroutine new_tracking_id
!
!-----------------------------------------------------------------------
!
subroutine resample_time(fin, tin, bin, rs_hours, cmeth, fout, tout, bout, nout)
! Hourly values fin(:,:,i) at the times tin(i) (hours since iniyear; time bounds bin) ->
! values every rs_hours hours (3, 6, ... 24 = daily).
!  - cmeth with "time: point" and rs_hours < 24: the instantaneous values at the hours that
!    are multiples of rs_hours (no averaging);
!  - otherwise the mean (the sum for "time: sum") of the hourly values whose interval
!    starts in the window [k step, (k+1) step), with time = middle of the window and
!    bounds k step and (k+1) step. Missing values (1e20) are left out; a window with
!    only missing values is missing.
! The windows follow 00 UTC of the days (hours since iniyear-01-01 00:00).
use datvar_s
real, dimension(:,:,:), intent(in) :: fin
real, dimension(:), intent(in) :: tin
integer, dimension(:,:), intent(in) :: bin
integer, intent(in) :: rs_hours
character(len=*), intent(in) :: cmeth
real, dimension(:,:,:), allocatable, intent(out) :: fout
real, dimension(:), allocatable, intent(out) :: tout
integer, dimension(:,:), allocatable, intent(out) :: bout
integer, intent(out) :: nout
integer :: rs_step, rs_k0, rs_k, rs_i, rs_n, rs_j
logical :: rs_point, rs_sum
real, dimension(:,:), allocatable :: rs_cnt
!
rs_step = rs_hours
rs_point = index(cmeth, 'time: point') > 0 .and. rs_step < 24
rs_sum   = index(cmeth, 'time: sum') > 0
rs_n = size(tin)
if (rs_point) then
  nout = count(mod(nint(tin), rs_step) == 0)
  allocate(fout(size(fin,1), size(fin,2), nout), tout(nout), bout(2, nout))
  rs_j = 0
  do rs_i = 1, rs_n
    if (mod(nint(tin(rs_i)), rs_step) == 0) then
      rs_j = rs_j + 1
      fout(:,:,rs_j) = fin(:,:,rs_i)
      tout(rs_j) = tin(rs_i)
      bout(:,rs_j) = (/ nint(tin(rs_i)), nint(tin(rs_i)) + rs_step /)
    endif
  enddo
else
  rs_k0 = floor(real(bin(1,1)) / rs_step)
  nout = floor(real(bin(1,rs_n)) / rs_step) - rs_k0 + 1
  allocate(fout(size(fin,1), size(fin,2), nout), tout(nout), bout(2, nout))
  allocate(rs_cnt(size(fin,1), size(fin,2)))
  rs_j = 0
  do rs_i = 1, rs_n
    rs_k = floor(real(bin(1,rs_i)) / rs_step) - rs_k0 + 1
    if (rs_k /= rs_j) then                              ! a new window
      if (rs_j > 0) call close_window
      rs_j = rs_k
      fout(:,:,rs_j) = 0.
      rs_cnt = 0.
      tout(rs_j) = (rs_k0 + rs_j - 1) * rs_step + 0.5 * rs_step
      bout(:,rs_j) = (/ (rs_k0 + rs_j - 1) * rs_step, (rs_k0 + rs_j) * rs_step /)
    endif
    where (fin(:,:,rs_i) < 1.e19)
      fout(:,:,rs_j) = fout(:,:,rs_j) + fin(:,:,rs_i)
      rs_cnt = rs_cnt + 1.
    endwhere
  enddo
  call close_window
  deallocate(rs_cnt)
  if (rs_complete) call drop_partial_windows
endif
!
contains
  subroutine drop_partial_windows
  ! variable calendar: keep only the windows with all their time steps (rs_step / the step
  ! of the input, counted from the input time bounds), e.g. not the last day of a
  ! simulation that ends at 18 UTC
  integer :: rs_din, rs_m
  integer, allocatable :: rs_nin(:)
  logical, allocatable :: rs_keep(:)
  real, dimension(:,:,:), allocatable :: rs_f
  real, dimension(:), allocatable :: rs_t
  integer, dimension(:,:), allocatable :: rs_b
  rs_din = max(bin(2,1) - bin(1,1), 1)
  allocate(rs_nin(nout), rs_keep(nout))
  rs_nin = 0
  do rs_i = 1, rs_n
    rs_k = floor(real(bin(1,rs_i)) / rs_step) - rs_k0 + 1
    rs_nin(rs_k) = rs_nin(rs_k) + 1
  enddo
  rs_keep = rs_nin * rs_din >= rs_step
  if (all(rs_keep)) return
  rs_m = count(rs_keep)
  write(*,'(a,i0,a,i0,a)') ' resample_time: ', nout - rs_m, ' incomplete ', rs_step, &
                           '-hour window(s) left out (start or end of the simulation)'
  allocate(rs_f(size(fout,1), size(fout,2), rs_m), rs_t(rs_m), rs_b(2, rs_m))
  rs_j = 0
  do rs_i = 1, nout
    if (.not. rs_keep(rs_i)) cycle
    rs_j = rs_j + 1
    rs_f(:,:,rs_j) = fout(:,:,rs_i)
    rs_t(rs_j) = tout(rs_i)
    rs_b(:,rs_j) = bout(:,rs_i)
  enddo
  call move_alloc(rs_f, fout)
  call move_alloc(rs_t, tout)
  call move_alloc(rs_b, bout)
  nout = rs_m
  end subroutine drop_partial_windows
!
  subroutine close_window
  where (rs_cnt > 0.)
    fout(:,:,rs_j) = merge(fout(:,:,rs_j), fout(:,:,rs_j) / max(rs_cnt, 1.), rs_sum)
  elsewhere
    fout(:,:,rs_j) = 1.e+20
  endwhere
  end subroutine close_window
end subroutine resample_time
!
!-----------------------------------------------------------------------
!
subroutine resample_output
! The variable of the header at its output step ostep (outstep of the header, or wp_step
! for outstep = 0) when that is longer than 1 hour: outvar_h, ttime, bdtime and ntime are
! replaced by the resampled ones (resample_time) and freq is set ('<ostep>hr' or 'day').
! Nothing is done for hourly output (ostep = 1) or without outstep in the header.
use datvar_s
!
if (ostep <= 1) return
! only the time steps filled (issh; a run of fewer months leaves the rest of the year empty)
if (issh < 1 .or. issh > ntime) issh = ntime
call resample_time(outvar_h(:,:,1:issh), ttime(1:issh), bdtime(:,1:issh), ostep, cellmethods, &
                   outvar_r, ttime_r, bdtime_r, nt_r)
call move_alloc(outvar_r, outvar_h)
call move_alloc(ttime_r, ttime)
call move_alloc(bdtime_r, bdtime)
ntime = nt_r
if (ostep == 24) then
  freq = 'day'
else
  write(freq,'(i0,a)') ostep, 'hr'
endif
write(*,*) trim(vaid), ': written at ', trim(freq), ' (outstep ', outstep, ')'
!
end subroutine resample_output
!
!-----------------------------------------------------------------------
!
subroutine plev_map(pr, pl)
! Map of the model levels that bracket the pressure level pl (Pa): plev_k(ix,iy) = k
! with pr(k) >= pl > pr(k+1), and the log(p) weight plev_w of level k+1, used by
! plev_interp. Pressure is smooth in the horizontal, so the level of the previous point
! (the point to the west; at the start of a row, the first point of the row below) is
! the first guess, and the search walks from it: down (k-1) while pr(k) < pl, up (k+1)
! while pr(k+1) >= pl - usually 0 to 2 steps. Points where pl is below the surface
! (pr(1) < pl) or above the model top (pr(nz) >= pl) get plev_k = 0 (missing).
! If the walk does not end within nz steps (non-monotonic column), the column is
! scanned from the bottom, as the earlier RCM_plev programs did.
! The map is kept for the next call (the next time step): the search of the first point
! starts from its level of the previous time step (else from the last level found then).
! plev_k1..plev_k2 (plev_nk levels) are the model levels plev_interp needs, k and k+1 of
! every point: the programs read and compute their fields only on these levels.
use datvar_s
real, dimension(nlon,nlat,nz), intent(in) :: pr
real, intent(in) :: pl
integer :: pm_i, pm_j, pm_k
!
if (.not. allocated(plev_k)) then
  allocate(plev_k(nlon,nlat), plev_w(nlon,nlat))
  plev_k = 0
  plev_kg = 1
endif
! first guess of the first point: its level of the previous time step
if (plev_k(1,1) > 0) plev_kg = plev_k(1,1)
plev_k = 0
plev_w = 0.
plev_steps = 0
plev_scan = 0
do pm_j = 1, nlat
  if (pm_j > 1) then
    if (plev_k(1,pm_j-1) > 0) plev_kg = plev_k(1,pm_j-1)
  endif
  do pm_i = 1, nlon
    if (pr(pm_i,pm_j,1) < pl .or. pr(pm_i,pm_j,nz) >= pl) cycle      ! below ground / above top
    pm_k = max(1, min(nz-1, plev_kg))
    walk: do plev_it = 1, nz
      if (pr(pm_i,pm_j,pm_k) < pl) then
        pm_k = pm_k - 1
      else if (pr(pm_i,pm_j,pm_k+1) >= pl) then
        pm_k = pm_k + 1
      else
        exit walk
      endif
      plev_steps = plev_steps + 1
      if (pm_k < 1 .or. pm_k > nz-1) exit walk
    enddo walk
    if (pm_k < 1 .or. pm_k > nz-1 .or. plev_it > nz) then
      ! not monotonic: first bracket from the bottom
      plev_scan = plev_scan + 1
      pm_k = 0
      do plev_it = 1, nz-1
        if (pr(pm_i,pm_j,plev_it) >= pl .and. pr(pm_i,pm_j,plev_it+1) < pl) then
          pm_k = plev_it
          exit
        endif
      enddo
      if (pm_k == 0) cycle
    endif
    plev_k(pm_i,pm_j) = pm_k
    plev_w(pm_i,pm_j) = (log(pr(pm_i,pm_j,pm_k)) - log(pl)) / (log(pr(pm_i,pm_j,pm_k)) - log(pr(pm_i,pm_j,pm_k+1)))
    plev_kg = pm_k
  enddo
enddo
! the levels plev_interp needs (1 level if pl is below the ground or above the top everywhere)
if (any(plev_k > 0)) then
  plev_k1 = minval(plev_k, mask = plev_k > 0)
  plev_k2 = maxval(plev_k) + 1
else
  plev_k1 = 1
  plev_k2 = 1
endif
plev_nk = plev_k2 - plev_k1 + 1
!
end subroutine plev_map
!
!-----------------------------------------------------------------------
!
subroutine zlev_map(zh, hl, kz)
! Map of the model levels that bracket the height hl (m above the ground): zlev_k(ix,iy) = k
! with zh(k) < hl <= zh(k+1), zh the height of the mass levels above the ground (from PH,
! PHB and HGT). zlev_k = 0 (missing) where hl is not above the lowest model level
! (zh(1) >= hl) or is above the top (zh(nz) < hl): the same brackets as the search from the
! bottom of the earlier RCM_zlev programs, which the programs use with their own
! interpolation (linear in z, or the power law of the winds).
! Height is smooth in the horizontal, so the level of the previous point (the point to the
! west; at the start of a row, the first point of the row below) is the first guess, and
! the search walks from it: down (k-1) while zh(k) >= hl, up (k+1) while zh(k+1) < hl.
! If the walk does not end within nz steps (non-monotonic column), the column is searched
! from the bottom as before. The map is kept for the next call (the next time step): the
! search of the first point starts from its level of the previous time step.
! zlev_k1..zlev_k2 (zlev_nk levels) are the model levels the interpolation needs, k and k+1
! of every point: the programs read and compute their fields only on these levels.
! kz (optional, default nz): zh is known on the levels 1..kz only (kz <= nz; zlev_heights),
! and kz takes the place of nz as the top of the column.
use datvar_s
real, dimension(nlon,nlat,nz), intent(in) :: zh
real, intent(in) :: hl
integer, intent(in), optional :: kz
integer :: zm_i, zm_j, zm_k, zm_kz
!
zm_kz = nz
if (present(kz)) zm_kz = kz
if (.not. allocated(zlev_k)) then
  allocate(zlev_k(nlon,nlat))
  zlev_k = 0
  zlev_kg = 1
endif
! first guess of the first point: its level of the previous time step
if (zlev_k(1,1) > 0) zlev_kg = zlev_k(1,1)
zlev_k = 0
zlev_steps = 0
zlev_scan = 0
do zm_j = 1, nlat
  if (zm_j > 1) then
    if (zlev_k(1,zm_j-1) > 0) zlev_kg = zlev_k(1,zm_j-1)
  endif
  do zm_i = 1, nlon
    if (zh(zm_i,zm_j,1) >= hl .or. zh(zm_i,zm_j,zm_kz) < hl) cycle      ! not above level 1 / above the top
    zm_k = max(1, min(zm_kz-1, zlev_kg))
    walk: do zlev_it = 1, nz
      if (zh(zm_i,zm_j,zm_k) >= hl) then
        zm_k = zm_k - 1
      else if (zh(zm_i,zm_j,zm_k+1) < hl) then
        zm_k = zm_k + 1
      else
        exit walk
      endif
      zlev_steps = zlev_steps + 1
      if (zm_k < 1 .or. zm_k > zm_kz-1) exit walk
    enddo walk
    if (zm_k < 1 .or. zm_k > zm_kz-1 .or. zlev_it > nz) then
      ! not monotonic: the search from the bottom of the earlier programs
      zlev_scan = zlev_scan + 1
      zm_k = 0
      do zlev_it = 1, zm_kz-1
        if (zh(zm_i,zm_j,zlev_it) > hl) exit
        if (zh(zm_i,zm_j,zlev_it+1) >= hl .and. zh(zm_i,zm_j,zlev_it) < hl) then
          zm_k = zlev_it
          exit
        endif
      enddo
      if (zm_k == 0) cycle
    endif
    zlev_k(zm_i,zm_j) = zm_k
    zlev_kg = zm_k
  enddo
enddo
! the levels the interpolation needs (1 level if hl is missing everywhere)
if (any(zlev_k > 0)) then
  zlev_k1 = minval(zlev_k, mask = zlev_k > 0)
  zlev_k2 = maxval(zlev_k) + 1
else
  zlev_k1 = 1
  zlev_k2 = 1
endif
zlev_nk = zlev_k2 - zlev_k1 + 1
!
end subroutine zlev_map
!
!-----------------------------------------------------------------------
!
subroutine zlev_heights(hl)
! The heights above the ground of the mass levels, zhgt = (phi(k) + phi(k+1)) / 2 - hgt with
! phi = (PH + PHB) / g, and the map of the levels that bracket the height hl (zlev_map), for
! the open wrfout file (ncid and infile of datvar_s; hgt read by the program).
! After the first time step, PH and PHB are read only up to the face above the mass level
! zlev_kz = zlev_k2 + 1 of the previous step's map (at most nz). If a point that is above
! level 1 might need a higher level (zhgt(zlev_kz) <= hl), they are read again up to nz
! (zlev_nfull counts these steps). The map, and so the results, are then those of a read of
! all nz levels: with zhgt(zlev_kz) > hl, the bracket of every point is below zlev_kz.
use datvar_s
use netcdf
real, intent(in) :: hl
integer :: zh_st, zh_vid
!
if (.not. allocated(ph)) allocate(ph(nlon,nlat,nzt), phb(nlon,nlat,nzt), phi(nlon,nlat,nzt))
if (allocated(zlev_k)) then
  zlev_kz = min(nz, zlev_k2 + 1)
else
  zlev_kz = nz                                  ! first time step: every level
endif
call read_ph(zlev_kz)
if (zlev_kz < nz) then
  if (any(zhgt(:,:,1) < hl .and. zhgt(:,:,zlev_kz) <= hl)) then
    zlev_nfull = zlev_nfull + 1
    if (zlev_nfull <= 3 .or. mod(zlev_nfull, 1000) == 0) &
      write(*,'(a,i0,a,i0,a,i0,a)') ' zlev_heights: PH and PHB read again up to level ', nz, &
        ' (', zlev_kz, ' were not enough; ', zlev_nfull, ' time steps so far)'
    zlev_kz = nz
    call read_ph(zlev_kz)
  endif
endif
call zlev_map(zhgt, hl, zlev_kz)
!
contains
  subroutine read_ph(kk)
  ! PH and PHB on the faces 1..kk+1, and zhgt on the mass levels 1..kk
  integer, intent(in) :: kk
  integer :: zh_k
  zh_st = nf90_inq_varid(ncid, 'PH', zh_vid)
  call ncerror(zh_st,'getting var id PH in '//trim(infile))
  zh_st = nf90_get_var(ncid, zh_vid, ph(:,:,1:kk+1), (/xoffset, yoffset, 1/), (/nlon, nlat, kk+1/))
  call ncerror(zh_st,'reading PH from '//trim(infile))
  zh_st = nf90_inq_varid(ncid, 'PHB', zh_vid)
  call ncerror(zh_st,'getting var id PHB in '//trim(infile))
  zh_st = nf90_get_var(ncid, zh_vid, phb(:,:,1:kk+1), (/xoffset, yoffset, 1/), (/nlon, nlat, kk+1/))
  call ncerror(zh_st,'reading PHB from '//trim(infile))
  phi(:,:,1:kk+1) = (ph(:,:,1:kk+1) + phb(:,:,1:kk+1)) / g
  do zh_k = 1, kk
    zhgt(:, :, zh_k) = ((phi(:, :, zh_k) + phi(:, :, zh_k+1)) / 2.) - hgt(:, :)
  enddo
  end subroutine read_ph
end subroutine zlev_heights
!
!-----------------------------------------------------------------------
!
subroutine plev_interp(f3d, f2d)
! f3d on the model levels -> f2d on the pressure level of the last plev_map, linear in
! log(p): f2d = f3d(k) + plev_w (f3d(k+1) - f3d(k)); missing (1e20) where plev_k = 0
use datvar_s
real, dimension(nlon,nlat,nz), intent(in) :: f3d
real, dimension(nlon,nlat), intent(out) :: f2d
integer :: pm_i, pm_j, pm_k
!
do pm_j = 1, nlat
  do pm_i = 1, nlon
    pm_k = plev_k(pm_i,pm_j)
    if (pm_k > 0) then
      f2d(pm_i,pm_j) = f3d(pm_i,pm_j,pm_k) + plev_w(pm_i,pm_j) * (f3d(pm_i,pm_j,pm_k+1) - f3d(pm_i,pm_j,pm_k))
    else
      f2d(pm_i,pm_j) = 1.e+20
    endif
  enddo
enddo
!
end subroutine plev_interp
!
!-----------------------------------------------------------------------
!
subroutine handle_err(status)
use netcdf
integer, intent ( in) :: status

if(status /= nf90_noerr) then
  print*, trim(nf90_strerror(status))
  stop 98
end if
end subroutine handle_err
!
!-----------------------------------------------------------------------
!
end module shared_subs

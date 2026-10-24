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
! MODIFIED_IGBP_MODIS_NOAH or USGS), used by urban_cell
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
logical elemental function urban_cell(frc, lu)
! .true. where WRF runs the urban scheme: urban fraction > 0 and the dominant land-use
! category (LU_INDEX) urban, for the land-use table of the geo_em file (read_geog):
!   MODIFIED_IGBP_MODIS_NOAH: 13, or the LCZ classes 51-61
!   USGS:                      1, or the LCZ classes 31-41
real, intent(in) :: frc, lu
integer :: k
k = nint(lu)
if (lu_usgs) then
  urban_cell = frc > 0. .and. (k == 1 .or. (k >= 31 .and. k <= 41))
else
  urban_cell = frc > 0. .and. (k == 13 .or. (k >= 51 .and. k <= 61))
endif
end function urban_cell
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
endif
!
contains
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
use datvar_s
real, dimension(nlon,nlat,nz), intent(in) :: pr
real, intent(in) :: pl
integer :: pm_i, pm_j, pm_k
!
if (.not. allocated(plev_k)) allocate(plev_k(nlon,nlat), plev_w(nlon,nlat))
plev_k = 0
plev_w = 0.
plev_kg = 1
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
!
end subroutine plev_map
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
subroutine landuse_field(fname, lu_out)
! Land-cover fraction (% of the grid cell) or dominant category of the variable vaid,
! from LANDUSEF / LU_INDEX of the wrfout file fname (RCM_fx_landuse, RCM_sfc_landuse):
!   treeFrac, shrubFrac, grassFrac, cropFrac, baresoilFrac, urbanFrac: 100 * sum over
!   the categories k of w(k) LANDUSEF(k), with the weight tables below (edit them to
!   change the grouping; a mosaic class may be split); cnc: tree+shrub+grass+crop (also
!   for albc, the canopy albedo of RCM_sfc_albc);
!   treeFracBdlDcd, treeFracBdlEvg, treeFracNdlDcd, treeFracNdlEvg: the pure forest
!   classes of each leaf type and phenology (mixed forest and the mosaics in none);
!   residualFrac: land neither vegetated nor bare (urban, incl. LCZ, and snow/ice);
!   pastureFrac: the grassland class (MODIS 10, USGS 7), taken as pasture (the tables have
!   no pasture class; it is also part of grassFrac);
!   lcvr: LU_INDEX. Water, snow/ice and ungrouped wetland count in none of the others.
! The table follows the MMINLU attribute of the file: MODIFIED_IGBP_MODIS_NOAH
! (LCZ urban classes 51-61) or USGS (LCZ 31-41). No sea mask.
use netcdf
character(len=*), intent(in) :: fname
real, dimension(nlon,nlat), intent(out) :: lu_out
integer, parameter :: lu_max = 61
real, dimension(:,:), allocatable :: lu_f
real, dimension(lu_max) :: lu_w
real, dimension(24) :: g
integer :: lu_ncat, lu_dimid, k, lu_ncid, lu_varid, lu_st, lcz1
character(len=80) :: lu_scheme
logical :: lu_modis
logical, save :: lu_told = .false.
!
! weights per category, MODIFIED_IGBP_MODIS_NOAH:
!  1 evergreen needleleaf  2 evergreen broadleaf  3 deciduous needleleaf  4 deciduous broadleaf
!  5 mixed forest  6 closed shrubland  7 open shrubland  8 woody savanna  9 savanna  10 grassland
! 11 permanent wetland  12 cropland  13 urban  14 cropland/natural vegetation mosaic  15 snow and ice
! 16 barren  17 water  18 wooded tundra  19 mixed tundra  20 barren tundra  21 lakes  51-61 LCZ (urban)
integer, dimension(21), parameter :: &
  md_tree  = [1,1,1,1,1, 0,0,1,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_shrub = [0,0,0,0,0, 1,1,0,0,0, 0,0,0,0,0, 0,0,1,0,0, 0], &
  md_grass = [0,0,0,0,0, 0,0,0,1,1, 1,0,0,0,0, 0,0,0,1,0, 0], &
  md_crop  = [0,0,0,0,0, 0,0,0,0,0, 0,1,0,1,0, 0,0,0,0,0, 0], &
  md_bare  = [0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 1,0,0,0,1, 0], &
  md_urban = [0,0,0,0,0, 0,0,0,0,0, 0,0,1,0,0, 0,0,0,0,0, 0], &
  md_ndlevg= [1,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_bdlevg= [0,1,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_ndldcd= [0,0,1,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_bdldcd= [0,0,0,1,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_resid = [0,0,0,0,0, 0,0,0,0,0, 0,0,1,0,1, 0,0,0,0,0, 0], &
  md_past  = [0,0,0,0,0, 0,0,0,0,1, 0,0,0,0,0, 0,0,0,0,0, 0]
!
! weights per category, USGS:
!  1 urban  2 dryland crop  3 irrigated crop  4 mixed dry/irrigated crop  5 crop/grassland mosaic
!  6 crop/woodland mosaic  7 grassland  8 shrubland  9 mixed shrub/grassland  10 savanna
! 11-14 forests  15 mixed forest  16 water  17 herbaceous wetland  18 wooded wetland  19 barren
! 20 herbaceous tundra  21 wooded tundra  22 mixed tundra  23 bare ground tundra  24 snow or ice
! 31-41 LCZ (urban)
real, dimension(24), parameter :: &
  us_tree  = [0.,0.,0.,0.,0., .5,0.,0.,0.,0., 1.,1.,1.,1.,1., 0.,0.,1.,0.,0., 0.,0.,0.,0.], &
  us_shrub = [0.,0.,0.,0.,0., 0.,0.,1.,.5,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 1.,1.,0.,0.], &
  us_grass = [0.,0.,0.,0.,.5, 0.,1.,0.,.5,1., 0.,0.,0.,0.,0., 0.,1.,0.,0.,1., 0.,0.,0.,0.], &
  us_crop  = [0.,1.,1.,1.,.5, .5,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_bare  = [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,1.,0., 0.,0.,1.,0.], &
  us_urban = [1.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_bdldcd= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 1.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_ndldcd= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,1.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_bdlevg= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,1.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_ndlevg= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,1.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_resid = [1.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,1.], &
  us_past  = [0.,0.,0.,0.,0., 0.,1.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.]
!
lu_st = nf90_open(trim(fname), nf90_nowrite, lu_ncid)
call ncerror(lu_st,'opening '//trim(fname))
!
if (trim(vaid) == 'lcvr') then
  lu_st=nf90_inq_varid(lu_ncid,'LU_INDEX',lu_varid)
  call ncerror(lu_st,'getting var id LU_INDEX in '//trim(fname))
  lu_st=nf90_get_var(lu_ncid,lu_varid,lu_out,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
  call ncerror(lu_st,'reading LU_INDEX from '//trim(fname))
  lu_out = real(nint(lu_out))
else
  lu_scheme = ''
  lu_st = nf90_get_att(lu_ncid, nf90_global, 'MMINLU', lu_scheme)
  lu_modis = (index(lu_scheme, 'USGS') == 0)
  if (lu_st /= nf90_noerr) lu_scheme = 'MODIFIED_IGBP_MODIS_NOAH (no MMINLU attribute: assumed)'
!
  lu_st=nf90_inq_varid(lu_ncid,'LANDUSEF',lu_varid)
  call ncerror(lu_st,'getting var id LANDUSEF in '//trim(fname))
  lu_st=nf90_inq_dimid(lu_ncid,'land_cat_stag',lu_dimid)
  if (lu_st /= nf90_noerr) lu_st=nf90_inq_dimid(lu_ncid,'land_cat',lu_dimid)
  call ncerror(lu_st,'getting the land_cat dimension in '//trim(fname))
  lu_st=nf90_inquire_dimension(lu_ncid,lu_dimid,len=lu_ncat)
  call ncerror(lu_st,'reading the land_cat dimension from '//trim(fname))
!
! weights lu_w(k) of the category k for the group of vaid
  lu_w = 0.
  g = 0.
  if (lu_modis) then
    lcz1 = 51
    select case (trim(vaid))
      case ('treeFrac');     g(1:21) = md_tree
      case ('shrubFrac');    g(1:21) = md_shrub
      case ('grassFrac');    g(1:21) = md_grass
      case ('cropFrac');     g(1:21) = md_crop
      case ('baresoilFrac'); g(1:21) = md_bare
      case ('urbanFrac');    g(1:21) = md_urban
      case ('cnc', 'albc');  g(1:21) = md_tree + md_shrub + md_grass + md_crop
      case ('treeFracBdlDcd'); g(1:21) = md_bdldcd
      case ('treeFracBdlEvg'); g(1:21) = md_bdlevg
      case ('treeFracNdlDcd'); g(1:21) = md_ndldcd
      case ('treeFracNdlEvg'); g(1:21) = md_ndlevg
      case ('residualFrac');   g(1:21) = md_resid
      case ('pastureFrac');    g(1:21) = md_past
      case default
        print *, 'ERROR: landuse_field does not know the variable ', trim(vaid)
        stop 95
    end select
    lu_w(1:21) = g(1:21)
  else
    lcz1 = 31
    select case (trim(vaid))
      case ('treeFrac');     g = us_tree
      case ('shrubFrac');    g = us_shrub
      case ('grassFrac');    g = us_grass
      case ('cropFrac');     g = us_crop
      case ('baresoilFrac'); g = us_bare
      case ('urbanFrac');    g = us_urban
      case ('cnc', 'albc');  g = us_tree + us_shrub + us_grass + us_crop
      case ('treeFracBdlDcd'); g = us_bdldcd
      case ('treeFracBdlEvg'); g = us_bdlevg
      case ('treeFracNdlDcd'); g = us_ndldcd
      case ('treeFracNdlEvg'); g = us_ndlevg
      case ('residualFrac');   g = us_resid
      case ('pastureFrac');    g = us_past
      case default
        print *, 'ERROR: landuse_field does not know the variable ', trim(vaid)
        stop 95
    end select
    lu_w(1:24) = g
  endif
  ! LCZ urban classes (11 of them), when the file has them
  if (trim(vaid) == 'urbanFrac' .or. trim(vaid) == 'residualFrac') lu_w(lcz1:lcz1+10) = 1.
!
  allocate(lu_f(nlon,nlat))
  lu_out = 0.
  do k = 1, min(lu_ncat, lu_max)
    if (lu_w(k) > 0.) then
      ! only the categories of this group are read (one 2-D slice each)
      lu_st=nf90_get_var(lu_ncid,lu_varid,lu_f,(/xoffset,yoffset,k,1/),(/nlon,nlat,1,1/),(/1,1,1,1/))
      call ncerror(lu_st,'reading LANDUSEF from '//trim(fname))
      lu_out = lu_out + lu_w(k) * lu_f
    endif
  enddo
  lu_out = 100. * lu_out
  where (lu_out > 100.) lu_out = 100.
  where (lu_out < 1.e-4) lu_out = 0.
  lu_out = real(nint(1.d4 * lu_out, 8)) / 1.e4
  deallocate(lu_f)
  if (.not. lu_told) write(*,*) trim(vaid), ' from LANDUSEF, land-use table ', trim(lu_scheme)
  lu_told = .true.
endif
!
lu_st = nf90_close(lu_ncid)
call ncerror(lu_st,'closing '//trim(fname))
!
end subroutine landuse_field
!
!-----------------------------------------------------------------------
!
! ---------------------------------------------------------------------------------------
! Moist thermodynamics of a lifted parcel (RCM_sfc_cape): saturation mixing ratio,
! virtual temperature, exact LCL (Romps 2017), pseudo-equivalent potential temperature
! (Bolton 1980, eq. 43) and its inversion. Double precision.
! ---------------------------------------------------------------------------------------
!
pure function qvs_wexler(tk, pa) result(qs)
! saturation mixing ratio (kg kg-1) over water at tk (K) and pa (Pa): ITS-90 / Wexler
! saturation vapour pressure with the enhancement factor of Hardy (1998) (es_wexler_dt),
! as RCM_sfc_hurs and RCM_sfc_hurscan
real(kind=8), intent(in) :: tk, pa
real(kind=8) :: qs, dqs
call qvs_wexler_dt(tk, pa, qs, dqs)
end function qvs_wexler
!
!-----------------------------------------------------------------------
!
pure subroutine es_wexler_dt(tk, pa, es, des)
! saturation vapour pressure es (Pa) over water at tk (K) in moist air at pa (Pa) and its
! exact derivative des = d es / d tk (Pa K-1): ITS-90 formula of Wexler (1976) for water,
! times the enhancement factor of moist air (Greenspan 1976, ITS-90 coefficients of Hardy
! 1998: water 0 to 100 degC, and supercooled water -50 to 0 degC below 0 degC)
!   f = exp[ fa (1 - ew/pa) + exp(fb) (pa/ew - 1) ],  fa, fb cubics in t (degC)
! (f ~ 1.004 at 20 degC and 1000 hPa). Used by RCM_sfc_hurs, RCM_sfc_hurscan,
! qvs_wexler_dt (CAPE) and RCM_sfc_evspsblpot (Penman-Monteith es and its slope).
real(kind=8), intent(in) :: tk, pa
real(kind=8), intent(out) :: es, des
real(kind=8) :: dlnes, tc, fa, dfa, fb, dfb, eb, fact, dlnf, ew
real(kind=8), parameter :: a1=-2.8365744d3, a2=-6.028076559d3, a3=19.54263612d0, a4=-2.737830188d-2, &
                           a5=1.6261698d-5, a6=7.0229056d-10, a7=-1.8680009d-13, a8=2.7150305d0
real(kind=8), parameter :: fi1=3.62183d-4, fi2=2.6061244d-5, fi3=3.8667770d-7, fi4=3.8268958d-9, &
                           fi5=-10.7604d0, fi6=6.3987441d-2, fi7=-2.6351566d-4, fi8=1.6725084d-6
real(kind=8), parameter :: fw1=3.536240d-4, fw2=2.932836d-5, fw3=2.616898d-7, fw4=8.581361d-9, &
                           fw5=-10.75880d0, fw6=6.326813d-2, fw7=-2.536893d-4, fw8=6.340529d-7
tc = tk - 273.15d0
! Wexler / ITS-90 saturation vapour pressure and d ln(es) / dT
ew = exp(a1/tk**2 + a2/tk + a3 + a4*tk + a5*tk**2 + a6*tk**3 + a7*tk**4 + a8*log(tk))
dlnes = -2.d0*a1/tk**3 - a2/tk**2 + a4 + 2.d0*a5*tk + 3.d0*a6*tk**2 + 4.d0*a7*tk**3 + a8/tk
! enhancement factor: ln f = fa (1 - ew/pa) + exp(fb) (pa/ew - 1), fa and fb cubics in tc
if (tc < 0.d0) then                      ! supercooled water (Hardy 1998, -50 to 0 degC)
  fa  = fi1 + fi2*tc + fi3*tc**2 + fi4*tc**3
  dfa = fi2 + 2.d0*fi3*tc + 3.d0*fi4*tc**2
  fb  = fi5 + fi6*tc + fi7*tc**2 + fi8*tc**3
  dfb = fi6 + 2.d0*fi7*tc + 3.d0*fi8*tc**2
else
  fa  = fw1 + fw2*tc + fw3*tc**2 + fw4*tc**3
  dfa = fw2 + 2.d0*fw3*tc + 3.d0*fw4*tc**2
  fb  = fw5 + fw6*tc + fw7*tc**2 + fw8*tc**3
  dfb = fw6 + 2.d0*fw7*tc + 3.d0*fw8*tc**2
endif
eb   = exp(fb)
fact = exp(fa*(1.d0 - ew/pa) + eb*(pa/ew - 1.d0))
! d ln f / dT, with d ew / dT = ew dlnes
dlnf = dfa*(1.d0 - ew/pa) + eb*dfb*(pa/ew - 1.d0) - fa*ew*dlnes/pa - eb*(pa/ew)*dlnes
es  = ew*fact
des = es*(dlnes + dlnf)
end subroutine es_wexler_dt
!
!-----------------------------------------------------------------------
!
pure subroutine qvs_wexler_dt(tk, pa, qs, dqs)
! qvs_wexler and its exact derivative dqs = d qs / d tk (kg kg-1 K-1), for Newton
! iterations (t_from_theta_e); es and its derivative from es_wexler_dt
real(kind=8), intent(in) :: tk, pa
real(kind=8), intent(out) :: qs, dqs
real(kind=8) :: es, des
call es_wexler_dt(tk, pa, es, des)
if (es > 0.5d0*pa) then                  ! capped (very hot or low pressure): flat
  es = 0.5d0*pa; des = 0.d0
endif
qs  = epsilon*es/(pa - es)
dqs = epsilon*pa*des/(pa - es)**2
end subroutine qvs_wexler_dt
!
!-----------------------------------------------------------------------
!
pure function tvirt(tk, r) result(tv)
! virtual temperature (K) from the temperature and the mixing ratio r (kg kg-1)
real(kind=8), intent(in) :: tk, r
real(kind=8) :: tv
tv = tk*(1.d0 + r/epsilon)/(1.d0 + r)
end function tvirt
!
!-----------------------------------------------------------------------
!
pure function lambertw_m1(x) result(w)
! real Lambert W function, lower branch W_-1, for -1/e <= x < 0 (Halley iterations)
real(kind=8), intent(in) :: x
real(kind=8) :: w, ew, f, q, l1, l2
integer :: it
if (x <= -exp(-1.d0)) then
  w = -1.d0
  return
endif
if (x < -0.25d0) then
  q = -sqrt(2.d0*(1.d0 + exp(1.d0)*x))
  w = -1.d0 + q - q**2/3.d0 + 11.d0/72.d0*q**3
else
  l1 = log(-x); l2 = log(-l1)
  w = l1 - l2 + l2/l1
endif
do it = 1, 20
  ew = exp(w)
  f = w*ew - x
  q = w*ew + ew - (w + 2.d0)*f/(2.d0*w + 2.d0)
  if (abs(q) < 1.d-300) exit
  w = w - f/q
  if (abs(f) < 1.d-14*abs(x)) exit
enddo
end function lambertw_m1
!
!-----------------------------------------------------------------------
!
pure subroutine romps_lcl(pa, tk, r, zl, tl, pl)
! Exact lifting condensation level of a parcel (pressure pa, temperature tk, mixing
! ratio r), Romps (2017, J. Atmos. Sci. 74, 3891), liquid water:
!   zl: height of the LCL above the parcel (m), tl: its temperature (K), pl: pressure (Pa).
! A saturated (or supersaturated) parcel has its LCL at the parcel level.
real(kind=8), intent(in) :: pa, tk, r
real(kind=8), intent(out) :: zl, tl, pl
real(kind=8), parameter :: ttrip=273.16d0, ptrip=611.65d0, e0v=2.3740d6, ggr=9.81d0
real(kind=8), parameter :: rgasa=287.04d0, rgasv=461.d0, cva=719.d0, cvv=1418.d0, cvl=4119.d0
real(kind=8), parameter :: cpa=cva+rgasa, cpv=cvv+rgasv
real(kind=8) :: pv, qv, rgasm, cpm, al, bl, cl, pvs, arg, rh
pv = r*pa/(rgasa/rgasv + r)
qv = rgasa*pv/(rgasv*pa + (rgasa - rgasv)*pv)
rgasm = (1.d0 - qv)*rgasa + qv*rgasv
cpm = (1.d0 - qv)*cpa + qv*cpv
pvs = ptrip*(tk/ttrip)**((cpv - cvl)/rgasv)*exp((e0v - (cvv - cvl)*ttrip)/rgasv*(1.d0/ttrip - 1.d0/tk))
rh = pv/pvs
if (r <= 0.d0) then
  tl = 0.d0; zl = cpm*tk/ggr; pl = 0.d0
  return
endif
if (rh >= 1.d0) then
  zl = 0.d0; tl = tk; pl = pa
  return
endif
al = -(cpv - cvl)/rgasv + cpm/rgasm
bl = -(e0v - (cvv - cvl)*ttrip)/(rgasv*tk)
cl = bl/al
arg = rh**(1.d0/al)*cl*exp(cl)
tl = cl/lambertw_m1(arg)*tk
zl = cpm/ggr*(tk - tl)
pl = pa*(tl/tk)**(cpm/rgasm)
end subroutine romps_lcl
!
!-----------------------------------------------------------------------
!
pure function theta_e_bolton(tk, pa, r, tl) result(the)
! pseudo-equivalent potential temperature (K), Bolton (1980) eq. 43: tk, pa, r (kg kg-1)
! of the parcel and tl, its temperature at the LCL
real(kind=8), intent(in) :: tk, pa, r, tl
real(kind=8) :: the, rg
rg = 1000.d0*r
the = tk*(1.d5/pa)**(0.2854d0*(1.d0 - 0.28d-3*rg))*exp((3.376d0/tl - 0.00254d0)*rg*(1.d0 + 0.81d-3*rg))
end function theta_e_bolton
!
!-----------------------------------------------------------------------
!
pure function t_from_theta_e(the, pa, tguess) result(tk)
! temperature (K) of a saturated parcel at pa (Pa) with pseudo-equivalent potential
! temperature the: Newton iterations on ln theta_e_bolton(T, pa, qvs(T, pa), T) = ln the,
! starting from tguess (the parcel temperature at the level below). The derivative is
! exact (qvs_wexler_dt), so each iteration needs one saturation evaluation.
!   ln theta_e = ln T + kap ln(p0/p) + (3.376/T - 0.00254) rg (1 + 0.81e-3 rg)
!   kap = 0.2854 (1 - 0.28e-3 rg), rg = 1000 qs(T, p) (g kg-1)
real(kind=8), intent(in) :: the, pa, tguess
real(kind=8) :: tk, qs, dqs, rg, drg, lnp, aa, f0, f1, dt
integer :: it
tk = tguess
lnp = log(1.d5/pa)
do it = 1, 30
  call qvs_wexler_dt(tk, pa, qs, dqs)
  rg  = 1000.d0*qs
  drg = 1000.d0*dqs
  aa  = 3.376d0/tk - 0.00254d0
  f0  = log(tk) + 0.2854d0*(1.d0 - 0.28d-3*rg)*lnp + aa*rg*(1.d0 + 0.81d-3*rg) - log(the)
  f1  = 1.d0/tk - 0.2854d0*0.28d-3*lnp*drg - 3.376d0/tk**2*rg*(1.d0 + 0.81d-3*rg) &
        + aa*(1.d0 + 1.62d-3*rg)*drg
  if (f1 <= 0.d0) exit
  dt = -f0/f1
  dt = max(-20.d0, min(20.d0, dt))
  tk = tk + dt
  if (abs(dt) < 1.d-3) exit
enddo
end function t_from_theta_e
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

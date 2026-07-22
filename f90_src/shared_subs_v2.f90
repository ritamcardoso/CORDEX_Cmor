module shared_subs
    use datvar_s
    implicit none

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

    read(unit_id, nml=cordex_config, iostat=status_id)
    if (status_id /= 0) then
        print *, "ERROR: Failed to parse namelist &cordex_config from: ", trim(cfg_filename)
        close(unit_id)
        stop 92
    end if

    close(unit_id)
    print *, "Successfully loaded run configurations from: ", trim(cfg_filename)

    ! Automatically populate secondary targets if variables existed in the namelist file
    if (height(1) /= missing_value) then
        heightl = height(1)
    end if

    if (pres /= missing_value) then
        presl       = pres
        pressure(1) = pres
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


subroutine read_global_metadata(meta_filename)
    character(len=*), intent(in) :: meta_filename
    integer :: unit_id, status_id

    open(newunit=unit_id, file=trim(meta_filename), status='old', action='read', iostat=status_id)
    if (status_id /= 0) then
        print *, "ERROR: Could not open global compliance metadata file: ", trim(meta_filename)
        stop 93
    end if

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
gfile = trim(dir)//trim(geog)//'.nc'
geofile = gfile(1:len_trim(gfile))

status = nf90_open(geofile, nf90_nowrite, ncid)
call ncerror(status, 'opening ' // trim(geofile))
!
! Get rotated coordinates
allocate(tlon(nlon, nlat), tlat(nlon, nlat))
allocate(rlon(nlon), rlat(nlat))

status=nf90_inq_varid(ncid,'CLONG',varid)
status=nf90_get_var(ncid,varid,tlon,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'CLONG')
!
status=nf90_inq_varid(ncid,'CLAT',varid)
status=nf90_get_var(ncid,varid,tlat,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'CLAT')
!
do i=1,nlon
 rlon(i)=tlon(i,1)
enddo
do j=1,nlat
 rlat(j)=tlat(1,j)
enddo
deallocate(tlon, tlat)
!
! Get geographical coordinates
!
allocate(lon(nlon,nlat), lat(nlon,nlat), landmask(nlon,nlat))

status = nf90_inq_varid(ncid, 'XLONG_M', varid)
status = nf90_get_var(ncid, varid, lon, (/xoffset, yoffset/), (/nlon, nlat/), (/1, 1/))

status = nf90_inq_varid(ncid, 'XLAT_M', varid)
status = nf90_get_var(ncid, varid, lat, (/xoffset, yoffset/), (/nlon, nlat/), (/1, 1/))
call ncerror(status,'reading '//'XLAT_M')

status=nf90_inq_varid(ncid,'LANDMASK',varid)
call ncerror(status,'getting var id')

status=nf90_get_var(ncid,varid,landmask,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'LANDMASK')

status = nf90_close(ncid)
call ncerror(status,'closing file')

end subroutine read_geog
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
subroutine write_netcdf_rtime_3d(uvar,mtime,utime,btime)
use netcdf
use datvar_s
!
integer :: LatDimID,LonDimID,BDimID,HDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,rpVarID
integer :: HVarID
integer :: mtime
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar

status = nf90_create(fnameout, IOR(nf90_clobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

! Check for optional Z coordinate conditions
if (height(1) > 0.0) then
    status = nf90_def_var(ncid, "height", nf90_double, HVarId)
elseif (pressure(1) > 0.0) then
    status = nf90_def_var(ncid, "press", nf90_double, HVarId)
end if

status = nf90_def_var(ncid, varname, nf90_float, (/ LonDimId, LatDimID, HDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 2)
call handle_err(status)

status = nf90_put_att(ncid, TVarID, "standard_name","time")
status = nf90_put_att(ncid, TVarID, "long_name","time")
status = nf90_put_att(ncid, TVarID, "bounds","time_bnds")
status = nf90_put_att(ncid, TVarID, "units",timeunits)
status = nf90_put_att(ncid, TVarID, "calender","standard")
status = nf90_put_att(ncid, TVarID, "axis","T")

status = nf90_put_att(ncid, TBVarID, "long_name","time bounds")
status = nf90_put_att(ncid, TBVarID, "units",timeunits)
status = nf90_put_att(ncid, TBVarID, "calender","standard")

status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_pole")

! Dynamically update coordinates attribute string matching configuration state
if (height(1) > 0.0) then
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time height")
elseif (pressure(1) > 0.0) then
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time press")
else
    status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time")
end if

status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",huge_val)
status = nf90_put_att(ncid, uVarID, "missing_value",huge_val)

! Set attributes on the dynamic variable layer if it was initialized
if (height(1) > 0.0) then
    status = nf90_put_att(ncid, HVarID, "long_name","height above the surface")
    status = nf90_put_att(ncid, HVarID, "standard_name","height")
    status = nf90_put_att(ncid, HVarID, "positive","up")
    status = nf90_put_att(ncid, HVarID, "axis","Z")
    status = nf90_put_att(ncid, HVarID, "units","m")
elseif (pressure(1) > 0.0) then
    status = nf90_put_att(ncid, HVarID, "long_name","pressure")
    status = nf90_put_att(ncid, HVarID, "standard_name","air_pressure")
    status = nf90_put_att(ncid, HVarID, "positive","down")
    status = nf90_put_att(ncid, HVarID, "axis","Z")
    status = nf90_put_att(ncid, HVarID, "units","hPa")
end if

status = nf90_put_att(ncid, LonVarID, "long_name","longitude")
status = nf90_put_att(ncid, LonVarID, "standard_name","longitude")
status = nf90_put_att(ncid, LonVarID, "units","degrees_east")
status = nf90_put_att(ncid, LonVarID, "_CoordinateAxisType","Lon")
call handle_err(status)

status = nf90_put_att(ncid, LatVarID, "long_name","latitude")
status = nf90_put_att(ncid, LatVarID, "standard_name","latitude")
status = nf90_put_att(ncid, LatVarID, "units","degrees_north")
status = nf90_put_att(ncid, LatVarID, "_CoordinateAxisType","Lat")
call handle_err(status)

status = nf90_put_att(ncid, rlonVarID, "long_name","longitude in rotated pole grid")
status = nf90_put_att(ncid, rlonVarID, "standard_name","grid_longitude")
status = nf90_put_att(ncid, rlonVarID, "units","degrees")
status = nf90_put_att(ncid, rlonVarID, "axis","X")
call handle_err(status)

status = nf90_put_att(ncid, rlatVarID, "long_name","latitude in rotated pole grid")
status = nf90_put_att(ncid, rlatVarID, "standard_name","grid_latitude")
status = nf90_put_att(ncid, rlatVarID, "units","degrees")
status = nf90_put_att(ncid, rlatVarID, "axis","Y")
call handle_err(status)

status = nf90_put_att(ncid, rpVarID, "grid_mapping_name","rotated_latitude_longitude")
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_latitude", 39.25 )
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_longitude", -162. )
! Updated to map the new shared module constant parameter directly
status = nf90_put_att(ncid, rpVarID, "earth_radius", earth_radius )
call handle_err(status)

call write_global_attributes

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, utime )
call handle_err(status)
status = nf90_put_var(ncid, TBVarID, btime )
call handle_err(status)
status = nf90_put_var(ncid, LonVarId, lon )
call handle_err(status)
status = nf90_put_var(ncid, LatVarId, lat )
call handle_err(status)
status = nf90_put_var(ncid, rlonVarId, rlon )
call handle_err(status)
status = nf90_put_var(ncid, rlatVarId, rlat )
call handle_err(status)

! Write the values to the variable array if initialized
if (height(1) > 0.0) then
    status = nf90_put_var(ncid, HVarID, height )
    call handle_err(status)
elseif (pressure(1) > 0.0) then
    status = nf90_put_var(ncid, HVarID, pressure )
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
integer :: LatDimID,LonDimID,BDimID,HDimID,depth_dimid,SVarId,SBVarId
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,rpVarID
integer :: mtime
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,nsoil,mtime) :: uvar

status = nf90_create(fnameout, IOR(nf90_clobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "nsoil", nsoil, depth_dimid)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, "sdepth", nf90_float, (/ depth_dimid /), SVarId)
status = nf90_def_var(ncid, "sdepth_bnds", nf90_float, (/ BDimID, depth_dimid /), SBVarId)

status = nf90_def_var(ncid, varname, nf90_float, (/ LonDimId, LatDimID, depth_dimid, HDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, nsoil, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 2)
call handle_err(status)

status = nf90_put_att(ncid, TVarID, "standard_name","time")
status = nf90_put_att(ncid, TVarID, "long_name","time")
status = nf90_put_att(ncid, TVarID, "bounds","time_bnds")
status = nf90_put_att(ncid, TVarID, "units",timeunits)
status = nf90_put_att(ncid, TVarID, "calender","standard")
status = nf90_put_att(ncid, TVarID, "axis","T")

status = nf90_put_att(ncid, TBVarID, "long_name","time bounds")
status = nf90_put_att(ncid, TBVarID, "units",timeunits)
status = nf90_put_att(ncid, TBVarID, "calender","standard")

status = nf90_put_att(ncid, SVarId, "standard_name", "depth")
status = nf90_put_att(ncid, SVarId, "long_name", "Soil layer depth")
status = nf90_put_att(ncid, SVarId, "bounds", "sdepth_bnds")
status = nf90_put_att(ncid, SVarId, "units", "m")
status = nf90_put_att(ncid, SVarId, "positive", "down")
status = nf90_put_att(ncid, SVarId, "axis", "Z")

status = nf90_put_att(ncid, SBVarId, "long_name", "sdepth_bnds")
status = nf90_put_att(ncid, SBVarId, "units", "m")
status = nf90_put_att(ncid, SBVarId, "positive", "down")
status = nf90_put_att(ncid, SBVarId, "axis", "Z")

status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_pole")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",huge_val)
status = nf90_put_att(ncid, uVarID, "missing_value",huge_val)

status = nf90_put_att(ncid, LonVarID, "long_name","longitude")
status = nf90_put_att(ncid, LonVarID, "standard_name","longitude")
status = nf90_put_att(ncid, LonVarID, "units","degrees_east")
status = nf90_put_att(ncid, LonVarID, "_CoordinateAxisType","Lon")
call handle_err(status)

status = nf90_put_att(ncid, LatVarID, "long_name","latitude")
status = nf90_put_att(ncid, LatVarID, "standard_name","latitude")
status = nf90_put_att(ncid, LatVarID, "units","degrees_north")
status = nf90_put_att(ncid, LatVarID, "_CoordinateAxisType","Lat")
call handle_err(status)

status = nf90_put_att(ncid, rlonVarID, "long_name","longitude in rotated pole grid")
status = nf90_put_att(ncid, rlonVarID, "standard_name","grid_longitude")
status = nf90_put_att(ncid, rlonVarID, "units","degrees")
status = nf90_put_att(ncid, rlonVarID, "axis","X")
call handle_err(status)

status = nf90_put_att(ncid, rlatVarID, "long_name","latitude in rotated pole grid")
status = nf90_put_att(ncid, rlatVarID, "standard_name","grid_latitude")
status = nf90_put_att(ncid, rlatVarID, "units","degrees")
status = nf90_put_att(ncid, rlatVarID, "axis","Y")
call handle_err(status)

status = nf90_put_att(ncid, rpVarID, "grid_mapping_name","rotated_latitude_longitude")
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_latitude", 39.25 )
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_longitude", -162. )
! Updated to map the new shared module constant parameter directly
status = nf90_put_att(ncid, rpVarID, "earth_radius", earth_radius )
call handle_err(status)

call write_global_attributes

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, utime )
call handle_err(status)
status = nf90_put_var(ncid, TBVarID, btime )
call handle_err(status)
status = nf90_put_var(ncid, LonVarId, lon )
call handle_err(status)
status = nf90_put_var(ncid, LatVarId, lat )
call handle_err(status)
status = nf90_put_var(ncid, rlonVarId, rlon )
call handle_err(status)
status = nf90_put_var(ncid, rlatVarId, rlat )
call handle_err(status)
status = nf90_put_var(ncid, SVarID, sdepth )
call handle_err(status)
status = nf90_put_var(ncid, SBVarID, sdepth_bounds )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)

return
end subroutine write_netcdf_rtime_soil
!
!
!
subroutine write_global_attributes
    use netcdf
    use datvar_s
!
!    integer :: status

    ! Dynamically trigger namelist reading cleanly right before writing attributes
    call init_cordex_environment

    ! String Attributes
    status = nf90_put_att(ncid, nf90_global, "Conventions", trim(conventions))
    status = nf90_put_att(ncid, nf90_global, "activity_id", trim(activity_id))
    status = nf90_put_att(ncid, nf90_global, "contact", trim(contact))
    status = nf90_put_att(ncid, nf90_global, "creation_date", trim(creationdate))
    status = nf90_put_att(ncid, nf90_global, "CORDEX_domain", trim(CORDEX_domain))
    status = nf90_put_att(ncid, nf90_global, "domain", trim(domain_name))
    status = nf90_put_att(ncid, nf90_global, "domain_id", trim(domain_id))
    status = nf90_put_att(ncid, nf90_global, "driving_experiment", trim(experiment))
    status = nf90_put_att(ncid, nf90_global, "driving_experiment_id", trim(experiment_id))
    status = nf90_put_att(ncid, nf90_global, "driving_institution_id", trim(driving_inst_id))
    status = nf90_put_att(ncid, nf90_global, "driving_source_id", trim(driving_source_id))
    status = nf90_put_att(ncid, nf90_global, "driving_source", trim(driving_source))
    status = nf90_put_att(ncid, nf90_global, "driving_variant_lable", trim(driving_variant))
    status = nf90_put_att(ncid, nf90_global, "frequency", trim(frequency))
    status = nf90_put_att(ncid, nf90_global, "further_info_url", trim(further_info_url))
    status = nf90_put_att(ncid, nf90_global, "grid", trim(grid_desc))
    status = nf90_put_att(ncid, nf90_global, "institution", trim(institution))
    status = nf90_put_att(ncid, nf90_global, "institution_id", trim(institution_id))
    status = nf90_put_att(ncid, nf90_global, "label", trim(label))
    status = nf90_put_att(ncid, nf90_global, "label_extended", trim(label_ext))
    status = nf90_put_att(ncid, nf90_global, "license", trim(license))
    status = nf90_put_att(ncid, nf90_global, "mip_era", trim(mip_era))
    status = nf90_put_att(ncid, nf90_global, "product", trim(product))
    status = nf90_put_att(ncid, nf90_global, "project_id", trim(project_id))
    status = nf90_put_att(ncid, nf90_global, "release_year", trim(release_year))
    status = nf90_put_att(ncid, nf90_global, "source_id", trim(source_id))
    status = nf90_put_att(ncid, nf90_global, "source_type", trim(source_type))
    status = nf90_put_att(ncid, nf90_global, "variable_id", trim(varname))
    status = nf90_put_att(ncid, nf90_global, "version_realisation", trim(version_real))
    status = nf90_put_att(ncid, nf90_global, "simulation_start_date", trim(sim_start_date))

    ! Numeric Attributes
    status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension", we_dim)
    status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension", sn_dim)
    status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension", bt_dim)
    status = nf90_put_att(ncid, nf90_global, "dx", dx_val)
    status = nf90_put_att(ncid, nf90_global, "dy", dy_val)

end subroutine write_global_attributes
!
!-------------------------------------------------------------------------------------
!
subroutine handle_err(status)
use netcdf
integer, intent ( in) :: status

if(status /= nf90_noerr) then
  print*, trim(nf90_strerror(status))
  stop "Stopped"
end if
end subroutine handle_err
!
end module shared_subs

module shared_subs
    use datvar_s
!    implicit none

contains
!
!-----------------------------------------------------------------------
!
subroutine read_geog
use netcdf
use datvar_s
!
! Read geog file
gfile = trim(dir)//trim(geog)//'.nc'
geofile = gfile(1:len_trim(gfile))
write(*,*) geofile

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
subroutine write_netcdf_rtime(uvar,mtime,utime,btime)
use netcdf
use datvar_s
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(nf90_noclobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
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
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)

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
status = nf90_put_att(ncid, rpVarID, "earth_radius", 6371229. )
call handle_err(status)

status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.11")
status = nf90_put_att(ncid, nf90_global, "activity_id","DD")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-11")
status = nf90_put_att(ncid, nf90_global, "domain","Europe")
status = nf90_put_att(ncid, nf90_global, "domain_id","EUR-12")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "driving_experiment_id",experiment_id)
status = nf90_put_att(ncid, nf90_global, "driving_institution_id","MPI-M")
status = nf90_put_att(ncid, nf90_global, "driving_source_id","MPI-ESM1-2-HR")
status = nf90_put_att(ncid, nf90_global, "driving_source","MPI-ESM1.2-HR (2017): \naerosol: none, prescribed MACv2-SP\natmos: ECHAM6.3 (spectral T127; 384 x 192 longitude/latitude; 95 levels; top level 0.01 hPa)\natmosChem: none\nland: JSBACH3.20\nlandIce: none/prescribed\nocean: MPIOM1.63 (tripolar TP04, approximately 0.4deg; 802 x 404 longitude/latitude; 40 levels; top grid cell 0-12 m)\nocnBgchem: HAMOCC6\nseaIce: unnamed (thermodynamic (Semtner zero-layer) dynamic (Hibler 79) sea ice model)")
status = nf90_put_att(ncid, nf90_global, "driving_variant_lable","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "further_info_url","https://github.com/CORDEX-WRF-community/euro-cordex-cmip6")
status = nf90_put_att(ncid, nf90_global, "grid","Rotated-pole latitude-longitude with 0.11 degree grid spacing")
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institution_id","IDL-FCUL")
status = nf90_put_att(ncid, nf90_global, "label","WRF V4.5.1-Q")
status = nf90_put_att(ncid, nf90_global, "label_extended","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "license","https://cordex.org/data-access/cordex-cmip6-data/cordex-cmip6-terms-of-use")
status = nf90_put_att(ncid, nf90_global, "mip_era","CMIP6")
status = nf90_put_att(ncid, nf90_global, "product","model-output")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX-CMIP6. CMIP6-driven Coordinated Regional Climate Downscaling Experiment")
status = nf90_put_att(ncid, nf90_global, "release_year","2022")
status = nf90_put_att(ncid, nf90_global, "source","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "source_id","WRF451Q")
status = nf90_put_att(ncid, nf90_global, "source_type","ARMC")
status = nf90_put_att(ncid, nf90_global, "variable_id",varname)
status = nf90_put_att(ncid, nf90_global, "version_realisation","v1-r1")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","2015-01-01_06:00:00")
status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

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
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
return
end
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime_h(uvar,mtime,utime,btime)
use netcdf
use datvar_s
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(nf90_noclobber, nf90_netcdf4), ncid)
call handle_err(status)
write(*,*) fnameout

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, "height", nf90_double, HVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
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
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time height")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)

status = nf90_put_att(ncid, HVarID, "long_name","height above the surface")
status = nf90_put_att(ncid, HVarID, "standard_name","height")
status = nf90_put_att(ncid, HVarID, "positive","up")
status = nf90_put_att(ncid, HVarID, "axis","Z")
status = nf90_put_att(ncid, HVarID, "units","m")

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
status = nf90_put_att(ncid, rpVarID, "earth_radius", 6371229. )
call handle_err(status)

status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.11")
status = nf90_put_att(ncid, nf90_global, "activity_id","DD")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-11")
status = nf90_put_att(ncid, nf90_global, "domain","Europe")
status = nf90_put_att(ncid, nf90_global, "domain_id","EUR-12")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "driving_experiment_id",experiment_id)
status = nf90_put_att(ncid, nf90_global, "driving_institution_id","MPI-M")
status = nf90_put_att(ncid, nf90_global, "driving_source_id","MPI-ESM1-2-HR")
status = nf90_put_att(ncid, nf90_global, "driving_source","MPI-ESM1.2-HR (2017): \naerosol: none, prescribed MACv2-SP\natmos: ECHAM6.3 (spectral T127; 384 x 192 longitude/latitude; 95 levels; top level 0.01 hPa)\natmosChem: none\nland: JSBACH3.20\nlandIce: none/prescribed\nocean: MPIOM1.63 (tripolar TP04, approximately 0.4deg; 802 x 404 longitude/latitude; 40 levels; top grid cell 0-12 m)\nocnBgchem: HAMOCC6\nseaIce: unnamed (thermodynamic (Semtner zero-layer) dynamic (Hibler 79) sea ice model)")
status = nf90_put_att(ncid, nf90_global, "driving_variant_lable","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "further_info_url","https://github.com/CORDEX-WRF-community/euro-cordex-cmip6")
status = nf90_put_att(ncid, nf90_global, "grid","Rotated-pole latitude-longitude with 0.11 degree grid spacing")
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institution_id","IDL-FCUL")
status = nf90_put_att(ncid, nf90_global, "label","WRF V4.5.1-Q")
status = nf90_put_att(ncid, nf90_global, "label_extended","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "license","https://cordex.org/data-access/cordex-cmip6-data/cordex-cmip6-terms-of-use")
status = nf90_put_att(ncid, nf90_global, "mip_era","CMIP6")
status = nf90_put_att(ncid, nf90_global, "product","model-output")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX-CMIP6. CMIP6-driven Coordinated Regional Climate Downscaling Experiment")
status = nf90_put_att(ncid, nf90_global, "release_year","2022")
status = nf90_put_att(ncid, nf90_global, "source","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "source_id","WRF451Q")
status = nf90_put_att(ncid, nf90_global, "source_type","ARMC")
status = nf90_put_att(ncid, nf90_global, "variable_id",varname)
status = nf90_put_att(ncid, nf90_global, "version_realisation","v1-r1")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","2015-01-01_06:00:00")
status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

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
status = nf90_put_var(ncid, HVarID, height )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
return
end
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime_p(uvar,mtime,utime,btime)
use netcdf
use datvar_s
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(nf90_noclobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, "press", nf90_double, HVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
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
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time press")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)

status = nf90_put_att(ncid, HVarID, "long_name","pressure")
status = nf90_put_att(ncid, HVarID, "standard_name","air_pressure")
status = nf90_put_att(ncid, HVarID, "positive","down")
status = nf90_put_att(ncid, HVarID, "axis","Z")
status = nf90_put_att(ncid, HVarID, "units","hPa")

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
status = nf90_put_att(ncid, rpVarID, "earth_radius", 6371229. )
call handle_err(status)

status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.11")
status = nf90_put_att(ncid, nf90_global, "activity_id","DD")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-11")
status = nf90_put_att(ncid, nf90_global, "domain","Europe")
status = nf90_put_att(ncid, nf90_global, "domain_id","EUR-12")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "driving_experiment_id",experiment_id)
status = nf90_put_att(ncid, nf90_global, "driving_institution_id","MPI-M")
status = nf90_put_att(ncid, nf90_global, "driving_source_id","MPI-ESM1-2-HR")
status = nf90_put_att(ncid, nf90_global, "driving_source","MPI-ESM1.2-HR (2017): \naerosol: none, prescribed MACv2-SP\natmos: ECHAM6.3 (spectral T127; 384 x 192 longitude/latitude; 95 levels; top level 0.01 hPa)\natmosChem: none\nland: JSBACH3.20\nlandIce: none/prescribed\nocean: MPIOM1.63 (tripolar TP04, approximately 0.4deg; 802 x 404 longitude/latitude; 40 levels; top grid cell 0-12 m)\nocnBgchem: HAMOCC6\nseaIce: unnamed (thermodynamic (Semtner zero-layer) dynamic (Hibler 79) sea ice model)")
status = nf90_put_att(ncid, nf90_global, "driving_variant_lable","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "further_info_url","https://github.com/CORDEX-WRF-community/euro-cordex-cmip6")
status = nf90_put_att(ncid, nf90_global, "grid","Rotated-pole latitude-longitude with 0.11 degree grid spacing")
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institution_id","IDL-FCUL")
status = nf90_put_att(ncid, nf90_global, "label","WRF V4.5.1-Q")
status = nf90_put_att(ncid, nf90_global, "label_extended","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "license","https://cordex.org/data-access/cordex-cmip6-data/cordex-cmip6-terms-of-use")
status = nf90_put_att(ncid, nf90_global, "mip_era","CMIP6")
status = nf90_put_att(ncid, nf90_global, "product","model-output")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX-CMIP6. CMIP6-driven Coordinated Regional Climate Downscaling Experiment")
status = nf90_put_att(ncid, nf90_global, "release_year","2022")
status = nf90_put_att(ncid, nf90_global, "source","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "source_id","WRF451Q")
status = nf90_put_att(ncid, nf90_global, "source_type","ARMC")
status = nf90_put_att(ncid, nf90_global, "variable_id",varname)
status = nf90_put_att(ncid, nf90_global, "version_realisation","v1-r1")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","2015-01-01_06:00:00")
status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

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
status = nf90_put_var(ncid, HVarID, pressure )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
return
end
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime_soil(uvar,mtime,utime,btime)
use netcdf
use datvar_s
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID,depth_dimid,SVarId,SBVarId
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,nsoil,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(nf90_noclobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "nsoil", nsoil, depth_dimid)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, "sdepth", nf90_float, (/ depth_dimid /), SVarId)
status = nf90_def_var(ncid, "sdepth_bnds", nf90_float, (/ BDimID, depth_dimid /), SBVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, depth_dimid, HDimID /), uVarId)
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
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)

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
status = nf90_put_att(ncid, rpVarID, "earth_radius", 6371229. )
call handle_err(status)

status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.11")
status = nf90_put_att(ncid, nf90_global, "activity_id","DD")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-11")
status = nf90_put_att(ncid, nf90_global, "domain","Europe")
status = nf90_put_att(ncid, nf90_global, "domain_id","EUR-12")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "driving_experiment_id",experiment_id)
status = nf90_put_att(ncid, nf90_global, "driving_institution_id","MPI-M")
status = nf90_put_att(ncid, nf90_global, "driving_source_id","MPI-ESM1-2-HR")
status = nf90_put_att(ncid, nf90_global, "driving_source","MPI-ESM1.2-HR (2017): \naerosol: none, prescribed MACv2-SP\natmos: ECHAM6.3 (spectral T127; 384 x 192 longitude/latitude; 95 levels; top level 0.01 hPa)\natmosChem: none\nland: JSBACH3.20\nlandIce: none/prescribed\nocean: MPIOM1.63 (tripolar TP04, approximately 0.4deg; 802 x 404 longitude/latitude; 40 levels; top grid cell 0-12 m)\nocnBgchem: HAMOCC6\nseaIce: unnamed (thermodynamic (Semtner zero-layer) dynamic (Hibler 79) sea ice model)")
status = nf90_put_att(ncid, nf90_global, "driving_variant_lable","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "further_info_url","https://github.com/CORDEX-WRF-community/euro-cordex-cmip6")
status = nf90_put_att(ncid, nf90_global, "grid","Rotated-pole latitude-longitude with 0.11 degree grid spacing")
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institution_id","IDL-FCUL")
status = nf90_put_att(ncid, nf90_global, "label","WRF V4.5.1-Q")
status = nf90_put_att(ncid, nf90_global, "label_extended","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "license","https://cordex.org/data-access/cordex-cmip6-data/cordex-cmip6-terms-of-use")
status = nf90_put_att(ncid, nf90_global, "mip_era","CMIP6")
status = nf90_put_att(ncid, nf90_global, "product","model-output")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX-CMIP6. CMIP6-driven Coordinated Regional Climate Downscaling Experiment")
status = nf90_put_att(ncid, nf90_global, "release_year","2022")
status = nf90_put_att(ncid, nf90_global, "source","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "source_id","WRF451Q")
status = nf90_put_att(ncid, nf90_global, "source_type","ARMC")
status = nf90_put_att(ncid, nf90_global, "variable_id",varname)
status = nf90_put_att(ncid, nf90_global, "version_realisation","v1-r1")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","2015-01-01_06:00:00")
status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

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
!
return
end
!
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
!-----------------------------------------------------------------------
!
subroutine readdata
    ! Reads the input data and the data option switches from inputlist.inp
    use datvar_s
    implicit none

    integer :: inperr, ichlef, ii
    character(80)  :: line
    character(20)  :: keyword

    ! 1. Open and Validate Input File
    open(10, file='inputlist.inp', status='old', iostat=inperr)
    if (inperr /= 0) then
        write(*,*) 'Error: Cannot find inputlist.inp!'
        stop
    endif

    read(10,'(a)') line
    call toupcase(line)
    if (line(1:12) /= 'CORDEX') then
        write(*,*) 'Wrong Input file header in inputlist.inp!'
        stop
    endif

    ! Use a scratch file to filter comments and process data
    open(27, status='scratch')

    ! Initialize logical flags from datvar_s
    ok_iniyear=.false. ; ok_yeari=.false.   ; ok_yearf=.false.   ; ok_imonth=.false.
    ok_nmonth=.false.  ; ok_iday=.false.    ; ok_ndays=.false.   ; ok_ihour=.false.
    ok_nlat=.false.    ; ok_nlon=.false.    ; ok_nz=.false.      ; ok_nsoil=.false.
    ok_xoffset=.false. ; ok_yoffset=.false. ; ok_dir=.false.     ; ok_dir2=.false.
    ok_dom=.false.     ; ok_outdom=.false.  ; ok_wrfvar=.false.  ; ok_vunts=.false.
    ok_vaid=.false.    ; ok_lname=.false.   ; ok_stname=.false.  ; ok_cmethods=.false.
    ok_geog=.false.    ; ok_wrffile=.false. ; ok_exp=.false.     ; ok_dexp=.false.


    ! 2. Parse the Input File
    do
        read(10,'(a)', iostat=inperr) line
        if (inperr /= 0) exit ! End of file

        if (line(1:1) == ' ' .or. line(1:1) == '#') cycle

        ichlef = index(line, '=')
        if (ichlef == 0) cycle

        keyword = line(1:ichlef-1)
        call toupcase(keyword)
        keyword = adjustl(keyword)

        ! Write the value part to scratch for clean reading
        rewind(27)
        write(27,'(a)') line(ichlef+1:80)
        rewind(27)

        select case (trim(keyword))
        case ('INIYEAR')
            read(27,*,iostat=inperr) iniyear    ; if(inperr==0) ok_iniyear=.true.
        case ('YEARI')
            read(27,*,iostat=inperr) yeari      ; if(inperr==0) ok_yeari=.true.
        case ('YEARF')
            read(27,*,iostat=inperr) yearf      ; if(inperr==0) ok_yearf=.true.
        case ('NMONTHS')
            read(27,*,iostat=inperr) nmonths    ; if(inperr==0) ok_nmonth=.true.
        case ('IMONTH')
            read(27,*,iostat=inperr) imonth     ; if(inperr==0) ok_imonth=.true.
        case ('IHOUR')
            read(27,*,iostat=inperr) ihour      ; if(inperr==0) ok_ihour=.true.
        case ('IDAY')
            read(27,*,iostat=inperr) iday       ; if(inperr==0) ok_iday=.true.
        case ('XOFFSET')
            read(27,*,iostat=inperr) xoffset    ; if(inperr==0) ok_xoffset=.true.
        case ('YOFFSET')
            read(27,*,iostat=inperr) yoffset    ; if(inperr==0) ok_yoffset=.true.
        case ('NLON')
            read(27,*,iostat=inperr) nlon       ; if(inperr==0) ok_nlon=.true.
        case ('NLAT')
            read(27,*,iostat=inperr) nlat       ; if(inperr==0) ok_nlat=.true.
        case ('NZ')
            read(27,*,iostat=inperr) nz         ; if(inperr==0) ok_nz=.true.
        case ('NSOIL')
            read(27,*,iostat=inperr) nsoil      ; if(inperr==0) ok_nsoil=.true.
        case ('DIR')
            read(27,*,iostat=inperr) dir        ; if(inperr==0) ok_dir=.true.
        case ('DIR2')
            read(27,*,iostat=inperr) dir2       ; if(inperr==0) ok_dir2=.true.
        case ('DOM')
            read(27,*,iostat=inperr) dom        ; if(inperr==0) ok_dom=.true.
        case ('OUTDOM')
            read(27,*,iostat=inperr) outdom     ; if(inperr==0) ok_outdom=.true.
        case ('WRFVAR')
            read(27,*,iostat=inperr) wrfvar     ; if(inperr==0) ok_wrfvar=.true.
        case ('VAID')
            read(27,*,iostat=inperr) vaid       ; if(inperr==0) ok_vaid=.true.
        case ('VUNTS')
            read(27,*,iostat=inperr) vunts      ; if(inperr==0) ok_vunts=.true.
        case ('LNAME')
            read(27,*,iostat=inperr) lname      ; if(inperr==0) ok_lname=.true.
        case ('STNAME')
            read(27,*,iostat=inperr) stname     ; if(inperr==0) ok_stname=.true.
        case ('CMETHODS')
            read(27,*,iostat=inperr) cmethods   ; if(inperr==0) ok_cmethods=.true.
        case ('GEOG')
            read(27,*,iostat=inperr) geo       ; if(inperr==0) ok_geog=.true.
        case ('WRFFILE')
            read(27,*,iostat=inperr) wrffile    ; if(inperr==0) ok_wrffile=.true.
        case ('DEXP_ID')
            read(27,*,iostat=inperr) dexp_id    ; if(inperr==0) ok_exp=.true.
        case ('DEXP')
            read(27,*,iostat=inperr) adexp      ; if(inperr==0) ok_dexp=.true.
        case ('HEIGHT')
            read(27,*,iostat=inperr) heightl
            height(1)=heightl
        case ('PRES')
            read(27,*,iostat=inperr) presl
            pressure(1)=presl
        case ('FACTOR')
            read(27,*,iostat=inperr) factor
        end select
    end do

    close(10)
    close(27)

    ! 3. Final Verification - Check every flag from datvar_s
    if (.not. ok_iniyear)  call abort_msg('INIYEAR')
    if (.not. ok_yeari)    call abort_msg('YEARI')
    if (.not. ok_yearf)    call abort_msg('YEARF')
    if (.not. ok_nmonth)   call abort_msg('NMONTHS')
    if (.not. ok_imonth)   call abort_msg('IMONTH')
    if (.not. ok_iday)     call abort_msg('IDAY')
    if (.not. ok_ihour)    call abort_msg('IHOUR')
    if (.not. ok_xoffset)  call abort_msg('XOFFSET (Required for NetCDF indexing)')
    if (.not. ok_yoffset)  call abort_msg('YOFFSET (Required for NetCDF indexing)')
    if (.not. ok_nlon)     call abort_msg('NLON')
    if (.not. ok_nlat)     call abort_msg('NLAT')
    if (.not. ok_nz)       call abort_msg('NZ')
    if (.not. ok_nsoil)    call abort_msg('NSOIL')
    if (.not. ok_dir)      call abort_msg('DIR (Input directory)')
    if (.not. ok_dir2)     call abort_msg('DIR2 (Output directory)')
    if (.not. ok_dom)      call abort_msg('DOM (Input domain string)')
    if (.not. ok_outdom)   call abort_msg('OUTDOM (Output domain string)')
    if (.not. ok_wrfvar)   call abort_msg('WRFVAR (Source variable name)')
    if (.not. ok_vaid)     call abort_msg('VAID (Output Variable ID)')
    if (.not. ok_vunts)    call abort_msg('VUNTS (Units)')
    if (.not. ok_lname)    call abort_msg('LNAME (Long Name)')
    if (.not. ok_stname)   call abort_msg('STNAME (Standard Name)')
    if (.not. ok_cmethods) call abort_msg('CMETHODS (Cell Methods)')
    if (.not. ok_geog)     call abort_msg('GEOG (Path to geog file)')
    if (.not. ok_wrffile)  call abort_msg('WRFFILE (Path to WRF file)')
    if (.not. ok_exp)      call abort_msg('EXPID (Experiment ID)')
    if (.not. ok_dexp)     call abort_msg('EXPER (Experiment Name)')

    write(*,*) '>>> All input parameters verified successfully.'

    geog   = trim(adjustl(geo))
    wrfile = trim(adjustl(wrffile))

    ! Clean up character variables for NetCDF use
    varname       = trim(adjustl(vaid))
    vunits        = trim(adjustl(vunts))
    longname      = trim(adjustl(lname))
    standardname  = trim(adjustl(stname))
    cellmethods   = trim(adjustl(cmethods))
    experiment_id = trim(adjustl(dexp_id))
    experiment    = trim(adjustl(adexp))

    write(ayearini,'(i4)')iniyear
    tunts='hours since '//ayearini//'-01-01 00:00'
    timeunits=trim(adjustl(tunts))

contains

    subroutine abort_msg(var)
        character(len=*), intent(in) :: var
        write(*,*) 'Aborted: Missing required input in inputlist.inp: ', var
        stop
    end subroutine abort_msg

end subroutine readdata
!
!
!
subroutine toupcase(string)
    ! Converts a character string to all uppercase letters
    ! This ensures keywords like 'yeari' and 'YEARI' are treated the same
    implicit none
    character(len=*), intent(inout) :: string
    integer :: i, ismall, ibig

    ismall = ichar('a')
    ibig   = ichar('A')

    do i = 1, len(string)
        ! Check if the character is a lowercase letter (a-z)
        if (string(i:i) >= 'a' .and. string(i:i) <= 'z') then
            ! Shift the character code from lowercase to uppercase
            string(i:i) = char(ichar(string(i:i)) + ibig - ismall)
        endif
    enddo
end subroutine toupcase
!
!
end module shared_subs

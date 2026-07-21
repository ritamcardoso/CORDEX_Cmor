
!
program read_wrfout
!use cloud
use netcdf
!
lpress=.false.
!
call init_cordex_environment
!
! Read latitude,longitude, grid angles and orography
!
allocate(tlon(nlon,nlat))
allocate(tlat(nlon,nlat))
!
gfile=trim(dir)//trim(geog)//'.nc'
geofile=gfile(1:len_trim(gfile))
write(*,*)geofile
!
status=nf90_open(geofile,nf90_nowrite,ncid)
call ncerror(status,'opening file')

status=nf90_inq_varid(ncid,'CLONG',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,tlon,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'CLONG')
!
status=nf90_inq_varid(ncid,'CLAT',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,tlat,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'CLAT')
!
allocate(rlon(nlon))
allocate(rlat(nlat))
!
do i=1,nlon
 rlon(i)=tlon(i,1)
enddo
do j=1,nlat
 rlat(j)=tlat(1,j)
enddo
deallocate(tlon)
deallocate(tlat)
!
allocate(lon(nlon,nlat))
allocate(lat(nlon,nlat))
allocate(wrfv2D(nlon,nlat))
allocate(outvar(nlon,nlat))
outvar=0.
!
status=nf90_inq_varid(ncid,'XLONG_M',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,lon,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'XLONG_M')
!
status=nf90_inq_varid(ncid,'XLAT_M',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,lat,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'XLAT_M')
!
status=nf90_inq_varid(ncid,wrfvar,varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,wrfv2D,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//wrfvar)
!
status=nf90_close(ncid)
call ncerror(status,'closing file')
!
do ix =1,nlon
  do iy=1,nlat
    if(wrfv2D(ix,iy) == 15) outvar(ix,iy)= 100.
  enddo
enddo  
!
call write_output
!
end ! end program
!
!
!-----------------------------------------------------------------------
!
subroutine write_output
!
!
outfile=trim(vaid)//trim(outdom)//'fx.nc'
fnameout=outfile(1:len_trim(outfile))
exper=trim(aexp)//' run with reanalysis forcing'
experiment=exper(1:len_trim(exper))
dexper='ECMWF-ERA5, '//trim(adexp)//', r1i1p1'
dexperiment=dexper(1:len_trim(dexper))

call date_and_time(date,times,zone,values)

write(yyyy,'(i4)')values(1)
if(values(2) < 10)then
  write(mm,'(a1,i1)')'0',values(2)
else
  write(mm,'(i2)')values(2)
endif
if(values(3) < 10)then
  write(dd,'(a1,i1)')'0',values(3)
else
  write(dd,'(i2)')values(3)
endif
if(values(5) < 10)then
  write(hh,'(a1,i1)')'0',values(5)
else
  write(hh,'(i2)')values(5)
endif
if(values(6) < 10)then
  write(mn,'(a1,i1)')'0',values(6)
else
  write(mn,'(i2)')values(6)
endif
if(values(7) < 10)then
  write(ss,'(a1,i1)')'0',values(7)
else
  write(ss,'(i2)')values(7)
endif
cdate=yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
creationdate=cdate(1:len_trim(cdate))
!
call write_netcdf_2D(outvar)
!
end subroutine write_output
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
subroutine write_netcdf_2D(uvar)
use netcdf
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
real, dimension(nlon,nlat) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, nf90_noclobber, ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)

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
                            (/ LonDimId, LatDimID /), uVarId)
call handle_err(status)

status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_pole")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon height")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)

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
call handle_err(status)

status = nf90_enddef(ncid)

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

!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime(uvar,mtime,utime,btime)
use netcdf
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, nf90_noclobber, ncid)
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
status = nf90_def_var(ncid, "crs", nf90_char,rpVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
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
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_latitude_longitude")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)

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

status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.4")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "experiment_id","evaluation")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",dexperiment)
status = nf90_put_att(ncid, nf90_global, "driving_model_id","ECMWF-ERA5")
status = nf90_put_att(ncid, nf90_global, "driving_model_ensemble_member","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "driving_experiment_name","evaluation")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institute_id","IDL")
status = nf90_put_att(ncid, nf90_global, "model_id","WRFV451Q")
status = nf90_put_att(ncid, nf90_global, "rcm_version_id","v1")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX")
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-12")
status = nf90_put_att(ncid, nf90_global, "product","output")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","1978-07-01_00:00:00")
status = nf90_put_att(ncid, nf90_global, "west-east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south-north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom-top_grid_dimension",54)
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
!-------------------------------------------------------------------------------------
!
subroutine write_netcdf_rtime_h(uvar,mtime,utime,btime)
use netcdf
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, nf90_noclobber, ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "height", nf90_double, HVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)

status = nf90_def_var(ncid, "crs", nf90_char,rpVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
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

status = nf90_put_att(ncid, HVarID, "long_name","height above the surface")
status = nf90_put_att(ncid, HVarID, "standard_name","height")
status = nf90_put_att(ncid, HVarID, "positive","up")
status = nf90_put_att(ncid, HVarID, "axis","Z")
status = nf90_put_att(ncid, HVarID, "units","m")

status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_latitude_longitude")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)

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

status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.4")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "experiment_id","evaluation")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",dexperiment)
status = nf90_put_att(ncid, nf90_global, "driving_model_id","ECMWF-ERA5")
status = nf90_put_att(ncid, nf90_global, "driving_model_ensemble_member","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "driving_experiment_name","evaluation")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institute_id","IDL")
status = nf90_put_att(ncid, nf90_global, "model_id","WRFV451Q")
status = nf90_put_att(ncid, nf90_global, "rcm_version_id","v1")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX")
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-12")
status = nf90_put_att(ncid, nf90_global, "product","output")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","1978-07-01_00:00:00")
status = nf90_put_att(ncid, nf90_global, "west-east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south-north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom-top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, utime )
call handle_err(status)
status = nf90_put_var(ncid, TBVarID, btime )
call handle_err(status)
status = nf90_put_var(ncid, HVarID, height )
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
!-------------------------------------------------------------------------------------
!
subroutine write_netcdf_rtime_p(uvar,mtime,utime,btime)
use netcdf
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID,PVarID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, nf90_noclobber, ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "plev", nf90_double, HVarId)
status = nf90_def_var(ncid, "plev_bnds", nf90_double, &
                            (2), PVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "crs", nf90_char,rpVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
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

status = nf90_put_att(ncid, HVarID, "long_name","pressure")
status = nf90_put_att(ncid, HVarID, "standard_name","air_pressure")
status = nf90_put_att(ncid, HVarID, "positive","down")
status = nf90_put_att(ncid, HVarID, "axis","Z")
status = nf90_put_att(ncid, HVarID, "units","Pa")
status = nf90_put_att(ncid, HVarID, "bounds","plev_bnds")

status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_latitude_longitude")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)

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

status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.4")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "experiment_id","evaluation")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",dexperiment)
status = nf90_put_att(ncid, nf90_global, "driving_model_id","ECMWF-ERA5")
status = nf90_put_att(ncid, nf90_global, "driving_model_ensemble_member","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "driving_experiment_name","evaluation")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institute_id","IDL")
status = nf90_put_att(ncid, nf90_global, "model_id","WRFV451Q")
status = nf90_put_att(ncid, nf90_global, "rcm_version_id","v1")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX")
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-12")
status = nf90_put_att(ncid, nf90_global, "product","output")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","1979-01-01_00:00:00")
status = nf90_put_att(ncid, nf90_global, "west-east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south-north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom-top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, utime )
call handle_err(status)
status = nf90_put_var(ncid, TBVarID, btime )
call handle_err(status)
status = nf90_put_var(ncid, HVarID, pressure )
call handle_err(status)
status = nf90_put_var(ncid, PVarID, pressure_bounds )
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
!
! Reads the input data and the data option switches
!
!     Calls funtion uppercase to transform the indexing keywords into
!     upercase indexes
!
integer :: itext,inperr,ichlef,ichrig,ii
real :: verbose
character(20) :: keyword,uppercase
character(80) :: line
external uppercase
logical ok_yeari,ok_yearf,ok_nmonth,ok_imonth
logical ok_ndays,ok_iday,ok_nlon,ok_nlat,ok_nz,ok_xoffset,ok_yoffset,ok_dir,ok_dir2,ok_dom,ok_outdom
logical ok_wrfvar,ok_vaid,ok_vunts,ok_lname,ok_stname,ok_cmethods,ok_geog,ok_wrffile
!
open(10,file='outputlist.inp')
!
read(10,'(a)')line
if(uppercase(line(1:12)).ne.'CORDEX') then
  write(*,*) 'Wrong Input file outputlist.inp !'
  stop
endif
!
open(27,status='scratch')
!
ok_yeari=.false.
ok_yearf=.false.
ok_nmonth=.false.
ok_imonth=.false.
ok_nlon=.false.
ok_nlat=.false.
ok_nz=.false.
ok_xoffset=.false.
ok_yoffset=.false.
ok_dir=.false.
ok_dir2=.false.
ok_geog=.false.
ok_wrffile=.false.
ok_dom=.false.
ok_outdom=.false.
ok_wrfvar=.false.
ok_vaid=.false.
ok_vunts=.false.
ok_lname=.false.
ok_stname=.false.
ok_cmethods=.false.
!
itext=0
inperr=0
do while(inperr.eq.0)
  read(10,'(a)') line
!
! Isolate keyword
!
  ichlef=1
  do i=1,80
    if(line(i:i).ne.' ') exit
    ichlef=i
  enddo
  if(ichlef.eq.80) cycle
  ichrig=ichlef
  do i=ichlef+1,80
    if(line(i:i).eq.' ') exit
    ichrig=i
  enddo
  keyword=line(ichlef:ichrig)
  call toupcase(keyword)
  write(27,'(a)') line(ichrig+1:80)
  backspace(27)
  if(keyword(1:3).eq.uppercase('end')) then
    exit
  elseif(keyword(1:1).eq.'#') then
    cycle
  elseif(keyword.eq.uppercase('verbose')) then
    read(27,*,iostat=inperr) verbose
    if(verbose.ge.1) write(*,*) 'verbose=',verbose
  elseif(keyword.eq.uppercase('yeari')) then
    read(27,*,iostat=inperr) yeari
    if(verbose.ge.1) write(*,*) 'yeari=',yeari
    ok_yeari=.true.
!
    write(aiyear,'(i4)')yeari
    if(mod(yeari,4) == 0. .and. yeari /= 2100)then
      days=days2
      mydays=366
      sedays=sedays2
    else
      days=days1
      mydays=365
      sedays=sedays1
    endif
!
!    ntime=mydays*24
!    ntime3=mydays*8
!    ntime6=mydays*8
!
  elseif(keyword.eq.uppercase('yearf')) then
    read(27,*,iostat=inperr) yearf
    if(verbose.ge.1) write(*,*) 'yearf=',yearf
    ok_yearf=.true.
  elseif(keyword.eq.uppercase('nmonth')) then
    read(27,*,iostat=inperr) nmonths
    if(verbose.ge.1) write(*,*) 'nmonth=',nmonths
    ok_nmonth=.true.
  elseif(keyword.eq.uppercase('imonth')) then
    read(27,*,iostat=inperr) imonth
    if(verbose.ge.1) write(*,*) 'imonth=',imonth
    ok_imonth=.true.
!
     if(imonth < 10) then
        write(aimonth,'(a1,i1)') '0',imonth
        write(amonthi,'(a1,i1)') '0',imonth
     else
        write(aimonth,'(i2)') imonth
        write(amonthi,'(i2)') imonth
     endif
!
  elseif(keyword.eq.uppercase('iday')) then
    read(27,*,iostat=inperr) iday
    if(verbose.ge.1) write(*,*) 'iday=',iday
    ok_iday=.true.
!
     if(iday < 10) then
       write(aiday,'(a1,i1)') '0',iday
       write(adayi,'(a1,i1)') '0',iday
     else
      write(aiday,'(i2)') iday
      write(adayi,'(i2)') iday
     endif
!
  elseif(keyword.eq.uppercase('xoffset')) then
    read(27,*,iostat=inperr) xoffset
    if(verbose.ge.1) write(*,*) 'xoffset=',xoffset
    ok_xoffset=.true.
  elseif(keyword.eq.uppercase('yoffset')) then
    read(27,*,iostat=inperr) yoffset
    if(verbose.ge.1) write(*,*) 'yoffset=',yoffset
    ok_yoffset=.true.
  elseif(keyword.eq.uppercase('nlon')) then
    read(27,*,iostat=inperr) nlon
    if(verbose.ge.1) write(*,*) 'nlon=',nlon
    ok_nlon=.true.
  elseif(keyword.eq.uppercase('nlat')) then
    read(27,*,iostat=inperr) nlat
    if(verbose.ge.1) write(*,*) 'nlat=',nlat
    ok_nlat=.true.
  elseif(keyword.eq.uppercase('nz')) then
    read(27,*,iostat=inperr) nz
    if(verbose.ge.1) write(*,*) 'nz=',nz
    ok_nz=.true.
  elseif(keyword.eq.uppercase('nsoil')) then
    read(27,*,iostat=inperr) nsoil
    if(verbose.ge.1) write(*,*) 'nsoil=',nsoil
    ok_nsoil=.true.
!
    nzt=nz+1
!
  elseif(keyword.eq.uppercase('dir')) then
    read(27,*,iostat=inperr) dir
    if(verbose.ge.1) write(*,*) 'dir=',dir
    ok_dir=.true.
  elseif(keyword.eq.uppercase('dir2')) then
    read(27,*,iostat=inperr) dir2
    if(verbose.ge.1) write(*,*) 'dir2=',dir2
    ok_dir2=.true.
  elseif(keyword.eq.uppercase('dom')) then
    read(27,*,iostat=inperr) dom
    if(verbose.ge.1) write(*,*) 'dom=',dom
    ok_dom=.true.
  elseif(keyword.eq.uppercase('outdom')) then
    read(27,*,iostat=inperr) outdom
    if(verbose.ge.1) write(*,*) 'outdom=',outdom
    ok_outdom=.true.
  elseif(keyword.eq.uppercase('exp')) then
    read(27,*,iostat=inperr) aexp
    if(verbose.ge.1) write(*,*) 'exp=',aexp
    ok_exp=.true.
  elseif(keyword.eq.uppercase('dexp')) then
    read(27,*,iostat=inperr) adexp
    if(verbose.ge.1) write(*,*) 'dexp=',adexp
    ok_dexp=.true.
  elseif(keyword.eq.uppercase('geog')) then
    read(27,*,iostat=inperr) geo
    if(verbose.ge.1) write(*,*) 'geo file=',geo
    ok_geog=.true.

    geog=geo(1:len_trim(geo))

  elseif(keyword.eq.uppercase('wrffile')) then
    read(27,*,iostat=inperr) wrffile
    if(verbose.ge.1) write(*,*) 'wrf file=',wrffile
    ok_wrffile=.true.

    wrfile=wrffile(1:len_trim(wrffile))

  elseif(keyword.eq.uppercase('wrfvar')) then
    read(27,*,iostat=inperr) wrfvar
    if(verbose.ge.1) write(*,*) 'wrfvar=',wrfvar
    ok_wrfvar=.true.

    wrfvarname=wrfvar(1:len_trim(wrfvar))

  elseif(keyword.eq.uppercase('vaid'))then
    read(27,*,iostat=inperr)vaid
    if(verbose.ge.1) write(*,*)'var id=',vaid
    ok_vaid=.true.

    varname=vaid(1:len_trim(vaid))

  elseif(keyword.eq.uppercase('rain'))then
    lpress=.true.
  elseif(keyword.eq.uppercase('vunts'))then
    read(27,*,iostat=inperr)vunts
    if(verbose.ge.1) write(*,*)'var units=',vunts
    ok_vunts=.true.

    vunits=vunts(1:len_trim(vunts))

  elseif(keyword.eq.uppercase('lname'))then
    read(27,*,iostat=inperr)lname
    if(verbose.ge.1) write(*,*)'var long name=',lname
    ok_lname=.true.

    longname=lname(1:len_trim(lname))

  elseif(keyword.eq.uppercase('stname'))then
    read(27,*,iostat=inperr)stname
    if(verbose.ge.1) write(*,*)'var standard name=',stname
    ok_stname=.true.

    standardname=stname(1:len_trim(stname))

  elseif(keyword.eq.uppercase('cmethods'))then
    read(27,*,iostat=inperr)cmethods
    if(verbose.ge.1) write(*,*)'var time agregation =',cmethods
    ok_cmethods=.true.

    cellmethods=cmethods(1:len_trim(cmethods))

  elseif(keyword.eq.uppercase('factor'))then
    read(27,*,iostat=inperr)factor
    if(verbose.ge.1) write(*,*)'factor=',factor
  else
    write(*,*) 'Unrecognized keyword !!:',keyword
    stop
  endif
  if(inperr.gt.0) then
    write(*,*) 'Input error from outputlist'
    stop
  endif
enddo
!
! Check data
!
if(.not.ok_yeari) then
  write(*,*) 'Aborted due to missing data: yeari'
  stop
endif
if(.not.ok_yearf) then
  write(*,*) 'Aborted due to missing data: yearf'
  stop
endif
if(.not.ok_nmonth) then
  write(*,*) 'Aborted due to missing data: nmonth'
  stop
endif
if(.not.ok_imonth) then
  write(*,*) 'Aborted due to missing data: imonth'
  stop
endif
if(.not.ok_dir) then
  write(*,*) 'Aborted due to missing input dir: dir'
  stop
endif
if(.not.ok_dir2) then
  write(*,*) 'Aborted due to missing input dir2: dir2'
  stop
endif
if(.not.ok_geog) then
  write(*,*) 'Aborted due to missing input geo_em file name'
  stop
endif
if(.not.ok_wrffile) then
  write(*,*) 'Aborted due to missing input wrf file name'
  stop
endif
if(.not.ok_dom) then
  write(*,*) 'Aborted due to missing input domain: dom'
  stop
endif
if(.not.ok_outdom) then
  write(*,*) 'Aborted due to missing output domain: outdom'
  stop
endif
if(.not.ok_wrfvar) then
  write(*,*) 'Aborted due to missing wrf input var: wrfvar'
  stop
endif
if(.not.ok_vaid) then
  write(*,*) 'Aborted due to missing output var id: vaid'
  stop
endif
if(.not.ok_vunts) then
  write(*,*) 'Aborted due to missing output var units: vunts'
  stop
endif
if(.not.ok_lname) then
  write(*,*) 'Aborted due to missing output var long name: lname'
  stop
endif
if(.not.ok_stname) then
  write(*,*) 'Aborted due to missing output var standard name: stname'
  stop
endif
if(.not.ok_cmethods) then
  write(*,*) 'Aborted due to missing output var agregation methods: cmethods'
  stop
endif
return
end
!
!-----------------------------------------------------------------------
!
subroutine toupcase(string)
!
! Converts string to uppercase
!
!     From nhli9902 - Miranda 1998
!
character (len=*) string
integer i,ismall,ibig
ismall=ichar('a')
ibig=ichar('A')
do i=1,len(string)
  if(string(i:i).ge.'a' .and. string(i:i).le.'z') then
    string(i:i)=char(ichar(string(i:i))+ibig-ismall)
  endif
enddo
return
end
!
!-----------------------------------------------------------------------
!
function uppercase(string)
!
! Converts string to uppercase
!
!     From nhad9903 - Miranda 1998
!
character (len=*) string
character(20) :: uppercase
integer :: i,ismall,ibig

uppercase=string
ismall=ichar('a')
ibig=ichar('A')
do i=1,len(string)
  if(string(i:i).ge.'a' .and. string(i:i).le.'z') then
    uppercase(i:i)=char(ichar(string(i:i))+ibig-ismall)
  endif
enddo
return
end
!

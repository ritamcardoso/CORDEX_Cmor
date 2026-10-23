program read_wrfout
!
! RCM_fx_areacella — area of the grid cells (areacella, m2, fx), as WRF sees it: the
! grid spacing on the projection plane divided by the map scale factors,
!
!   areacella = DX * DY / (MAPFAC_MX * MAPFAC_MY)
!
! DX, DY: global attributes of the geo_em file (m; dx_val/dy_val of the global ini if
! missing); MAPFAC_MX, MAPFAC_MY: map scale factors on the mass points (MAPFAC_M for
! both when the geo_em file has no MX/MY).
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK, LU_INDEX) ---

call read_geog

! fixed field: an existing file is kept (the NetCDF writer does not overwrite)
outfile = trim(dir_out)//trim(vaid)//trim(outdom)//'fx.nc'
inquire(file=trim(outfile), exist=fx_exists)
if (fx_exists) then
  print *, trim(outfile), ' already exists: kept (fixed field)'
  stop
endif

allocate(outvar(nlon,nlat))
allocate(msftx(nlon,nlat), msfty(nlon,nlat))

gfile = trim(dir_in)//trim(geog)//'.nc'
geofile = gfile(1:len_trim(gfile))
status = nf90_open(geofile, nf90_nowrite, ncid)
call ncerror(status, 'opening '//trim(geofile))

! grid spacing (m)
status = nf90_get_att(ncid, nf90_global, 'DX', dx_geo)
if (status /= nf90_noerr) dx_geo = dx_val
status = nf90_get_att(ncid, nf90_global, 'DY', dy_geo)
if (status /= nf90_noerr) dy_geo = dy_val

! map scale factors on the mass points
status = nf90_inq_varid(ncid, 'MAPFAC_MX', varid)
if (status == nf90_noerr) then
  status = nf90_get_var(ncid, varid, msftx, (/xoffset, yoffset/), (/nlon, nlat/))
  call ncerror(status, 'reading MAPFAC_MX from '//trim(geofile))
  status = nf90_inq_varid(ncid, 'MAPFAC_MY', varid)
  call ncerror(status, 'getting var id MAPFAC_MY in '//trim(geofile))
  status = nf90_get_var(ncid, varid, msfty, (/xoffset, yoffset/), (/nlon, nlat/))
  call ncerror(status, 'reading MAPFAC_MY from '//trim(geofile))
else
  status = nf90_inq_varid(ncid, 'MAPFAC_M', varid)
  call ncerror(status, 'getting var id MAPFAC_MX/MAPFAC_M in '//trim(geofile))
  status = nf90_get_var(ncid, varid, msftx, (/xoffset, yoffset/), (/nlon, nlat/))
  call ncerror(status, 'reading MAPFAC_M from '//trim(geofile))
  msfty = msftx
endif

status = nf90_close(ncid)
call ncerror(status, 'closing '//trim(geofile))

outvar = dx_geo * dy_geo / (msftx * msfty)
write(*,*) 'areacella: DX, DY = ', dx_geo, dy_geo, ' m; min/max ', minval(outvar), maxval(outvar), ' m2; total ', &
           sum(real(outvar, 8)), ' m2'

call write_output

contains
!
!-----------------------------------------------------------------------
!
subroutine write_output
! file name and NetCDF writer (fx file)

freq = 'fx'
frequency = trim(adjustl(freq))

fnameout = trim(adjustl(outfile))

call date_and_time(date,times,zone,values)
write(yyyy,'(i4)') values(1)
mm = pad_int(values(2), 2)
dd = pad_int(values(3), 2)
hh = pad_int(values(5), 2)
mn = pad_int(values(6), 2)
ss = pad_int(values(7), 2)
cdate = yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
creationdate = cdate(1:len_trim(cdate))

call write_netcdf_2D(outvar)

end subroutine write_output
!
!-----------------------------------------------------------------------
!
end program read_wrfout

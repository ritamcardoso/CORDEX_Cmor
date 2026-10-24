program read_wrfout
!
! RCM_fx_slthick — slthick, thickness of the soil layers (fx, m, lon x lat x depth): the
! layer thicknesses DZS (wrfvar of the header) of the first wrfout file of the job year,
! the same in every land cell (sea points missing). depth = middle of each layer,
! depth_bnds = its top and bottom (write_netcdf_fx_soil). An existing fx file is kept.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

logical :: lu_exists

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

outfile=trim(dir_out)//trim(vaid)//trim(outdom)//'fx.nc'
inquire(file=trim(outfile), exist=lu_exists)
if (lu_exists) then
  print *, trim(outfile), ' already exists: kept (fixed field)'
  stop
endif


! --- First wrfout file of the job year
write(ayear, '(i4)') yeari
amonth = pad_int(imonth, 2)
aday = pad_int(iday, 2)
ahour = pad_int(ihour, 2)
infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'

! --- Soil layer thicknesses DZS (Time, soil_layers_stag)
status = nf90_open(trim(infile), nf90_nowrite, ncid)
call ncerror(status,'opening '//trim(infile))
status = nf90_inq_varid(ncid, wrfvar, varid)
call ncerror(status,'getting var id '//trim(wrfvar)//' in '//trim(infile))
allocate(sl_dz(nsoil))
status = nf90_get_var(ncid, varid, sl_dz, (/1,1/), (/nsoil,1/))
call ncerror(status,'reading '//trim(wrfvar)//' from '//trim(infile))
status = nf90_close(ncid)
call ncerror(status,'closing '//trim(infile))
write(*,*) trim(wrfvar), ' (m): ', sl_dz

! the same thicknesses in every land cell; sea points missing
allocate(wrfv3D(nlon,nlat,nsoil))
do k = 1, nsoil
  where (landmask > 0.5)
    wrfv3D(:,:,k) = sl_dz(k)
  elsewhere
    wrfv3D(:,:,k) = huge_val
  endwhere
enddo

call write_output

contains
!
!----------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_subs
use netcdf

freq='fx'
frequency=trim(adjustl(freq))

fnameout=trim(adjustl(outfile))

call date_and_time(date,times,zone,values)
write(yyyy,'(i4)')values(1)
mm = pad_int(values(2), 2)
dd = pad_int(values(3), 2)
hh = pad_int(values(5), 2)
mn = pad_int(values(6), 2)
ss = pad_int(values(7), 2)

cdate=yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
creationdate=cdate(1:len_trim(cdate))
!
! Call the shared NetCDF writer from shared_subs
!
call write_netcdf_fx_soil(wrfv3D)

deallocate(wrfv3D, sl_dz)

end subroutine write_output


end program read_wrfout

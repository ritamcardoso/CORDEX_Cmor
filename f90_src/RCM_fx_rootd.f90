program read_wrfout
!
! RCM_fx_rootd — maximum root depth (rootd, m, fx): the depth of the soil layers with
! roots of the dominant vegetation class of each grid cell,
!
!   rootd = sum of the thicknesses of the top NROOT soil layers
!
! NROOT: number of root layers of the class (LU_INDEX of the geo_em file), from the
! WRF VEGPARM.TBL / Noah-MP NoahmpTable.TBL (identical; nroot_modis / nroot_usgs in
! datvar_s), for the land-use table of the geo_em file (MMINLU). The LCZ urban classes
! (51-61 MODIS, 31-41 USGS) take the urban value, MODIS lakes (21) 0. Layer
! thicknesses: sdepth (the 4 Noah/Noah-MP layers, 0.1, 0.3, 0.6, 1.0 m). Sea
! (LANDMASK = 0) is missing.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_io_subs
use netcdf
!implicit none

! --- Read configuration using shared_io_subs subroutine

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
do iy = 1, nlat
  do ix = 1, nlon
    k = nint(luindex(ix,iy))
    if (lu_usgs) then
      if (k >= 31 .and. k <= 41) k = 1                   ! LCZ: urban
      if (k >= 1 .and. k <= size(nroot_usgs)) then
        l = nroot_usgs(k)
      else
        l = 0
      endif
    else
      if (k >= 51 .and. k <= 61) k = 13                  ! LCZ: urban
      if (k >= 1 .and. k <= size(nroot_modis)) then
        l = nroot_modis(k)
      else
        l = 0                                            ! 21: lakes
      endif
    endif
    if (landmask(ix,iy) < 0.5) then
      outvar(ix,iy) = huge_val
    else
      outvar(ix,iy) = sum(sdepth(1:min(l, size(sdepth))))
    endif
  enddo
enddo
write(*,*) 'rootd: land-use table ', trim(lu_table), '; min/max over land ', &
           minval(outvar, mask=landmask >= 0.5), maxval(outvar, mask=landmask >= 0.5), ' m'

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

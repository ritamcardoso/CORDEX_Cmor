program read_wrfout
!
! RCM_yr_landuse — yearly land-cover fractions (frequency yr, % of the grid cell) and
! dominant land-use category, for land-use change experiments (LUCAS): the variables
! of RCM_fx_landuse (treeFrac, shrubFrac, grassFrac, cropFrac, baresoilFrac,
! urbanFrac, cnc, luindex), one value per year, from LANDUSEF / LU_INDEX of the
! first wrfout file of each year (YYYY-01-01_00). The land use is held fixed through
! the year (the maps change from one year to the next), so the value is written as
! the mean of the year: time at mid-year, bounds YYYY-01-01 to YYYY+1-01-01,
! cell_methods "<header> time: mean". If the last wrfout of the year (Dec 31 23 UTC)
! has a different map, the largest difference is printed as a warning.
! One file per year: <var>_<outdom>yr_YYYY-YYYY.nc. The grouping of the land-use
! categories (weight tables) is in landuse_field (shared_subs_v2.f90).
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

real, dimension(:,:), allocatable :: ly_last
logical :: ly_exists
integer :: ly_h0, ly_h1

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

if (index(cellmethods, 'time:') == 0) cellmethods = trim(cellmethods)//' time: mean'

allocate(ly_last(nlon,nlat))
ntime = 1

do year = yeari, yearf
  write(ayear, '(i4)') year

  allocate(ttime(ntime), bdtime(2,ntime), outvar_h(nlon,nlat,ntime))

  ! hours since iniyear-01-01 of the start and end of the year
  ly_h0 = 24 * (days_from_civil(year, 1, 1) - days_from_civil(iniyear, 1, 1))
  ly_h1 = 24 * (days_from_civil(year + 1, 1, 1) - days_from_civil(iniyear, 1, 1))
  bdtime(1,1) = ly_h0
  bdtime(2,1) = ly_h1
  ttime(1) = 0.5 * real(ly_h0 + ly_h1)

  infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-01-01_00_00_00'
  call landuse_field(infile, outvar_h(:,:,1))

  ! check: the map at the end of the year
  infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-12-31_23_00_00'
  inquire(file=trim(infile), exist=ly_exists)
  if (ly_exists) then
    call landuse_field(infile, ly_last)
    if (maxval(abs(ly_last - outvar_h(:,:,1))) > 1.e-3) &
      write(*,*) 'WARNING: ', trim(vaid), ' changes within ', ayear, ': largest difference ', &
                 maxval(abs(ly_last - outvar_h(:,:,1))), ' (the Jan 1 map is written)'
  endif

  write(ayeari, '(i4)') year
  write(ayearf, '(i4)') year
  call write_output
enddo

contains
!
!----------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_subs
use netcdf

freq='yr'
frequency=trim(adjustl(freq))

outfile=trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_label(ttime(1),ttime(1)))//'.nc'
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
call write_netcdf_rtime_3d(outvar_h, ntime, ttime, bdtime)

deallocate(ttime, bdtime, outvar_h)

end subroutine write_output


end program read_wrfout

program read_wrfout
!
! RCM_fx_landuse — land-cover fractions (fx, % of the grid cell) and the dominant
! land-use category, from LANDUSEF and LU_INDEX of the first wrfout file of the job
! year. For land-use change experiments (LUCAS) use RCM_sfc_landuse (varset landuse),
! which writes them every hour. The variable (vaid in its header):
!
!   treeFrac      % tree cover           (area_type tree)
!   shrubFrac     % shrub cover          (area_type shrubs)
!   grassFrac     % natural grass cover  (area_type natural_grasses)
!   cropFrac      % crop cover           (area_type crops)
!   baresoilFrac  % bare soil            (area_type bare_ground)
!   urbanFrac     % urban                (area_type urban)
!   cnc           % vegetation = tree + shrub + grass + crop
!   luindex       LU_INDEX, dominant land-use category (1)
!
! The grouping of the land-use categories (weight tables) is in landuse_field
! (shared_subs_v2.f90). An existing fx file is kept (fixed field).
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

allocate(outvar(nlon,nlat))

! --- First wrfout file of the job year
write(ayear, '(i4)') yeari
amonth = pad_int(imonth, 2)
aday = pad_int(iday, 2)
ahour = pad_int(ihour, 2)
infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'

call landuse_field(infile, outvar)

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
call write_netcdf_2D(outvar)

deallocate(outvar)

end subroutine write_output


end program read_wrfout

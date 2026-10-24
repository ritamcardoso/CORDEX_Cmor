program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_landuse.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_landuse.f90 and rerun tools/make_varcalendar.py rather than this file.
!
!
! RCM_sfc_landuse — land-cover fractions (1hr, instantaneous: time: point, % of the
! grid cell) and the dominant land-use category, from LANDUSEF and LU_INDEX of every
! wrfout file, for land-use change experiments (LUCAS): the fields follow the maps
! whenever they change, and can be used as masks at any time step.
! The variable (vaid in its header):
!
!   treeFrac      % tree cover           (area_type tree)
!   shrubFrac     % shrub cover          (area_type shrubs)
!   grassFrac     % natural grass cover  (area_type natural_grasses)
!   cropFrac      % crop cover           (area_type crops)
!   baresoilFrac  % bare soil            (area_type bare_ground)
!   urbanFrac     % urban                (area_type urban)
!   cnc           % vegetation = tree + shrub + grass + crop
!   lcvr          LU_INDEX, dominant land-use category (1)
!
! The grouping of the land-use categories (weight tables) is in landuse_field
! (shared_subs_v2.f90); only the categories of the group are read. No sea mask.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none


! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

! instantaneous values: no time bounds
if (index(cellmethods, 'time:') == 0) cellmethods = trim(cellmethods)//' time: point'

! --- Initialising grid and time counters
nzt = nz + 1
nhours = 24


! --- Main Processing Loops ---
allocate(wrfv2D(nlon, nlat))

it = 0
do vc_year = yeari, yearf
  ! the part of the year inside sim_start..sim_end (nothing to do if none)
  if (.not. time_chunk(vc_year, 1, .false.)) cycle
  year = vc_year

  write(ayear, '(i4)') year
  issh = 0

  ! Compute time length and allocate time sensitive variables
  if (mod(year, 4) == 0 .and. year /= 2100) then
      days = days2
      mydays = 366
  else
      days = days1
      mydays = 365
  endif


  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h(nlon, nlat, ntime))

  ! Loop over months
  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        call landuse_field(infile, wrfv2D)


        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h(:,:,issh) = wrfv2D

      enddo loop_h    ! end of the files of the chunk

  ! Write annual output using shared subroutine
  write(ayearf, '(i4)') year
  write(ayeari, '(i4)') year

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

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)
ahourf = pad_int(hour-1, 2)

freq='1hr'
frequency=trim(adjustl(freq))

! Create output filename based on metadata
outfile=trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
fnameout=trim(adjustl(outfile))


call date_and_time(date,times,zone,values)
!
!Values    1    2    3      4       5     6      7       8
!Meaning Year Month Day Time_zone  Hour Minute Second  Millisecond
!                       offset(min)
!
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

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h)

end subroutine write_output


end program read_wrfout

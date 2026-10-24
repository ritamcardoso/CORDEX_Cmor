program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_cVeg.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_cVeg.f90 and rerun tools/make_varcalendar.py rather than this file.
!
!
! RCM_sfc_cVeg — cVeg, carbon mass in vegetation (1hr, instantaneous: time: point, kg m-2): the
! Noah-MP carbon pools leaf LFMASS (wrfvar of the header) + fine roots RTMASS + stem
! STMASS + wood WOOD, g m-2 -> kg m-2. Noah-MP grows these pools directly from its carbon
! fluxes (NPP in g m-2 s-1 C), so they are taken as carbon mass. Meaningful only with
! dynamic vegetation (opt_dveg). Sea points (LANDMASK = 0) are missing.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

! --- Initialising grid and time counters
nzt = nz + 1
nhours = 24


! --- Main Processing Loops ---
allocate(wrfv2D(nlon, nlat))
allocate(lsm_a(nlon, nlat), lsm_b(nlon, nlat), lsm_c(nlon, nlat))

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

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        ! Read wrf var
        status = nf90_inq_varid(ncid, wrfvar, varid)
        call ncerror(status,'getting var id '//trim(wrfvar)//' in '//trim(infile))

        status=nf90_get_var(ncid,varid,wrfv2D,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//trim(wrfvar)//' from '//trim(infile))

        status=nf90_inq_varid(ncid,'RTMASS',varid)
        call ncerror(status,'getting var id RTMASS in '//trim(infile))

        status=nf90_get_var(ncid,varid,lsm_a,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading RTMASS from '//trim(infile))

        status=nf90_inq_varid(ncid,'STMASS',varid)
        call ncerror(status,'getting var id STMASS in '//trim(infile))

        status=nf90_get_var(ncid,varid,lsm_b,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading STMASS from '//trim(infile))

        status=nf90_inq_varid(ncid,'WOOD',varid)
        call ncerror(status,'getting var id WOOD in '//trim(infile))

        status=nf90_get_var(ncid,varid,lsm_c,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading WOOD from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))


        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        where (landmask < 0.5)
          outvar_h(:,:,issh) = huge_val
        elsewhere
          outvar_h(:,:,issh) = 1.e-3 * (wrfv2D + lsm_a + lsm_b + lsm_c)
        endwhere

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
call resample_output        ! output step: outstep of the header (hours; 0 = wp_step of the grid ini)
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

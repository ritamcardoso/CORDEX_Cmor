program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_xtrm.f90, by hand
! (not made by tools/make_varcalendar.py: the wrfxtrm files are monthly, with one record a
! day). For each year yeari..yearf, the days whose 24 hours (day d 00 UTC to day d+1
! 00 UTC) are inside the simulation period sim_start..sim_end of the grid ini.
! The statistics of day d are in the record at day d+1 00 UTC. The file of a month starts
! at 00 UTC of its first day, or of the first day of the simulation (a simulation that
! starts during the month), and has one record a day from there.
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

! --- Initialising grid and time counters
nz = 10
nzt = nz + 1
nhours = 24

! --- Main Processing Loops ---
allocate(outvar_a(nlon,nlat))

do vc_year = yeari, yearf
  ! the days of the year with complete statistics (as interval values of 24 hours: day d
  ! from 00 UTC to day d+1 00 UTC, inside sim_start..sim_end); nothing to do if none
  if (.not. time_chunk(vc_year, 24, .true.)) cycle
  year = vc_year
  write(ayear, '(i4)') year
  write(ayeari,'(i4)') year

  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h(nlon, nlat, ntime))

  ! the days of the chunk, month by month (one wrfxtrm file a month)
  vc_k = 1
  do while (vc_k <= ntime)
    call set_time_step(vc_k)                         ! year, month, day of day vc_k
    vc_nd = min(days(month) - day + 1, ntime - vc_k + 1)  ! days of the chunk in this month
    ! the file of the month: from 00 UTC of its first day, or of the first day of the simulation
    vc_tf = max(hours_since_ini(year, month, 1, 0), t_sim0 + modulo(-t_sim0, 24))
    vc_rec = (hours_since_ini(year, month, day, 0) + 24 - vc_tf) / 24 + 1   ! record of day + 1, 00 UTC
    filename = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'// &
               trim(pad_int(1 + (vc_tf - hours_since_ini(year, month, 1, 0)) / 24, 2))//'_00_00_00'
    infile = trim(filename)
!
    allocate(wrfv3D(nlon,nlat,vc_nd))

    status = nf90_open(infile, nf90_nowrite, ncid)
    call ncerror(status,'opening '//trim(infile))

    ! Read wrf var
!
    status=nf90_inq_varid(ncid,wrfvar,varid)
    call ncerror(status,'getting var id '//trim(wrfvar)//' in '//trim(infile))
!
    status=nf90_get_var(ncid,varid,wrfv3D,(/xoffset,yoffset,vc_rec/),(/nlon,nlat,vc_nd/),(/1,1,1/))
    call ncerror(status,'reading '//trim(wrfvar)//' from '//trim(infile))
!
    status=nf90_close(ncid)
    call ncerror(status,'closing '//trim(infile))

    do vc_kf = 1, vc_nd
      issh = issh + 1
      ish = (t_ch0 / 24) + issh                         ! days since iniyear at the end of the day
      ttime(issh) = float(ish) - 0.5
      bdtime(1, issh) = ish - 1
      bdtime(2, issh) = ish

      outvar_a(:,:)=nint(10000.d0*wrfv3D(:,:,vc_kf))

      outvar_h(:,:,issh)=float(outvar_a(:,:))/10000.d0
    enddo

    deallocate(wrfv3D)
    vc_k = vc_k + vc_nd
  enddo

  write(ayearf, '(i4)') year
!
!  Write annual output using shared subroutine
!
  call write_output

enddo
!
contains
!
!
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_subs
use netcdf

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)

freq='day'
frequency=trim(adjustl(freq))
tunts='days since '//ayearini//'-01-01 00:00'
timeunits=trim(adjustl(tunts))

! Create output filename based on metadata
outfile=trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
fnameout=trim(adjustl(outfile))

if (factor /= 0.) outvar_h = outvar_h * factor

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

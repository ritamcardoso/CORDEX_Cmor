program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_plev_zg.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_plev_zg.f90 and rerun tools/make_varcalendar.py rather than this file.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_io_subs
use vert_interp_subs
use netcdf
!implicit none


! --- Read configuration using shared_io_subs subroutine

call init_cordex_environment
if (ostep < 1) ostep = wp_step       ! output step: outstep of the header (0 or missing: wp_step of the grid ini)

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

! --- Initialising grid and time counters
nzt = nz + 1
nhours = 24


! --- Main Processing Loops ---
allocate(outvar(nlon, nlat), outvar_i(nlon,nlat))
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(ph(nlon, nlat, nzt), phb(nlon, nlat, nzt), phi(nlon, nlat, nzt))
allocate(wrfv3D(nlon, nlat, nz))

it = 0
!
do vc_year = yeari, yearf
  ! the part of the year inside sim_start..sim_end (nothing to do if none)
  if (.not. time_chunk(vc_year, ostep, .false.)) cycle
  year = vc_year

  write(ayear, '(i4)') year
  issh=0

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
!    
  ! Loop over months
  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        ! Read Pressure and Target Variable

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status,'getting var id P in '//trim(infile))

        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading P from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status,'getting var id PB in '//trim(infile))

        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading PB from '//trim(infile))

        ! Read wrf var
        status=nf90_inq_varid(ncid,'PH',varid)
        call ncerror(status,'getting var id PH in '//trim(infile))

        status=nf90_get_var(ncid,varid,ph,(/xoffset,yoffset,1/),(/nlon,nlat,nzt/),(/1,1,1/))
        call ncerror(status,'reading PH from '//trim(infile))

        status=nf90_inq_varid(ncid,'PHB',varid)
        call ncerror(status,'getting var id PHB in '//trim(infile))

        status=nf90_get_var(ncid,varid,phb,(/xoffset,yoffset,1/),(/nlon,nlat,nzt/),(/1,1,1/))
        call ncerror(status,'reading PHB from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
        press = p + pb
!
! Compute variable
!
        phi=(ph+phb)/g

        do iz=1,nz
          wrfv3D(:,:,iz)=(phi(:,:,iz)+phi(:,:,iz+1))/2.
        enddo

        ! levels bracketing presl at every point (map), then the log(p) interpolation
        call plev_map(press, presl)
        call plev_interp(wrfv3D, outvar)
!
        issh = issh + 1
        bdtime(1, issh) = hours_since_ini(year, month, day, hour)
        bdtime(2, issh) = bdtime(1, issh) + ostep
        ttime(issh) = float(bdtime(1, issh))

        outvar_h(:,:,issh)=outvar(:,:)
!
      enddo loop_h    ! end of the files of the chunk
!
! Write Output
!
  write(ayearf, '(i4)') year
  write(ayeari,'(i4)')year
!
  call write_output

enddo

contains
!
!
!-------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_io_subs
use netcdf

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)
ahourf = pad_int(hour-1, 2)

write(freq,'(i0,a)') ostep, 'hr'
frequency=trim(adjustl(freq))

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
! Call the shared NetCDF writer from shared_io_subs
!
call write_netcdf_rtime_3d(outvar_h, ntime, ttime, bdtime)

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h)

end subroutine write_output


end program read_wrfout

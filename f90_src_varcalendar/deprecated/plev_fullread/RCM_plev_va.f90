program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_plev_va.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_plev_va.f90 and rerun tools/make_varcalendar.py rather than this file.
!
use datvar_s
use shared_io_subs
use vert_interp_subs
use netcdf
implicit none

real :: u_unstag, v_unstag
integer :: ix, iy

! Read configuration using shared_io_subs subroutine
call init_cordex_environment
if (ostep < 1) ostep = wp_step       ! output step: outstep of the header (0 or missing: wp_step of the grid ini)

! Read Grid Information (Latitude, Longitude)
call read_geog

! Initialising grid and time counters
nzt = nz + 1
nhours = 24
nlon_u = nlon + 1
nlat_v = nlat + 1


! --- Main Processing Loops ---
allocate(outvar_u(nlon, nlat), outvar_v(nlon, nlat))
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(cosalp(nlon, nlat), sinalp(nlon, nlat))
allocate(ua(nlon_u, nlat, nz), va(nlon, nlat_v, nz))
allocate(wrfv3D_u(nlon, nlat, nz), wrfv3D_v(nlon, nlat, nz))

it = 0

do vc_year = yeari, yearf
  ! the part of the year inside sim_start..sim_end (nothing to do if none)
  if (.not. time_chunk(vc_year, ostep, .false.)) cycle
  year = vc_year

  write(ayear, '(i4)') year
  issh = 0

  if (mod(year, 4) == 0 .and. year /= 2100) then
    days = days2
    mydays = 366
  else
    days = days1
    mydays = 365
  endif

  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h_u(nlon, nlat, ntime))
  allocate(outvar_h_v(nlon, nlat, ntime))

  ! Loop over months
  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        if (status /= nf90_noerr) then
            write(*,*) 'Warning: File skipped or missing: ', trim(infile)
            cycle loop_h
        end if

        if (it == 0) then
          it = it + 1
          status = nf90_inq_varid(ncid, 'COSALPHA', varid)
          call ncerror(status,'getting var id COSALPHA in '//trim(infile))
          status = nf90_get_var(ncid, varid, cosalp, (/xoffset, yoffset/), (/nlon, nlat/))
          call ncerror(status,'reading COSALPHA from '//trim(infile))

          status = nf90_inq_varid(ncid, 'SINALPHA', varid)
          call ncerror(status,'getting var id SINALPHA in '//trim(infile))
          status = nf90_get_var(ncid, varid, sinalp, (/xoffset, yoffset/), (/nlon, nlat/))
          call ncerror(status,'reading SINALPHA from '//trim(infile))
        endif

        ! Read Pressures
        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status,'getting var id P in '//trim(infile))
        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading P from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status,'getting var id PB in '//trim(infile))
        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading PB from '//trim(infile))

        ! Explicitly query and fetch staggered metrics simultaneously
        status = nf90_inq_varid(ncid, 'U', varid)
        call ncerror(status,'getting var id U in '//trim(infile))
        status = nf90_get_var(ncid, varid, ua, (/xoffset, yoffset, 1/), (/nlon_u, nlat, nz/))
        call ncerror(status,'reading U from '//trim(infile))

        status = nf90_inq_varid(ncid, 'V', varid)
        call ncerror(status,'getting var id V in '//trim(infile))
        status = nf90_get_var(ncid, varid, va, (/xoffset, yoffset, 1/), (/nlon, nlat_v, nz/))
        call ncerror(status,'reading V from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))

        press = p + pb

        ! Single pass un-staggering and geographic coordinate frame rotation
        do iz = 1, nz
          do iy = 1, nlat
            do ix = 1, nlon
              u_unstag = (ua(ix, iy, iz) + ua(ix+1, iy, iz)) / 2.0
              v_unstag = (va(ix, iy, iz) + va(ix, iy+1, iz)) / 2.0

              ! Earth-relative Eastward Wind component (U)
              wrfv3D_u(ix, iy, iz) = u_unstag * cosalp(ix, iy) - v_unstag * sinalp(ix, iy)
              
              ! Earth-relative Northward Wind component (V)
              wrfv3D_v(ix, iy, iz) = v_unstag * cosalp(ix, iy) + u_unstag * sinalp(ix, iy)
            enddo
          enddo
        enddo

        ! Perform optimized interpolation (Single-pass vertical search loop)
        ! levels bracketing presl at every point (map, once), then u and v in log(p)
        call plev_map(press, presl)
        call plev_interp(wrfv3D_u, outvar_u)
        call plev_interp(wrfv3D_v, outvar_v)

        issh = issh + 1

        bdtime(1, issh) = hours_since_ini(year, month, day, hour)

        bdtime(2, issh) = bdtime(1, issh) + ostep

        ttime(issh) = float(bdtime(1, issh))

        outvar_h_u(:, :, issh) = outvar_u(:, :)
        outvar_h_v(:, :, issh) = outvar_v(:, :)

      enddo loop_h    ! end of the files of the chunk

  write(ayearf, '(i4)') year
  write(ayeari, '(i4)') year

  call write_dual_output

enddo

contains


subroutine write_dual_output
  use datvar_s
  use shared_io_subs
  use netcdf

  character(len=10) :: p_str
  integer :: p_val

  amonthf = pad_int(month-1, 2)
  adayf = pad_int(day-1, 2)
  ahourf = pad_int(hour-1, 2)

  write(freq,'(i0,a)') ostep, 'hr'
  frequency = trim(adjustl(freq))

  p_val = int(presl / 100.0)
  write(p_str, '(I0)') p_val  ! 'I0' adjusts to the width needed (pad_int(p_val, 1) failed for p >= 100 hPa)
  p_str = adjustl(p_str)

  ! Build unique system output targets natively using context pressure levels
  fnameout_u = trim(dir_out)//'ua'//trim(p_str)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
  fnameout_v = trim(dir_out)//'va'//trim(p_str)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'

  if (factor /= 0.0) then
    outvar_h_u = outvar_h_u * factor
    outvar_h_v = outvar_h_v * factor
  endif

  call date_and_time(date, times, zone, values)
  write(yyyy, '(i4)') values(1)
  mm = pad_int(values(2), 2)
  dd = pad_int(values(3), 2)
  hh = pad_int(values(5), 2)
  mn = pad_int(values(6), 2)
  ss = pad_int(values(7), 2)

  cdate = yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
  creationdate = cdate(1:len_trim(cdate))

  ! Write File 1: Eastward Wind component
  fnameout = trim(adjustl(fnameout_u))
  varname = 'ua'//trim(p_str)
  standardname = 'eastward_wind'
  longname = 'Eastward Wind at ' // trim(p_str) // 'hPa'
  vunits = 'm s-1'
  call write_netcdf_rtime_3d(outvar_h_u, ntime, ttime, bdtime)

  ! Write File 2: Northward Wind component
  fnameout = trim(adjustl(fnameout_v))
  varname = 'va'//trim(p_str)
  standardname = 'northward_wind'
  longname = 'Northward Wind at ' // trim(p_str) // 'hPa'
  vunits = 'm s-1'
  call write_netcdf_rtime_3d(outvar_h_v, ntime, ttime, bdtime)

  deallocate(ttime)
  deallocate(bdtime)
  deallocate(outvar_h_u)
  deallocate(outvar_h_v)

end subroutine write_dual_output

end program read_wrfout

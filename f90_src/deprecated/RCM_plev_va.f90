program read_wrfout
use datvar_s
use shared_subs
use netcdf
implicit none

real :: u_unstag, v_unstag
integer :: ix, iy

! Read configuration using shared_subs subroutine
call init_cordex_environment

! Read Grid Information (Latitude, Longitude)
call read_geog

! Initialising grid and time counters
nzt = nz + 1
nhours = 24
nlon_u = nlon + 1
nlat_v = nlat + 1

! Determine starting hour offset
ish = 0
if (yeari /= iniyear) then
    nyr = yeari - iniyear
    loop_year = iniyear
    do iyl = 1, nyr, 1
        if (mod(loop_year, 4) == 0 .and. loop_year /= 2100) then
            yhours = 366 * nhours
        else
            yhours = 365 * nhours
        endif
        ish = ish + yhours
        loop_year = loop_year + 1
    enddo
endif

! Initial padding for start dates
amonthi = pad_int(imonth, 2)
adayi = pad_int(iday, 2)
ahouri = pad_int(ihour, 2)
if (ihour > 0) ish = ish + ihour - 1

! --- Main Processing Loops ---
allocate(outvar_u(nlon, nlat), outvar_v(nlon, nlat))
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(cosalp(nlon, nlat), sinalp(nlon, nlat))
allocate(ua(nlon_u, nlat, nz), va(nlon, nlat_v, nz))
allocate(wrfv3D_u(nlon, nlat, nz), wrfv3D_v(nlon, nlat, nz))

it = 0

do year = yeari, yearf, 1

  write(ayear, '(i4)') year
  issh = 0

  if (mod(year, 4) == 0 .and. year /= 2100) then
    days = days2
    mydays = 366
  else
    days = days1
    mydays = 365
  endif
  ntime = n_time_steps(year, imonth, nmonths, ihour, wp_step)

  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h_u(nlon, nlat, ntime))
  allocate(outvar_h_v(nlon, nlat, ntime))

  ! Loop over months
  do month = imonth, nmonths, 1
    ndays = days(month)
    amonth = pad_int(month, 2)
    write(*,*) 'Processing Year: ', year, ' Month: ', month

    ! Loop over days
    do day = 1, ndays
      aday_pad = pad_int(day, 2)

      ! Loop over hours
      loop_h: do hour = ihour, 23, wp_step
        ahour = pad_int(hour, 2)

        filename = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday_pad//'_'//ahour//'_00_00'
        infile = trim(filename)

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
        if (presl >= 50000.0) then
          call calc_plev_dual(wrfv3D_u, wrfv3D_v, outvar_u, outvar_v)
        else
          call calc_invplev_dual(wrfv3D_u, wrfv3D_v, outvar_u, outvar_v)
        endif

        issh = issh + 1

        bdtime(1, issh) = hours_since_ini(year, month, day, hour)

        bdtime(2, issh) = bdtime(1, issh) + wp_step

        ttime(issh) = float(bdtime(1, issh))

        outvar_h_u(:, :, issh) = outvar_u(:, :)
        outvar_h_v(:, :, issh) = outvar_v(:, :)

      enddo loop_h
      ihour = 0
      nhours = 24
    enddo
  enddo

  write(ayearf, '(i4)') year
  write(ayeari, '(i4)') year

  call write_dual_output

enddo

contains

subroutine calc_plev_dual(f3d_u, f3d_v, f2d_u, f2d_v)
  real, dimension(nlon, nlat, nz), intent(in)  :: f3d_u, f3d_v
  real, dimension(nlon, nlat),     intent(out) :: f2d_u, f2d_v
  real :: weight_factor
  
  f2d_u = 1.e+20
  f2d_v = 1.e+20
!  pressure(1) = presl
  
  do iy = 1, nlat
    do ix = 1, nlon
      p_loop: do iz = 1, nz - 1
        if (press(ix, iy, iz) < presl) then
          exit p_loop
        endif
        if (press(ix, iy, iz) >= presl .and. press(ix, iy, iz+1) < presl) then
          ! Extract common weighting log factor once
          weight_factor = (log(press(ix, iy, iz)) - log(presl)) / &
                          (log(press(ix, iy, iz)) - log(press(ix, iy, iz+1)))
          
          ! Interpolate both fields simultaneously
          f2d_u(ix, iy) = f3d_u(ix, iy, iz) + weight_factor * (f3d_u(ix, iy, iz+1) - f3d_u(ix, iy, iz))
          f2d_v(ix, iy) = f3d_v(ix, iy, iz) + weight_factor * (f3d_v(ix, iy, iz+1) - f3d_v(ix, iy, iz))
          exit p_loop
        endif
      enddo p_loop
    enddo
  enddo
end subroutine calc_plev_dual

subroutine calc_invplev_dual(f3d_u, f3d_v, f2d_u, f2d_v)
  real, dimension(nlon, nlat, nz), intent(in)  :: f3d_u, f3d_v
  real, dimension(nlon, nlat),     intent(out) :: f2d_u, f2d_v
  real :: weight_factor
  
  f2d_u = 1.e+20
  f2d_v = 1.e+20
!  pressure(1) = presl
  
  do iy = 1, nlat
    do ix = 1, nlon
      p_loop: do iz = nz - 1, 2, -1
        if (press(ix, iy, iz-1) >= presl .and. press(ix, iy, iz) < presl) then
          ! Extract common weighting log factor once
          weight_factor = (log(press(ix, iy, iz-1)) - log(presl)) / &
                          (log(press(ix, iy, iz-1)) - log(press(ix, iy, iz)))
          
          ! Interpolate both fields simultaneously
          f2d_u(ix, iy) = f3d_u(ix, iy, iz-1) + weight_factor * (f3d_u(ix, iy, iz) - f3d_u(ix, iy, iz-1))
          f2d_v(ix, iy) = f3d_v(ix, iy, iz-1) + weight_factor * (f3d_v(ix, iy, iz) - f3d_v(ix, iy, iz-1))
          exit p_loop
        elseif (press(ix, iy, iz) > presl) then
          exit p_loop
        endif
      enddo p_loop
    enddo
  enddo
end subroutine calc_invplev_dual

subroutine write_dual_output
  use datvar_s
  use shared_subs
  use netcdf

  character(len=10) :: p_str
  integer :: p_val

  amonthf = pad_int(month-1, 2)
  adayf = pad_int(day-1, 2)
  ahourf = pad_int(hour-1, 2)

  write(freq,'(i0,a)') wp_step, 'hr'
  frequency = trim(adjustl(freq))

  p_val = int(presl / 100.0)
  write(p_str, '(I0)') p_val  ! 'I0' adjusts to the width needed (pad_int(p_val, 1) failed for p >= 100 hPa)
  p_str = adjustl(p_str)

  ! Build unique system output targets natively using context pressure levels
  fnameout_u = trim(dir_out)//'ua'//trim(p_str)//trim(outdom)//trim(freq)//'_'//trim(time_label(ttime(1),ttime(ntime)))//'.nc'
  fnameout_v = trim(dir_out)//'va'//trim(p_str)//trim(outdom)//trim(freq)//'_'//trim(time_label(ttime(1),ttime(ntime)))//'.nc'

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

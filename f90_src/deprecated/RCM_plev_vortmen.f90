program read_wrfout
!
! RCM_plev_vortmen — relative vorticity (vortmen<p>, s-1, instantaneous) on the pressure
! level pres (Pa) of the header, from the model levels of wrfout. On each model level,
! as wrf-python (avo, without the Coriolis parameter), on the C grid:
!
!   zeta = m^2 [ d(v/m_v)/dx - d(u/m_u)/dy ]
!
!   u, v: U and V of wrfout (grid-relative; the vertical component of the curl does not
!   depend on the orientation of the axes), m_u, m_v, m: MAPFAC_U, MAPFAC_V, MAPFAC_M,
!   dx, dy: DX, DY of the file. Centred differences over the neighbouring mass points
!   (U and V averaged to them); one extra row/column around the output window is read
!   where the full grid has it (else one-sided at the edge).
!
! zeta is interpolated linearly in log(p) to pres, as RCM_plev_wap and RCM_plev_wa (from
! the bottom for pres >= 500 hPa, from the top above); points where pres is below the
! surface or above the model top are missing (1e20).
! Output every wp_step hours (wp_step of the grid's ini: 3 or 6).
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
nzt = nz + 1
nhours = 24

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
allocate(outvar(nlon, nlat), outvar_i(nlon,nlat))
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(wrfv3D(nlon, nlat, nz))
!
! halo around the output window, from the full grid of the first wrfout file
amonth = pad_int(imonth, 2)
aday = pad_int(iday, 2)
ahour = pad_int(ihour, 2)
write(ayear, '(i4)') yeari
infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
status = nf90_open(infile, nf90_nowrite, ncid)
call ncerror(status,'opening '//trim(infile))
status = nf90_inq_dimid(ncid, 'west_east', vo_dimid)
call ncerror(status,'getting the west_east dimension in '//trim(infile))
status = nf90_inquire_dimension(ncid, vo_dimid, len=vo_nxf)
call ncerror(status,'reading the west_east dimension from '//trim(infile))
status = nf90_inq_dimid(ncid, 'south_north', vo_dimid)
call ncerror(status,'getting the south_north dimension in '//trim(infile))
status = nf90_inquire_dimension(ncid, vo_dimid, len=vo_nyf)
call ncerror(status,'reading the south_north dimension from '//trim(infile))
status = nf90_get_att(ncid, nf90_global, 'DX', vo_dx)
call ncerror(status,'reading the DX attribute of '//trim(infile))
status = nf90_get_att(ncid, nf90_global, 'DY', vo_dy)
call ncerror(status,'reading the DY attribute of '//trim(infile))
status = nf90_close(ncid)
call ncerror(status,'closing '//trim(infile))
vo_hw = merge(1, 0, xoffset > 1)
vo_hs = merge(1, 0, yoffset > 1)
vo_he = merge(1, 0, xoffset + nlon - 1 < vo_nxf)
vo_hn = merge(1, 0, yoffset + nlat - 1 < vo_nyf)
vo_nxh = nlon + vo_hw + vo_he
vo_nyh = nlat + vo_hs + vo_hn
write(*,*) 'DX, DY (m):', vo_dx, vo_dy, '  halo W E S N:', vo_hw, vo_he, vo_hs, vo_hn
allocate(u(vo_nxh+1, vo_nyh, nz), v(vo_nxh, vo_nyh+1, nz))
allocate(vo_mu(vo_nxh+1, vo_nyh), vo_mv(vo_nxh, vo_nyh+1), vo_mt(vo_nxh, vo_nyh))

it = 0
!
do year = yeari, yearf,1

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
  ntime = n_time_steps(year, imonth, nmonths, ihour, wp_step)

  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h(nlon, nlat, ntime))
!    
  ! Loop over months
  do month = imonth, nmonths,1

    ndays = days(month)
    amonth = pad_int(month, 2)
!
    write(*,*)year,month

    ! Loop over days
    do day = 1, ndays
      aday = pad_int(day, 2)

      ! Loop over hours
      loop_h: do hour = ihour, 23, wp_step
        ahour = pad_int(hour, 2)

        filename = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

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

        ! Winds on the staggered grid and the map factors, with the halo
        status = nf90_inq_varid(ncid, 'U', varid)
        call ncerror(status,'getting var id U in '//trim(infile))
        status = nf90_get_var(ncid, varid, u, (/xoffset-vo_hw, yoffset-vo_hs, 1/), (/vo_nxh+1, vo_nyh, nz/))
        call ncerror(status,'reading U from '//trim(infile))

        status = nf90_inq_varid(ncid, 'V', varid)
        call ncerror(status,'getting var id V in '//trim(infile))
        status = nf90_get_var(ncid, varid, v, (/xoffset-vo_hw, yoffset-vo_hs, 1/), (/vo_nxh, vo_nyh+1, nz/))
        call ncerror(status,'reading V from '//trim(infile))

        status = nf90_inq_varid(ncid, 'MAPFAC_U', varid)
        call ncerror(status,'getting var id MAPFAC_U in '//trim(infile))
        status = nf90_get_var(ncid, varid, vo_mu, (/xoffset-vo_hw, yoffset-vo_hs/), (/vo_nxh+1, vo_nyh/))
        call ncerror(status,'reading MAPFAC_U from '//trim(infile))

        status = nf90_inq_varid(ncid, 'MAPFAC_V', varid)
        call ncerror(status,'getting var id MAPFAC_V in '//trim(infile))
        status = nf90_get_var(ncid, varid, vo_mv, (/xoffset-vo_hw, yoffset-vo_hs/), (/vo_nxh, vo_nyh+1/))
        call ncerror(status,'reading MAPFAC_V from '//trim(infile))

        status = nf90_inq_varid(ncid, 'MAPFAC_M', varid)
        call ncerror(status,'getting var id MAPFAC_M in '//trim(infile))
        status = nf90_get_var(ncid, varid, vo_mt, (/xoffset-vo_hw, yoffset-vo_hs/), (/vo_nxh, vo_nyh/))
        call ncerror(status,'reading MAPFAC_M from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
        press = p + pb
!
! Compute variable: vorticity on the model levels (wrfv3D), then on the pressure level
!
        call calc_vort
!
        if(presl >= 50000.)then
          call calc_plev
        else
          call calc_invplev
        endif
!
        issh = issh + 1
        bdtime(1, issh) = hours_since_ini(year, month, day, hour)
        bdtime(2, issh) = bdtime(1, issh) + wp_step
        ttime(issh) = float(bdtime(1, issh))

        outvar_h(:,:,issh)=outvar(:,:)
!
      enddo loop_h    ! end hour
!
      ihour=0
      nhours=24
!
    enddo             ! end day
  enddo               ! end month
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
!-------------------------------------------------------------------------------------------------------------------
!
subroutine calc_vort
! relative vorticity on the model levels (wrfv3D), wrf-python avo without Coriolis:
! (ix, iy) of the window is (vo_i, vo_j) of the arrays with halo
!
do iz=1,nz
  do iy=1,nlat
    do ix=1,nlon
      vo_i  = ix + vo_hw
      vo_j  = iy + vo_hs
      vo_ip = min(vo_i+1, vo_nxh); vo_im = max(vo_i-1, 1)
      vo_jp = min(vo_j+1, vo_nyh); vo_jm = max(vo_j-1, 1)
      vo_dudy = 0.5 * (u(vo_i,vo_jp,iz)/vo_mu(vo_i,vo_jp) + u(vo_i+1,vo_jp,iz)/vo_mu(vo_i+1,vo_jp) &
                     - u(vo_i,vo_jm,iz)/vo_mu(vo_i,vo_jm) - u(vo_i+1,vo_jm,iz)/vo_mu(vo_i+1,vo_jm)) &
                / (real(vo_jp - vo_jm) * vo_dy)
      vo_dvdx = 0.5 * (v(vo_ip,vo_j,iz)/vo_mv(vo_ip,vo_j) + v(vo_ip,vo_j+1,iz)/vo_mv(vo_ip,vo_j+1) &
                     - v(vo_im,vo_j,iz)/vo_mv(vo_im,vo_j) - v(vo_im,vo_j+1,iz)/vo_mv(vo_im,vo_j+1)) &
                / (real(vo_ip - vo_im) * vo_dx)
      wrfv3D(ix,iy,iz) = vo_mt(vo_i,vo_j)**2 * (vo_dvdx - vo_dudy)
    enddo
  enddo
enddo
!
end subroutine calc_vort
!
!-------------------------------------------------------------------------------------------------------------------
!
subroutine calc_plev
use datvar_s
!
outvar=1.e+20
presure=presl
!
do isy=1,nlat
  do isx=1,nlon
    p_loop: do iz=1,nz-1
      if(press(isx,isy,iz) < presl)then
!        write(*,*)'p < plev',isx,isy,presl
        exit p_loop
      endif
      if(press(isx,isy,iz) >= presl .and. press(isx,isy,iz+1) < presl)then

        outvar(isx,isy)=wrfv3D(isx,isy,iz)+((log(press(isx,isy,iz))-log(presl))/   &
            (log(press(isx,isy,iz))-log(press(isx,isy,iz+1))))*(wrfv3D(isx,isy,iz+1)-wrfv3D(isx,isy,iz))
        exit p_loop
      endif
    enddo p_loop
  enddo
enddo
!
end
!
!-------------------------------------------------------------------------------------------------------------------
!
subroutine calc_invplev
use datvar_s
!
outvar=1.e+20
presure=presl
!
do isy=1,nlat
  do isx=1,nlon
    p_loop: do iz=nz-1,2,-1   ! iz-1 >= 1 (as the other RCM_plev programs)
      if(press(isx,isy,iz-1) >= presl .and. press(isx,isy,iz) < presl)then

        outvar(isx,isy)=wrfv3D(isx,isy,iz-1)+((log(press(isx,isy,iz-1))-log(presl))/   &
            (log(press(isx,isy,iz-1))-log(press(isx,isy,iz))))*(wrfv3D(isx,isy,iz)-wrfv3D(isx,isy,iz-1))
        exit p_loop
      elseif(press(isx,isy,iz) > presl)then
!        write(*,*)'p < plev',isx,isy,presl
        exit p_loop
      endif
    enddo p_loop
  enddo
enddo
!
end
!
!
!-------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_subs
use netcdf

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)
ahourf = pad_int(hour-1, 2)

write(freq,'(i0,a)') wp_step, 'hr'
frequency=trim(adjustl(freq))

! Create output filename based on metadata
outfile=trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_label(ttime(1),ttime(ntime)))//'.nc'
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

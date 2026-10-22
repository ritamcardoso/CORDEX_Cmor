program read_wrfout
!
! RCM_plev_wap — omega, the vertical velocity in pressure coordinates (wap<p>, Pa s-1,
! instantaneous), on the pressure level pres (Pa) of the header, from the model
! levels of wrfout:
!
!   omega = -rho g w,   rho = p / (Rd Tv),   Tv = T (epsilon + r) / (epsilon (1 + r))
!
!   p  = P + PB,   T = (theta' + 300) (p / 1e5)**rcp  (theta' = T of wrfout),
!   r  = QVAPOR (mixing ratio),   w = W averaged from the staggered levels to the
!   mass levels.
!
! Omega is computed on the model levels and interpolated linearly in log(p) to pres,
! as RCM_plev_wa (from the bottom for pres >= 500 hPa, from the top above); points
! where pres is below the surface or above the model top are missing (1e20).
! Output every wp_step hours (wp_step of the grid's ini: 3 or 6).
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

real, dimension(:,:,:), allocatable :: wp_w, wp_t, wp_q, wp_om
real :: wp_tv

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
allocate(wp_w(nlon, nlat, nz+1), wp_t(nlon, nlat, nz), wp_q(nlon, nlat, nz), wp_om(nlon, nlat, nz))

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

        ! Vertical velocity (staggered: nz+1 levels), potential temperature perturbation
        ! and water vapour mixing ratio
        status = nf90_inq_varid(ncid, 'W', varid)
        call ncerror(status,'getting var id W in '//trim(infile))
        status = nf90_get_var(ncid, varid, wp_w, (/xoffset, yoffset, 1/), (/nlon, nlat, nz+1/))
        call ncerror(status,'reading W from '//trim(infile))

        status = nf90_inq_varid(ncid, 'T', varid)
        call ncerror(status,'getting var id T in '//trim(infile))
        status = nf90_get_var(ncid, varid, wp_t, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading T from '//trim(infile))

        status = nf90_inq_varid(ncid, 'QVAPOR', varid)
        call ncerror(status,'getting var id QVAPOR in '//trim(infile))
        status = nf90_get_var(ncid, varid, wp_q, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading QVAPOR from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
        press = p + pb
!
! Compute variable: omega on the model levels (wrfv3D), then on the pressure level
!
        call calc_omega
        wrfv3D = wp_om
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
subroutine calc_omega
! omega = -rho g w on the model levels (wp_om), from press, wp_w, wp_t, wp_q
!
do iz=1,nz
  do iy=1,nlat
    do ix=1,nlon
      wp_tv = (wp_t(ix,iy,iz) + 300.) * (press(ix,iy,iz) / pconst)**rcp            ! temperature (K)
      wp_tv = wp_tv * (epsilon + wp_q(ix,iy,iz)) / (epsilon * (1. + wp_q(ix,iy,iz)))  ! virtual temperature
      wp_om(ix,iy,iz) = -g * press(ix,iy,iz) / (Rd * wp_tv) * 0.5 * (wp_w(ix,iy,iz) + wp_w(ix,iy,iz+1))
    enddo
  enddo
enddo
!
end subroutine calc_omega
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

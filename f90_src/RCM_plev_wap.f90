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
! with the level map of plev_map and plev_interp (shared_subs_v2.f90); points
! where pres is below the surface or above the model top are missing (1e20).
! Output every wp_step hours (wp_step of the grid's ini: 3 or 6).
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

! --- Read configuration using shared_subs subroutine

call init_cordex_environment
if (ostep < 1) ostep = wp_step       ! output step: outstep of the header (0 or missing: wp_step of the grid ini)

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
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, 0:nz))
allocate(psf(nlon, nlat))          ! surface pressure: press(:,:,0)
allocate(t2(nlon, nlat), q2(nlon, nlat))
allocate(wrfv3D(nlon, nlat, 0:nz))
allocate(w(nlon, nlat, nz+1), t(nlon, nlat, nz), qv(nlon, nlat, nz))

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
  ntime = n_time_steps(year, imonth, nmonths, ihour, ostep)

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
      loop_h: do hour = ihour, 23, ostep
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

        status = nf90_inq_varid(ncid, 'PSFC', varid)
        call ncerror(status,'getting var id PSFC in '//trim(infile))
        status = nf90_get_var(ncid, varid, psf, (/xoffset, yoffset/), (/nlon, nlat/))
        call ncerror(status,'reading PSFC from '//trim(infile))

        press(:,:,1:nz) = p + pb
        press(:,:,0) = psf                  ! level 0: the surface
!
        ! levels bracketing presl at every point (map), and the levels plev_interp needs:
        ! plev_k1..plev_k2, the only levels of T and QVAPOR that are read (W, staggered:
        ! the faces plev_k1..plev_k2+1)
        call plev_map_s(press, presl)
!
        ! Vertical velocity (staggered: nz+1 levels), potential temperature perturbation
        ! and water vapour mixing ratio
        status = nf90_inq_varid(ncid, 'W', varid)
        call ncerror(status,'getting var id W in '//trim(infile))
        status = nf90_get_var(ncid, varid, w(:,:,plev_k1:plev_k2+1), (/xoffset, yoffset, plev_k1/), (/nlon, nlat, plev_nk+1/))
        call ncerror(status,'reading W from '//trim(infile))

        status = nf90_inq_varid(ncid, 'T', varid)
        call ncerror(status,'getting var id T in '//trim(infile))
        status = nf90_get_var(ncid, varid, t(:,:,plev_k1:plev_k2), (/xoffset, yoffset, plev_k1/), (/nlon, nlat, plev_nk/))
        call ncerror(status,'reading T from '//trim(infile))

        status = nf90_inq_varid(ncid, 'QVAPOR', varid)
        call ncerror(status,'getting var id QVAPOR in '//trim(infile))
        status = nf90_get_var(ncid, varid, qv(:,:,plev_k1:plev_k2), (/xoffset, yoffset, plev_k1/), (/nlon, nlat, plev_nk/))
        call ncerror(status,'reading QVAPOR from '//trim(infile))

        ! surface value of the variable (level 0)
        status = nf90_inq_varid(ncid, 'T2', varid)
        call ncerror(status,'getting var id T2 in '//trim(infile))
        status = nf90_get_var(ncid, varid, t2, (/xoffset, yoffset/), (/nlon, nlat/))
        call ncerror(status,'reading T2 from '//trim(infile))
        status = nf90_inq_varid(ncid, 'Q2', varid)
        call ncerror(status,'getting var id Q2 in '//trim(infile))
        status = nf90_get_var(ncid, varid, q2, (/xoffset, yoffset/), (/nlon, nlat/))
        call ncerror(status,'reading Q2 from '//trim(infile))
        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
! Compute variable: omega on the model levels plev_k1..plev_k2 (wrfv3D), then on the
! pressure level
!
        call calc_omega
        ! surface: -rho g w at the lowest face, rho from PSFC and the 2-m virtual temperature
        if (plev_sfc) wrfv3D(:,:,0) = -g * psf / (Rd * t2 * (epsilon + q2) / (epsilon * (1. + q2))) * w(:,:,1)
        call plev_interp_s(wrfv3D, outvar)
!
        issh = issh + 1
        bdtime(1, issh) = hours_since_ini(year, month, day, hour)
        bdtime(2, issh) = bdtime(1, issh) + ostep
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
! omega = -rho g w on the model levels (wp_om), from press, wp_w, wp_t, wp_q; only on the
! levels plev_k1..plev_k2 that plev_interp needs
!
do iz=plev_k1,plev_k2
  do iy=1,nlat
    do ix=1,nlon
      tv = (t(ix,iy,iz) + 300.) * (press(ix,iy,iz) / pconst)**rcp            ! temperature (K)
      tv = tv * (epsilon + qv(ix,iy,iz)) / (epsilon * (1. + qv(ix,iy,iz)))  ! virtual temperature
      wrfv3D(ix,iy,iz) = -g * press(ix,iy,iz) / (Rd * tv) * 0.5 * (w(ix,iy,iz) + w(ix,iy,iz+1))
    enddo
  enddo
enddo
!
end subroutine calc_omega
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

write(freq,'(i0,a)') ostep, 'hr'
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

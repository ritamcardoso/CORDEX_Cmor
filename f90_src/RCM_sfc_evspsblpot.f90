program read_wrfout
!
! Hourly potential evapotranspiration (evspsblpot, 1hr, kg m-2 s-1), following
! FAO-56 Penman-Monteith reference evapotranspiration, hourly form (Allen et al.
! 1998, FAO Irrigation and Drainage Paper 56, eq. 53):
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use humidity_subs
use netcdf
!implicit none

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

! --- Initialising grid and time counters
nz = 10
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
allocate(wrfv2D(nlon,nlat), i_wrfv2D(nlon,nlat))
allocate(t2(nlon,nlat), q2(nlon,nlat), psf(nlon,nlat), wind10(nlon,nlat))
allocate(t2_i(nlon,nlat), q2_i(nlon,nlat), psf_i(nlon,nlat), wind10_i(nlon,nlat))
allocate(Rn(nlon,nlat), Rn_i(nlon,nlat), u_s(nlon,nlat), v_s(nlon,nlat))

it = 0
yearf=yeari+1
!
do year = yeari, yearf,1

  write(ayear, '(i4)') year
 !
  if(year == yearf)then
    nmonths=1
  endif
!
  if(it == 0)then
    write(ayeari,'(i4)')year
    issh=0

  ! Compute time length and allocate time sensitive variables
    if (mod(year, 4) == 0 .and. year /= 2100) then
      days = days2
      mydays = 366
    else
      days = days1
      mydays = 365
    endif
    ntime = mydays * nhours

    if (ihour > 0) then
      nhours=nhours-ihour+1
      ntime = ntime - ihour + 1
    endif

    allocate(ttime(ntime))
    allocate(bdtime(2, ntime))
    allocate(outvar_h(nlon, nlat, ntime))
  endif

  ! Loop over months
  do month = imonth, nmonths

    ndays = days(month)
    amonth = pad_int(month, 2)
!
   if(year == yearf)then
      ndays=1
      nhours=1
    endif
!
    write(*,*)year,month

    ! Loop over days
    do day = 1, ndays
      aday = pad_int(day, 2)

      ! Loop over hours
      loop_h: do hour = ihour, nhours-1,1

        ahour = pad_int(hour, 2)

        filename = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))
!
        ! Read wrf var
        status=nf90_inq_varid(ncid,'T2',varid)
        call ncerror(status,'getting var id T2 in '//trim(infile))

        status=nf90_get_var(ncid,varid,t2,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading T2 from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'Q2',varid)
        call ncerror(status,'getting var id Q2 in '//trim(infile))

        status=nf90_get_var(ncid,varid,q2,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading Q2 from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'PSFC',varid)
        call ncerror(status,'getting var id PSFC in '//trim(infile))

        status=nf90_get_var(ncid,varid,psf,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading PSFC from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'U10',varid)
        call ncerror(status,'getting var id U10 in '//trim(infile))

        status=nf90_get_var(ncid,varid,u_s,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading U10 from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'V10',varid)
        call ncerror(status,'getting var id V10 in '//trim(infile))

        status=nf90_get_var(ncid,varid,v_s,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading V10 from '//trim(infile))

        wind10 = sqrt(u_s**2 + v_s**2)
!
        ! accumulated net radiation (J m-2): SW down - SW up + LW down - LW up, with the buckets
        Rn = 0.d0
        do ir = 1, 4

          fname=trim(rad_Jm(ir))
          wrfvar=trim(fname)

          status=nf90_inq_varid(ncid,wrfvar,varid)
          call ncerror(status,'getting var id '//trim(wrfvar)//' in '//trim(infile))
!
          status=nf90_get_var(ncid,varid,wrfv2D,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
          call ncerror(status,'reading '//trim(wrfvar)//' from '//trim(infile))
!
          fname='I_'//trim(wrfvar)
          iwrfvar=trim(fname)

          status=nf90_inq_varid(ncid,iwrfvar,varid)
          call ncerror(status,'getting var id '//trim(iwrfvar)//' in '//trim(infile))
!
          status=nf90_get_var(ncid,varid,i_wrfv2D,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
          call ncerror(status,'reading '//trim(iwrfvar)//' from '//trim(infile))

          Rn = Rn + rad_sign(ir) * (real(wrfv2D, 8) + real(i_wrfv2D, 8) * 1.d9)
        enddo
!
        status=nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
! Compute variable
!
        if(it == 0)then
          it=it+1
!
          call keep_previous

          cycle loop_h
        endif

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 0.5
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        call calc_evspsblpot
!
        call keep_previous

      enddo loop_h    ! end hour
!
      ihour=0
      nhours=24
!
    enddo             ! end day
  enddo               ! end month

  write(ayearf, '(i4)') year

enddo
!
!  Write annual output
!
call write_output
!
contains
!
!----------------------------------------------------------------------------------------------------
!
subroutine keep_previous
!        
! fields from the previous hour
!
t2_i = t2 
q2_i = q2 
psf_i = psf
wind10_i = wind10
Rn_i = Rn
!
end subroutine keep_previous
!
!----------------------------------------------------------------------------------------------------
!
subroutine calc_evspsblpot
!
! Potential evapotranspiration (evspsblpot, 1hr, kg m-2 s-1),
! FAO-56 Penman-Monteith reference evapotranspiration, hourly form (Allen et al.
! 1998, FAO Irrigation and Drainage Paper 56, eq. 53):
!
!   ET0 = [0.408 D (Rn - G) + gam 37/(T+273) u2 (es - ea)] / [D + gam (1 + 0.34 u2)]   (mm h-1)
!
!   Rn   net radiation (MJ m-2 h-1): hourly mean of SW down - SW up + LW down - LW up,
!        from the accumulated WRF fields (ACSWDNB, ACSWUPB, ACLWDNB, ACLWUPB + I_ buckets)
!   G    soil heat flux (MJ m-2 h-1): 0.1 Rn when Rn > 0 (day), 0.5 Rn otherwise (night) (eq. 45-46)
!   T    2 m air temperature (degC), mean of the hour (T2)
!   u2   2 m wind speed: 0.748 x 10 m wind speed (eq. 47), mean of the hour (U10, V10)
!   es   saturation vapour pressure at T (kPa): ITS-90 / Wexler formula over water with the
!        enhancement factor (Goff 1949), as hurs and cape (es_wexler_dt in humidity_subs.f90),
!        instead of the FAO-56 Tetens formula (eq. 11)
!   ea   actual vapour pressure (kPa) from the specific humidity: q p / (0.622 + 0.378 q) (Q2, PSFC)
!   D    slope of the saturation vapour pressure curve (kPa degC-1): the exact derivative of
!        that es (es_wexler_dt), instead of FAO-56 eq. 13
!   gam  psychrometric constant: 0.665e-3 p (kPa degC-1) (eq. 8), with the model surface pressure p (PSFC)
!
! ET0 (mm h-1 = kg m-2 h-1) / 3600 -> kg m-2 s-1. Sea points (LANDMASK = 0) are missing
! ("area: mean where land"). Negative values (condensation, mostly at night) are kept.
!
do ix=1,nlon
  do iy=1,nlat
    if (landmask(ix,iy) > 0.) then
      t2_C   = 0.5 * (t2(ix,iy) + t2_i(ix,iy)) - 273.15                        ! degC
      q2_m   = 0.5 * (q2(ix,iy) + q2_i(ix,iy))                                 ! kg kg-1
      psf_kPa = 0.5 * (psf(ix,iy) + psf_i(ix,iy)) / 1000.                      ! kPa
      wind2   = 0.748 * 0.5 * (wind10(ix,iy) + wind10_i(ix,iy))                ! m s-1 at 2 m
      Rn_MJ   = real((Rn(ix,iy) - Rn_i(ix,iy)) * 1.d-6)                        ! MJ m-2 h-1
      if (Rn_MJ > 0.) then
        ghf = 0.1 * Rn_MJ
      else
        ghf = 0.5 * Rn_MJ
      endif
      ! saturation vapour pressure and its slope: as hurs and cape (Wexler / ITS-90, enhancement factor)
      call es_wexler_dt(real(t2_C, 8) + 273.15d0, 1000.d0 * real(psf_kPa, 8), es_pa, des_pa)
      es_kPa = real(es_pa / 1000.d0)                                           ! kPa
      vpres = q2_m * psf_kPa / (0.622 + 0.378 * q2_m)                          ! kPa
      slope = real(des_pa / 1000.d0)                                           ! kPa degC-1
      gam = 0.665e-3 * psf_kPa                                                 ! kPa degC-1
      ET0 = (0.408 * slope * (Rn_MJ - ghf) &
               + gam * (37. / (t2_C + 273.)) * wind2 * (es_kPa - vpres)) &
              / (slope + gam * (1. + 0.34 * wind2))                            ! mm h-1
      outvar_h(ix,iy,issh) = ET0 / 3600.                                       ! kg m-2 s-1
    else
      outvar_h(ix,iy,issh) = 1.e+20
    endif
  enddo
enddo
!
end subroutine calc_evspsblpot
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

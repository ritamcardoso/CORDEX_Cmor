
!
program read_wrfout
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
allocate(outvar(nlon, nlat))
allocate(wrfv2D(nlon, nlat))
allocate(p(nlon,nlat,1))
allocate(pb(nlon,nlat,1))
allocate(t(nlon,nlat,1))
allocate(pres_s(nlon,nlat))
allocate(psf(nlon,nlat))
allocate(t_l(nlon,nlat))
allocate(phi_s(nlon,nlat))
!
it = 0
do year = yeari, yearf,1

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
  ntime = mydays * nhours

  if (ihour > 0) then
    nhours=nhours-ihour+1
    ntime = ntime - ihour + 1
  endif

  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h(nlon, nlat, ntime))

  ! Loop over months
  do month = imonth, nmonths

    ndays = days(month)
    amonth = pad_int(month, 2)

    ! Loop over days
    do day = 1, ndays
      aday = pad_int(day, 2)

      ! Loop over hours
      loop_h: do hour = ihour, nhours-1,1

        ahour = pad_int(hour, 2)

        filename = trim(dir)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening file')

        ! Read wrf var
          status=nf90_inq_varid(ncid,'P',varid)
          call ncerror(status,'getting var id')

          status=nf90_get_var(ncid,varid,p,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
          call ncerror(status,'reading '//'P')

          status=nf90_inq_varid(ncid,'PB',varid)
          call ncerror(status,'getting var id')

          status=nf90_get_var(ncid,varid,pb,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
          call ncerror(status,'reading '//'PB')
!
          pres_s(:,:)=p(:,:,1)+pb(:,:,1)
!
          status=nf90_inq_varid(ncid,'PH',varid)
          call ncerror(status,'getting var id')

          status=nf90_get_var(ncid,varid,p,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
          call ncerror(status,'reading '//'PH')

          status=nf90_inq_varid(ncid,'PHB',varid)
          call ncerror(status,'getting var id')

          status=nf90_get_var(ncid,varid,pb,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
          call ncerror(status,'reading '//'PHB')
!
          phi_s(:,:)=p(:,:,1)+pb(:,:,1)
!
          status=nf90_inq_varid(ncid,'T',varid)
          call ncerror(status,'getting var id')

          status=nf90_get_var(ncid,varid,t,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
          call ncerror(status,'reading '//'T')
!
          t_l(:,:)=(t(:,:,1)+300.)*(pres_s(:,:)/pconst)**rcp
!
        status=nf90_inq_varid(ncid,wrfvar,varid)
        call ncerror(status,'getting var id')
!
        status=nf90_get_var(ncid,varid,wrfv2D,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//wrfvar)
!
        status=nf90_close(ncid)
        call ncerror(status,'closing file')
!
! Compute variable
!
        psf(:,:)=wrfv2D(:,:)
!
        call calcslptwo

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h(:,:,issh)=outvar(:,:)

      enddo loop_h    ! end hour
!
      ihour=0
      nhours=24
!
    enddo             ! end day
  enddo               ! end month

  ! Write annual output using shared subroutine
  write(ayearf, '(i4)') year
  write(ayeari, '(i4)') year

  call write_output

enddo

contains
!
!===============================================================================
!
!(lah): fullpos_cy38 routine
!(lah): this code resembles the algorithm described in chapter 4 of "FULL-POS in
!       the cycle 38 of ARPEGE/IFS" by Yessad K. (Meteo-France/CNRM/GMAP/ALGO),
!       November 10, 2011. The equation can be found especially in the section
!       (4.3.1) "Mean sea level pressure PP_msl (routine PPPMER)"

subroutine calcslptwo
use datvar_s
!real, dimension(:,:),   intent(out) :: outvar        !(output) sea level pressure
!real, dimension(:,:),   intent(in)  :: phi_s      !(input) 2d geopotential of the surface
!real, dimension(:,:),   intent(in)  :: t_l        !(input) temperature at lowest level

real                                :: t_surf     !(calculated) surface temperature
real                                :: gamma_mod  !(calculated) modified lapse rate that is actually used for calculationlat
real                                :: x          !(calculated) expanlation coefficient of (eq. 9)
real                                :: t_0        !(calculated) auxiliary variable

do j = 1,nlon
  do k = 1,nlat

    !always assume none of the if conditionlat trigger, then (according to step 5)
    gamma_mod = gamma

    !(0) if abs(phi_s)<0.001 ("sea" grid cells) then set slp to surface pressure
    if (abs(phi_s(j,k)).lt.0.001) then

      outvar(j,k) = psf(j,k) !in this case we are done with this grid cell

    else !else apply the following algorithm

      !always assume none of the following if conditionlat trigger
      !then we use the conlattant camma (accoRding to step 5)
      gamma_mod = gamma

      !(1) compute t_surf according to eq (1)
      !t_surf = t_l + gamma*(Rd/g)*(psf/pres-1.0)*t_l
      t_surf = t_l(j,k) + gamma * (Rd/g) * ( psf(j,k)/pres_s(j,k) - 1.0 ) * t_l(j,k)

      !(2) compute t_0=t_surf+gamma*phi_s/g
      t_0 = t_surf + gamma * phi_s(j,k) / g

      !(3) to avoid extrapolation of too low pressures over high and warm surfaces:
      ! if (t_0 > 290.5):
      !    if (t_surf <= 290.5): gamma_mod=(290.5-t_surf)*g/phi_s (eq. 7)
      !    else: gamma_mod=0.0, t_surf=0.5*(290.5+t_surf)
      if (t_0 .gt. 290.5) then
        if (t_surf .le. 290.5) then
          gamma_mod = ( 290.5 - t_surf ) * g / phi_s(j,k)
        else
          gamma_mod = 0.0
          t_surf = 0.5 * ( 290.5 + t_surf )
        endif
      endif

      !(4) to avoid extrapolation of too high pressures over cold surfaces:
      ! if t_surf < 255: gamma_mod=gamma, t_surf=0.5*(255+t_surf)
      if (t_surf .lt. 255.0) then
        gamma_mod = gamma
        t_surf = 0.5 * ( 255.0 + t_surf )
      endif

      !(5) in other cases set gamma_mod=gamma
      !this was already done in the beginning of the loop!

      !(6) compute mean sea level pressure (eq. 8) using the above determined parameters
      !x=gamma_mod*phi_s/(g*t_surf)
      !slp=psf*exp(phi_s/(r_d*t_surf)*(1-x/2.+x*x/3.))
      x = gamma_mod * phi_s(j,k) / ( g * t_surf )
      outvar(j,k) = psf(j,k) * exp( phi_s(j,k) / (Rd * t_surf ) * (1.0 - x/2. + x*x/3.) )
      !done.
    end if
  enddo
enddo

end subroutine calcslptwo
        
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
outfile=trim(dir2)//trim(vaid)//trim(outdom)//trim(freq)//'_'//ayeari//amonthi//adayi//ahouri//'-'//ayearf//amonthf//adayf//ahourf//'.nc'
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

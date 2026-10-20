program read_wrfout
!
! RCM_sfc_evspsblpot — potential evapotranspiration (evspsblpot, 1hr, kg m-2 s-1),
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
!   es   saturation vapour pressure at T (kPa): 0.6108 exp(17.27 T / (T + 237.3)) (eq. 11)
!   ea   actual vapour pressure (kPa) from the specific humidity: q p / (0.622 + 0.378 q) (Q2, PSFC)
!   D    slope of the saturation vapour pressure curve: 4098 es / (T + 237.3)^2 (eq. 13)
!   gam  psychrometric constant: 0.665e-3 p (kPa degC-1) (eq. 8), with the model surface pressure p (PSFC)
!
! The instantaneous fields are averaged over each hour (start and end of the hour),
! as for the other hourly means; the value is written at hh:30 with bounds hh:00-hh+1:00.
! ET0 (mm h-1 = kg m-2 h-1) / 3600 -> kg m-2 s-1. Sea points (LANDMASK = 0) are missing
! ("area: mean where land"). Negative values (condensation, mostly at night) are kept.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

! Fields of the previous and the current hour
real, dimension(:,:), allocatable :: pe_t, pe_q, pe_p, pe_w, pe_tp, pe_qp, pe_pp, pe_wp
real(kind=8), dimension(:,:), allocatable :: pe_rn, pe_rnp
real, dimension(:,:), allocatable :: pe_u, pe_v
real :: pe_tc, pe_qm, pe_pk, pe_u2, pe_rnmj, pe_g, pe_es, pe_ea, pe_dl, pe_gm, pe_et
character(len=8), dimension(4), parameter :: pe_rad = ['ACSWDNB ', 'ACSWUPB ', 'ACLWDNB ', 'ACLWUPB ']
real, dimension(4), parameter :: pe_sign = [1., -1., 1., -1.]
integer :: ir


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
allocate(pe_t(nlon,nlat), pe_q(nlon,nlat), pe_p(nlon,nlat), pe_w(nlon,nlat))
allocate(pe_tp(nlon,nlat), pe_qp(nlon,nlat), pe_pp(nlon,nlat), pe_wp(nlon,nlat))
allocate(pe_rn(nlon,nlat), pe_rnp(nlon,nlat), pe_u(nlon,nlat), pe_v(nlon,nlat))

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
        call ncerror(status,'opening file')
!
        call read_field('T2', pe_t)
        call read_field('Q2', pe_q)
        call read_field('PSFC', pe_p)
        call read_field('U10', pe_u)
        call read_field('V10', pe_v)
        pe_w = sqrt(pe_u**2 + pe_v**2)
!
        ! accumulated net radiation (J m-2): SW down - SW up + LW down - LW up, with the buckets
        pe_rn = 0.d0
        do ir = 1, 4
          call read_field(trim(pe_rad(ir)), wrfv2D)
          call read_field('I_'//trim(pe_rad(ir)), i_wrfv2D)
          pe_rn = pe_rn + pe_sign(ir) * (real(wrfv2D, 8) + real(i_wrfv2D, 8) * 1.d9)
        enddo
!
        status=nf90_close(ncid)
        call ncerror(status,'closing file')
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
!  Write annual output using shared subroutine
!
call write_output
!
contains
!
!----------------------------------------------------------------------------------------------------
!
subroutine read_field(vname, field)
! one 2-D field of the open wrfout file (ncid), cut to the output grid
character(len=*), intent(in) :: vname
real, dimension(:,:), intent(out) :: field
!
status=nf90_inq_varid(ncid,vname,varid)
call ncerror(status,'getting var id '//vname)
status=nf90_get_var(ncid,varid,field,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//vname)
!
end subroutine read_field
!
!----------------------------------------------------------------------------------------------------
!
subroutine keep_previous
! fields at the start of the next hour
pe_tp = pe_t; pe_qp = pe_q; pe_pp = pe_p; pe_wp = pe_w; pe_rnp = pe_rn
end subroutine keep_previous
!
!----------------------------------------------------------------------------------------------------
!
subroutine calc_evspsblpot
! FAO-56 Penman-Monteith, hourly (see the header of this file), for hour issh
!
do ix=1,nlon
  do iy=1,nlat
    if (landmask(ix,iy) > 0.) then
      pe_tc   = 0.5 * (pe_t(ix,iy) + pe_tp(ix,iy)) - 273.15               ! degC
      pe_qm   = 0.5 * (pe_q(ix,iy) + pe_qp(ix,iy))                        ! kg kg-1
      pe_pk   = 0.5 * (pe_p(ix,iy) + pe_pp(ix,iy)) / 1000.                ! kPa
      pe_u2   = 0.748 * 0.5 * (pe_w(ix,iy) + pe_wp(ix,iy))                ! m s-1 at 2 m
      pe_rnmj = real((pe_rn(ix,iy) - pe_rnp(ix,iy)) * 1.d-6)              ! MJ m-2 h-1
      if (pe_rnmj > 0.) then
        pe_g = 0.1 * pe_rnmj
      else
        pe_g = 0.5 * pe_rnmj
      endif
      pe_es = 0.6108 * exp(17.27 * pe_tc / (pe_tc + 237.3))               ! kPa
      pe_ea = pe_qm * pe_pk / (0.622 + 0.378 * pe_qm)                     ! kPa
      pe_dl = 4098. * pe_es / (pe_tc + 237.3)**2                          ! kPa degC-1
      pe_gm = 0.665e-3 * pe_pk                                            ! kPa degC-1
      pe_et = (0.408 * pe_dl * (pe_rnmj - pe_g) &
               + pe_gm * (37. / (pe_tc + 273.)) * pe_u2 * (pe_es - pe_ea)) &
              / (pe_dl + pe_gm * (1. + 0.34 * pe_u2))                     ! mm h-1
      outvar_h(ix,iy,issh) = pe_et / 3600.                                ! kg m-2 s-1
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

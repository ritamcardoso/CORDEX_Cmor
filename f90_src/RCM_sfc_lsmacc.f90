program read_wrfout
!
! RCM_sfc_lsmacc — Noah-MP water fluxes (1hr, hourly means, kg m-2 s-1) from the
! accumulated fields of wrfout (mm = kg m-2), as RCM_sfc_pr:
!
!   evspsblsoi  ACEDIR   water evaporation from soil (ground surface)
!   evspsblveg  ACECAN   evaporation of the water intercepted by the canopy
!   tran        ACETRAN  transpiration
!
! value of hour h = (accumulation at the end - at the start of the hour) / 3600 s,
! written at hh:30 with bounds hh:00-hh+1:00. If the accumulation went back (it was
! reset, e.g. at a restart), the mean of the instantaneous rates (EDIR, ECAN, ETRAN,
! mm s-1) at the start and end of the hour is used for that hour instead.
! Sea points (LANDMASK = 0) are missing ("area: mean where land").
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

real, dimension(:,:), allocatable :: la_acc, la_accp, la_rate, la_ratep
character(len=20) :: la_accv, la_ratev
integer :: la_reset

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

select case (trim(vaid))
  case ('evspsblsoi'); la_accv = 'ACEDIR';  la_ratev = 'EDIR'
  case ('evspsblveg'); la_accv = 'ACECAN';  la_ratev = 'ECAN'
  case ('tran');       la_accv = 'ACETRAN'; la_ratev = 'ETRAN'
  case default
    print *, 'ERROR: RCM_sfc_lsmacc does not know the variable ', trim(vaid)
    stop 95
end select
write(*,*) trim(vaid), ' from ', trim(la_accv), ' (resets: ', trim(la_ratev), ')'

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
allocate(la_acc(nlon,nlat), la_accp(nlon,nlat), la_rate(nlon,nlat), la_ratep(nlon,nlat))
la_reset = 0

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

        call read_field(la_accv, la_acc)
        call read_field(la_ratev, la_rate)

        status = nf90_close(ncid)
        call ncerror(status,'closing file')
!
        if(it == 0)then
          it=it+1
          la_accp = la_acc; la_ratep = la_rate
          cycle loop_h
        endif

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 0.5
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        call calc_flux

        la_accp = la_acc; la_ratep = la_rate

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
if (la_reset > 0) write(*,*) la_reset, ' grid point-hours with a reset accumulation: mean rate used'
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
status=nf90_inq_varid(ncid,trim(vname),varid)
call ncerror(status,'getting var id '//trim(vname))
status=nf90_get_var(ncid,varid,field,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//trim(vname))
!
end subroutine read_field
!
!----------------------------------------------------------------------------------------------------
!
subroutine calc_flux
! hourly mean flux (kg m-2 s-1) of hour issh; sea points missing
!
do ix=1,nlon
  do iy=1,nlat
    if (landmask(ix,iy) > 0.) then
      if (la_acc(ix,iy) >= la_accp(ix,iy) - 1.e-6) then
        outvar_h(ix,iy,issh) = (la_acc(ix,iy) - la_accp(ix,iy)) / 3600.
      else
        outvar_h(ix,iy,issh) = 0.5 * (la_rate(ix,iy) + la_ratep(ix,iy))
        la_reset = la_reset + 1
      endif
    else
      outvar_h(ix,iy,issh) = 1.e+20
    endif
  enddo
enddo
!
end subroutine calc_flux
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

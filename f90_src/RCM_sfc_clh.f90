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
allocate(psf(nlon, nlat))

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
!    
  endif
  ! Loop over months
  do month = imonth, nmonths,1

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

        filename = trim(dir)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening file')

        ! Read Pressure and Target Variable

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading '//'P')

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading '//'PB')

        press = p + pb
!
        status=nf90_inq_varid(ncid,'PSFC',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,psf,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'PSFC')

        ! Read wrf var
        status = nf90_inq_varid(ncid, wrfvar, varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, wrfv3D, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading '//wrfvar)

        status = nf90_close(ncid)
        call ncerror(status,'closing file')
!
! Compute atmosphere water content
!
        call calc_clh
!
        if(it == 0)then
          it=it+1
!
          outvar_i=outvar

          cycle loop_h
        endif

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 0.5
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h(:,:,issh)=(outvar(:,:)+outvar_i(:,:))/2.
!
        outvar_i=outvar

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
!  Write output
!
call write_output

contains
!
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_clt
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
!
! Output:
! outvar       : maximum cloud fraction - Total Cloud Cover
!
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    bf=0.
!
    loop_k: do k=1,nz
      b(k)=wrfv3D(ix,iy,k)
      if(b(1) == 1.)then
        bf(k)=1.
        exit loop_k
      else
        do j=1,k
          if(b(j-1) /= 1)then
            bb(k)=bb(k)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
          else
            bf(k)=1.
            exit loop_k
          endif
        enddo
        bf(k)=1.-bb(k)
      endif
    enddo loop_k
!
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
!
end subroutine calc_clt
!
!------------------------------------------------------------------------------------------------
!
subroutine calc_clh
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
! press     : pressure at model levels P + PB
!
! Output:
! outvar       : maximum cloud fraction - Total Cloud Cover
!
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    i=0
    bf=0.
!
    loop_k: do k=1,nz
      if(press(ix,iy,k) <= 44000.)then
        i=i+1
        b(i)=wrfv3D(ix,iy,k)
        if(b(1) == 1.)then
          bf(i)=1.
          exit loop_k
        else
          do j=1,i
            if(b(j-1) /= 1)then
              bb(i)=bb(i)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
            else
              bf(i)=1.
              exit loop_k
            endif
          enddo
          bf(i)=1.-bb(i)
        endif
      endif
    enddo loop_k
!
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
!
end subroutine calc_clh
!
!-------------------------------------------------------------------------------------------------
!
subroutine calc_clm
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
! press     : pressure at model levels P + PB
!
! Output:
! outvar       : maximum cloud fraction - Total Cloud Cover
!
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    i=0
    bf=0.
!
    loop_k: do k=1,nz
      if( 44000. < press(ix,iy,k) .and. press(ix,iy,k) <= 68000.)then
        i=i+1
        b(i)=wrfv3D(ix,iy,k)
        if(b(1) == 1.)then
          bf(i)=1.
          exit loop_k
        else
          do j=1,i
            if(b(j-1) /= 1)then
              bb(i)=bb(i)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
            else
              bf(i)=1.
              exit loop_k
            endif
          enddo
          bf(i)=1.-bb(i)
        endif
      elseif(press(ix,iy,k) <= 44000)then
        exit loop_k
      endif
    enddo loop_k
!
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
!
end subroutine calc_clm
!
!------------------------------------------------------------------------------------------------
!
subroutine calc_cll
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
! press     : pressure at model levels P + PB
!
! Output:
! outvar       : maximum cloud fraction - Total Cloud Cover
!
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    i=0
    bf=0.
!
    loop_k: do k=1,nz
      if(press(ix,iy,k) > 68000.)then
        i=i+1
        b(i)=wrfv3D(ix,iy,k)
        if(b(1) == 1.)then
          bf(i)=1.
          exit loop_k
        else
          do j=1,i
            if(b(j-1) /= 1)then
              bb(i)=bb(i)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
            else
              bf(i)=1.
              exit loop_k
            endif
          enddo
          bf(i)=1.-bb(i)
        endif
      elseif(press(ix,iy,k) <= 68000.)then
        exit loop_k
      endif
    enddo loop_k
!
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
!
end subroutine calc_cll
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

freq='1hr'
frequency=trim(adjustl(freq))

! Create output filename based on metadata
outfile=trim(vaid)//trim(outdom)//trim(freq)//'_'//ayeari//amonthi//adayi//ahouri//'-'//ayearf//amonthf//adayf//ahourf//'_v2.nc'
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

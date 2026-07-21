
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
allocate(outvar(nlon,nlat))
allocate(outvar_i(nlon,nlat))
allocate(rainc(nlon,nlat))
allocate(rainnc(nlon,nlat))
allocate(rainsh(nlon,nlat))
allocate(i_rainc(nlon,nlat))
allocate(i_rainnc(nlon,nlat))

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

        filename = trim(dir)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening file')

        ! Read wrf var
!
        status=nf90_inq_varid(ncid,wrfvar,varid)
        call ncerror(status,'getting var id')
!
        status=nf90_get_var(ncid,varid,rainc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//wrfvar)
!
        status=nf90_inq_varid(ncid,'I_RAINC',varid)
        call ncerror(status,'getting var id')
!
        status=nf90_get_var(ncid,varid,i_rainc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'I_RAINC')
!
        status=nf90_inq_varid(ncid,'RAINNC',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,rainnc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'RAINNC')
!
        status=nf90_inq_varid(ncid,'I_RAINNC',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,i_rainnc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'I_RAINNC')
!
        status=nf90_inq_varid(ncid,'RAINSH',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,rainsh,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'RAINSH')

        status=nf90_close(ncid)
        call ncerror(status,'closing file')
!
! Compute variable
!
        call calc_pr
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

        outvar_h(:,:,issh)=(outvar(:,:)-outvar_i(:,:))/3600.
!
        outvar_i=outvar

      enddo loop_h    ! end hour
!
      ihour=0
      nhours=24
!
    enddo             ! end day
  enddo               ! end month

  ! Write annual output using shared subroutine
  write(ayearf, '(i4)') year

enddo
!
!  Write output
!
call write_output
!
contains
!
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_pr
!
do ix=1,nlon
  do iy=1,nlat
    outvar(ix,iy)=((rainc(ix,iy)+i_rainc(ix,iy)*1000.)+(rainnc(ix,iy)+i_rainnc(ix,iy)*1000.)+rainsh(ix,iy))
  enddo
enddo
!
end subroutine calc_pr
!
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_prc
!
do ix=1,nlon
  do iy=1,nlat
    outvar(ix,iy)=(rainc(ix,iy)+i_rainc(ix,iy)*1000.)
  enddo
enddo
!
end subroutine calc_prc
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

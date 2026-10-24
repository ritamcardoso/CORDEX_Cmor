program read_wrfout
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
nlon_u=nlon +1
nlat_v=nlat+1

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
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(cosalp(nlon,nlat), sinalp(nlon,nlat))
allocate(ua(nlon_u,nlat,nz), va(nlon,nlat_v,nz))
allocate(wrfv3D(nlon, nlat, nz))

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

        if (it == 0) then
            it = it + 1
!
          status=nf90_inq_varid(ncid,'COSALPHA',varid)
          call ncerror(status,'getting var id COSALPHA in '//trim(infile))

          status=nf90_get_var(ncid,varid,cosalp,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
          call ncerror(status,'reading COSALPHA from '//trim(infile))
!
          status=nf90_inq_varid(ncid,'SINALPHA',varid)
          call ncerror(status,'getting var id SINALPHA in '//trim(infile))

          status=nf90_get_var(ncid,varid,sinalp,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
          call ncerror(status,'reading SINALPHA from '//trim(infile))

        endif

        ! Read Pressure and Target Variable

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status,'getting var id P in '//trim(infile))

        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading P from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status,'getting var id PB in '//trim(infile))

        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading PB from '//trim(infile))

        status=nf90_inq_varid(ncid,'U',varid)
        call ncerror(status,'getting var id U in '//trim(infile))

        status=nf90_get_var(ncid,varid,ua,(/xoffset,yoffset,1/),(/nlon_u,nlat,nz/),(/1,1,1/))
        call ncerror(status,'reading U from '//trim(infile))

        status=nf90_inq_varid(ncid,'V',varid)
        call ncerror(status,'getting var id V in '//trim(infile))

        status=nf90_get_var(ncid,varid,va,(/xoffset,yoffset,1/),(/nlon,nlat_v,nz/),(/1,1,1/))
        call ncerror(status,'reading V from '//trim(infile))
!
        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
        press = p + pb
!
! Compute variable
!
        do ix=1,nlon
          do iy=1,nlat
            wrfv3D(ix,iy,:)=((ua(ix,iy,:)+ua(ix+1,iy,:))/2.)*cosalp(ix,iy)- &
                           ((va(ix,iy,:)+va(ix,iy+1,:))/2.)*sinalp(ix,iy)              !u
!            wrfv3D(ix,iy,:)=((va(ix,iy,:)+va(ix,iy+1,:))/2.)*cosalp(ix,iy)+ &
!                           ((ua(ix,iy,:)+ua(ix+1,iy,:))/2.)*sinalp(ix,iy)              !v
          enddo
        enddo
!
        ! levels bracketing presl at every point (map), then the log(p) interpolation
        call plev_map(press, presl)
        call plev_interp(wrfv3D, outvar)
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

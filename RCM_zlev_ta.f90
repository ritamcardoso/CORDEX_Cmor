
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
allocate(zhgt(nlon, nlat, nz))
allocate(wrfv3D(nlon, nlat, nz))
allocate(hgt(nlon, nlat))

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

        ! Read Terrain Height once
        if (it == 0) then
            it = it + 1

            status = nf90_inq_varid(ncid, 'HGT', varid)
            call ncerror(status,'getting var id'//'HGT')

            status = nf90_get_var(ncid, varid, hgt, (/xoffset, yoffset/), (/nlon, nlat/))
            call ncerror(status,'reading '//'HGT')
        endif

        ! Read Geopotential for Height Calculation

        allocate(ph(nlon, nlat, nzt), phb(nlon, nlat, nzt), phi(nlon, nlat, nzt))

        status = nf90_inq_varid(ncid, 'PH', varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, ph, (/xoffset, yoffset, 1/), (/nlon, nlat, nzt/))
        call ncerror(status,'reading '//'PH')

        status = nf90_inq_varid(ncid, 'PHB', varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, phb, (/xoffset, yoffset, 1/), (/nlon, nlat, nzt/))
        call ncerror(status,'reading '//'PHB')

        phi = (ph + phb) / g

        ! Calculate height above the surface

        do iz = 1, nz
            zhgt(:, :, iz) = ((phi(:, :, iz) + phi(:, :, iz+1)) / 2.) - hgt(:, :)
        enddo
        deallocate(ph, phb, phi)

        ! Read Pressure and Target Variable

        allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading '//'P')

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading '//'PB')

        press = p + pb

        deallocate(p, pb)

        ! Read wrf var
        status = nf90_inq_varid(ncid, wrfvar, varid)
        call ncerror(status,'getting var id')

        status = nf90_get_var(ncid, varid, wrfv3D, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading '//wrfvar)

        status = nf90_close(ncid)
        call ncerror(status,'closing file')

        ! Convert to Potential Temperature

        wrfv3D = (wrfv3D + 300.) * (press / pconst)**rcp

        deallocate(press)

        ! Interpolate to specific height 'heightl'

        call calc_zlev

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h(:, :, issh) = outvar(:, :)

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
!----------------------------------------------------------------------------------------------------
!
subroutine calc_zlev
use datvar_s        
! Interpolates the variable to the target height 'heightl' 
real, parameter :: huge_val = 1.0e20

outvar = huge_val

do isy = 1, nlat
  do isx = 1, nlon
    z_loop: do iz = 1, nz - 1
      if (zhgt(isx, isy, iz) > heightl) exit z_loop

      if (zhgt(isx, isy, iz+1) >= heightl .and. zhgt(isx, isy, iz) < heightl) then

        slope = (wrfv3D(isx, isy, iz+1) - wrfv3D(isx, isy, iz)) / &
                (zhgt(isx, isy, iz+1) - zhgt(isx, isy, iz))
        outvar(isx, isy) = wrfv3D(isx, isy, iz) + (heightl - zhgt(isx, isy, iz)) * slope

        exit z_loop
      endif
    enddo z_loop
  enddo
enddo
!
end subroutine calc_zlev
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

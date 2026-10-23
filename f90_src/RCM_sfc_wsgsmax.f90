program read_wrfout
!
! RCM_sfc_wsgsmax — daily maximum near-surface wind speed of gust (wsgsmax, m s-1),
! from the hourly wrfout files, following the gust of the old RCM_50km_sfc_gust_era.f90
! (the NCEP/UPP formula): the wind of the highest model level inside the boundary
! layer is mixed down to the surface, the more the shallower the boundary layer:
!
!   gust = max( ws10, ws10 + (ws_pbl - ws10) * (1 - min(0.5, PBLH / 2000 m)) )
!
!   ws10   10 m wind speed (U10, V10)
!   ws_pbl wind speed (U, V on the mass levels) of the highest level with a height
!          above ground (PH + PHB, HGT) <= PBLH; the lowest level if PBLH is below it
!
! wsgsmax = maximum of the 24 hourly gusts of each day (cell_methods time: maximum).
! Corrections to the old code: heights are taken above ground (z - HGT), the level
! indices are those of the grid point, and the level is defined when PBLH is below
! the first model level.
!
! All the arrays are those of datvar_s (u_s/v_s: U10/V10, pblh, hgt, u/v staggered and
! ua/va on the mass levels, ph/phb, phi: height of the w levels, zhgt: of the mass levels,
! outvar: hourly gust, outvar_i: running daily maximum).
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

allocate(u_s(nlon,nlat), v_s(nlon,nlat), pblh(nlon,nlat), hgt(nlon,nlat))
allocate(outvar(nlon,nlat), outvar_i(nlon,nlat))
allocate(u(nlon+1,nlat,nz), v(nlon,nlat+1,nz), ua(nlon,nlat,nz), va(nlon,nlat,nz))
allocate(ph(nlon,nlat,nz+1), phb(nlon,nlat,nz+1), phi(nlon,nlat,nz+1), zhgt(nlon,nlat,nz))

amonthi = pad_int(imonth, 2)
adayi = pad_int(iday, 2)
ahouri = pad_int(ihour, 2)

do year = yeari, yearf
  write(ayear, '(i4)') year
  if (mod(year, 4) == 0 .and. year /= 2100) then
    days = days2
  else
    days = days1
  endif

  ! one value per day: the maximum of the hourly gusts of that day
  ntime = sum(days(imonth:nmonths))
  allocate(ttime(ntime), bdtime(2, ntime), outvar_h(nlon, nlat, ntime))
  issh = 0

  do month = imonth, nmonths
    amonth = pad_int(month, 2)
    write(*,*) year, month
    do day = 1, days(month)
      aday = pad_int(day, 2)
      outvar_i = -1.
      do hour = ihour, 23
        ahour = pad_int(hour, 2)
        infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))
        status = nf90_inq_varid(ncid, 'U10', varid)
        call ncerror(status, 'getting var id U10 in '//trim(infile))
        status = nf90_get_var(ncid, varid, u_s, (/xoffset, yoffset/), (/nlon, nlat/))
        call ncerror(status, 'reading U10 from '//trim(infile))
        status = nf90_inq_varid(ncid, 'V10', varid)
        call ncerror(status, 'getting var id V10 in '//trim(infile))
        status = nf90_get_var(ncid, varid, v_s, (/xoffset, yoffset/), (/nlon, nlat/))
        call ncerror(status, 'reading V10 from '//trim(infile))
        status = nf90_inq_varid(ncid, 'PBLH', varid)
        call ncerror(status, 'getting var id PBLH in '//trim(infile))
        status = nf90_get_var(ncid, varid, pblh, (/xoffset, yoffset/), (/nlon, nlat/))
        call ncerror(status, 'reading PBLH from '//trim(infile))
        status = nf90_inq_varid(ncid, 'HGT', varid)
        call ncerror(status, 'getting var id HGT in '//trim(infile))
        status = nf90_get_var(ncid, varid, hgt, (/xoffset, yoffset/), (/nlon, nlat/))
        call ncerror(status, 'reading HGT from '//trim(infile))
        status = nf90_inq_varid(ncid, 'U', varid)
        call ncerror(status, 'getting var id U in '//trim(infile))
        status = nf90_get_var(ncid, varid, u, (/xoffset, yoffset, 1/), (/nlon+1, nlat, nz/))
        call ncerror(status, 'reading U from '//trim(infile))
        status = nf90_inq_varid(ncid, 'V', varid)
        call ncerror(status, 'getting var id V in '//trim(infile))
        status = nf90_get_var(ncid, varid, v, (/xoffset, yoffset, 1/), (/nlon, nlat+1, nz/))
        call ncerror(status, 'reading V from '//trim(infile))
        status = nf90_inq_varid(ncid, 'PH', varid)
        call ncerror(status, 'getting var id PH in '//trim(infile))
        status = nf90_get_var(ncid, varid, ph, (/xoffset, yoffset, 1/), (/nlon, nlat, nz+1/))
        call ncerror(status, 'reading PH from '//trim(infile))
        status = nf90_inq_varid(ncid, 'PHB', varid)
        call ncerror(status, 'getting var id PHB in '//trim(infile))
        status = nf90_get_var(ncid, varid, phb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz+1/))
        call ncerror(status, 'reading PHB from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))

        ! winds and heights on the mass levels
        ua = 0.5 * (u(1:nlon,:,:) + u(2:nlon+1,:,:))
        va = 0.5 * (v(:,1:nlat,:) + v(:,2:nlat+1,:))
        phi = (ph + phb) / g                                   ! geopotential height of the w levels (m)
        zhgt = 0.5 * (phi(:,:,1:nz) + phi(:,:,2:nz+1))         ! ... of the mass levels

        call calc_gust
        outvar_i = max(outvar_i, outvar)
      enddo
      ihour = 0

      issh = issh + 1
      bdtime(1, issh) = hours_since_ini(year, month, day, 0)
      bdtime(2, issh) = bdtime(1, issh) + 24
      ttime(issh) = float(bdtime(1, issh)) + 12.
      outvar_h(:,:,issh) = real(nint(100.d0 * outvar_i, 8)) / 100.
    enddo
  enddo

  write(ayeari, '(i4)') year
  write(ayearf, '(i4)') year
  call write_output
enddo

contains
!
!-----------------------------------------------------------------------
!
subroutine calc_gust
! gust of every grid point for the current hour (outvar)
do iy = 1, nlat
  do ix = 1, nlon
    l = 1
    do k = 1, nz
      if (zhgt(ix,iy,k) - hgt(ix,iy) > pblh(ix,iy)) exit
      l = k
    enddo
    ws10 = sqrt(u_s(ix,iy)**2 + v_s(ix,iy)**2)
    wsp  = sqrt(ua(ix,iy,l)**2 + va(ix,iy,l)**2)
    dws  = (wsp - ws10) * (1. - min(0.5, pblh(ix,iy) / 2000.))
    outvar(ix,iy) = max(ws10, ws10 + dws)
  enddo
enddo
end subroutine calc_gust
!
!-----------------------------------------------------------------------
!
subroutine write_output
! file name and NetCDF writer (daily file of one year)

freq = 'day'
frequency = trim(adjustl(freq))

outfile = trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_label(ttime(1),ttime(ntime)))//'.nc'
fnameout = trim(adjustl(outfile))

if (factor /= 0.) outvar_h = outvar_h * factor

call date_and_time(date,times,zone,values)
write(yyyy,'(i4)') values(1)
mm = pad_int(values(2), 2)
dd = pad_int(values(3), 2)
hh = pad_int(values(5), 2)
mn = pad_int(values(6), 2)
ss = pad_int(values(7), 2)
cdate = yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
creationdate = cdate(1:len_trim(cdate))

call write_netcdf_rtime_3d(outvar_h, ntime, ttime, bdtime)

deallocate(ttime, bdtime, outvar_h)

end subroutine write_output
!
!-----------------------------------------------------------------------
!
end program read_wrfout

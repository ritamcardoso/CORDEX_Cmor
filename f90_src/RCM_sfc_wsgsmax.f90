program read_wrfout
!
! RCM_sfc_wsgsmax — daily maximum near-surface wind speed of gust (wsgsmax, m s-1),
! from the hourly wrfout files. The method depends on the wrfout files:
!
! 1. With QKE (twice the TKE of MYNN) in the wrfout: Brasseur (2001, MWR) as in the
!    CORDEX-WRF module (CDXWRF, Fita et al. 2019, GMD 12, 1029; gustwind_Brasseur01
!    of phys/module_diagvar_cordex.F, adapted from clWRF). An air parcel at height
!    zp in the boundary layer is deflected to the surface if its mean turbulent
!    kinetic energy is larger than the buoyant energy between the surface and zp,
!
!      (1/zp) int_0^zp TKE dz  >=  int_0^zp g (dtheta_v / theta_v) dz
!
!    and the gust is the largest wind speed of the levels that satisfy it, going up
!    from the surface until the first level that does not (0 if none, as in CDXWRF).
!      theta_v = theta (1 + 0.61 qv - qc)   (T + 300, QVAPOR, QCLOUD);  TKE = QKE / 2
!      levels  : heights above ground (PH + PHB on the mass levels, HGT) <= PBLH
!    CDXWRF takes the maximum over every model time step; from hourly output the
!    maximum can only be lower or equal.
!
! 2. Without QKE: the gust of the old RCM_50km_sfc_gust_era.f90 (the NCEP/UPP
!    formula): the wind of the highest model level inside the boundary layer is
!    mixed down to the surface, the more the shallower the boundary layer:
!
!      gust = max( ws10, ws10 + (ws_pbl - ws10) * (1 - min(0.5, PBLH / 2000 m)) )
!
!      ws10   10 m wind speed (U10, V10)
!      ws_pbl wind speed (U, V on the mass levels) of the highest level with a height
!             above ground <= PBLH; the lowest level if PBLH is below it
!
! The method is chosen from the first wrfout file of the job and written to the log.
! wsgsmax = maximum of the 24 hourly gusts of each day (cell_methods time: maximum).
!
! All the arrays are those of datvar_s (u_s/v_s: U10/V10, pblh, hgt, u/v staggered and
! ua/va on the mass levels, ph/phb, phi: height of the w levels, zhgt: of the mass levels,
! outvar: hourly gust, outvar_i: running daily maximum; t, qv, qc, tke 3-D; vpt, zcol, dzcol, dvpt one column;
! gust_b01: .true. for the Brasseur method).
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_io_subs
use netcdf
!implicit none

! --- Read configuration using shared_io_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

! --- Method: Brasseur (2001) if the wrfout files have QKE, else the UPP formula
write(ayear, '(i4)') yeari
amonth = pad_int(imonth, 2)
ahour = pad_int(ihour, 2)
infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-01_'//ahour//'_00_00'
status = nf90_open(infile, nf90_nowrite, ncid)
call ncerror(status,'opening '//trim(infile))
gust_b01 = (nf90_inq_varid(ncid, 'QKE', varid) == nf90_noerr)
status = nf90_close(ncid)
call ncerror(status,'closing '//trim(infile))
if (gust_b01) then
  write(*,*) 'wsgsmax: QKE found in ', trim(infile), ': Brasseur (2001) gust, as CDXWRF'
else
  write(*,*) 'wsgsmax: no QKE in ', trim(infile), ': UPP gust (wind at the top of the boundary layer)'
endif

allocate(u_s(nlon,nlat), v_s(nlon,nlat), pblh(nlon,nlat), hgt(nlon,nlat))
allocate(outvar(nlon,nlat), outvar_i(nlon,nlat))
allocate(u(nlon+1,nlat,nz), v(nlon,nlat+1,nz), ua(nlon,nlat,nz), va(nlon,nlat,nz))
allocate(ph(nlon,nlat,nz+1), phb(nlon,nlat,nz+1), phi(nlon,nlat,nz+1), zhgt(nlon,nlat,nz))
if (gust_b01) then
  allocate(t(nlon,nlat,nz), qv(nlon,nlat,nz), qc(nlon,nlat,nz), tke(nlon,nlat,nz))
  allocate(vpt(nz), zcol(nz), dzcol(nz), dvpt(nz))
endif

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
        if (gust_b01) then
          status = nf90_inq_varid(ncid, 'T', varid)
          call ncerror(status, 'getting var id T in '//trim(infile))
          status = nf90_get_var(ncid, varid, t, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
          call ncerror(status, 'reading T from '//trim(infile))
          status = nf90_inq_varid(ncid, 'QVAPOR', varid)
          call ncerror(status, 'getting var id QVAPOR in '//trim(infile))
          status = nf90_get_var(ncid, varid, qv, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
          call ncerror(status, 'reading QVAPOR from '//trim(infile))
          status = nf90_inq_varid(ncid, 'QCLOUD', varid)
          call ncerror(status, 'getting var id QCLOUD in '//trim(infile))
          status = nf90_get_var(ncid, varid, qc, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
          call ncerror(status, 'reading QCLOUD from '//trim(infile))
          status = nf90_inq_varid(ncid, 'QKE', varid)
          call ncerror(status, 'getting var id QKE in '//trim(infile))
          status = nf90_get_var(ncid, varid, tke, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
          call ncerror(status, 'reading QKE from '//trim(infile))
        endif
        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))

        ! winds and heights on the mass levels
        ua = 0.5 * (u(1:nlon,:,:) + u(2:nlon+1,:,:))
        va = 0.5 * (v(:,1:nlat,:) + v(:,2:nlat+1,:))
        phi = (ph + phb) / g                                   ! geopotential height of the w levels (m)
        zhgt = 0.5 * (phi(:,:,1:nz) + phi(:,:,2:nz+1))         ! ... of the mass levels
        if (gust_b01) then
          t = t + 300.                                         ! potential temperature (K)
          tke = 0.5 * tke                                      ! TKE = QKE / 2
        endif

        if (gust_b01) then
          call calc_gust_b01
        else
          call calc_gust_upp
        endif
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
subroutine calc_gust_b01
! gust of every grid point for the current hour (outvar): gustwind_Brasseur01 of CDXWRF
! (module_diagvar_cordex.F) for each column, wind speed only
do iy = 1, nlat
  do ix = 1, nlon
    outvar(ix,iy) = 0.
    zcol = 0.; dzcol = 0.; vpt = 0.; dvpt = 0.
    ! levels inside the boundary layer (the level above must still be below PBLH, as CDXWRF)
    nlevs = 0
    do k = 1, nz-1
      if (zhgt(ix,iy,k+1) - hgt(ix,iy) > pblh(ix,iy)) exit
      vpt(k) = t(ix,iy,k) * (1. + 0.61 * qv(ix,iy,k) - qc(ix,iy,k))   ! virtual potential temperature
      zcol(k) = zhgt(ix,iy,k) - hgt(ix,iy)
      nlevs = k
    enddo
    if (nlevs <= 1) cycle
    dzcol(1:nlevs-1) = zcol(2:nlevs) - zcol(1:nlevs-1)
    ! buoyancy term g dtheta_v / theta_v (centred, one-sided at the ends)
    dvpt(1) = g * (vpt(2) - vpt(1)) / vpt(1)
    if (nlevs > 2) dvpt(2:nlevs-1) = g * (vpt(3:nlevs) - vpt(1:nlevs-2)) / vpt(2:nlevs-1)
    dvpt(nlevs) = g * (vpt(nlevs) - vpt(nlevs-1)) / vpt(nlevs)
    do ilev = 2, nlevs
      tke_int = sum(tke(ix,iy,1:ilev) * dzcol(1:ilev)) / zcol(ilev)
      vpt_int = sum(dvpt(1:ilev))
      if (tke_int < vpt_int) exit                                     ! end of the deflection
      outvar(ix,iy) = max(outvar(ix,iy), sqrt(ua(ix,iy,ilev)**2 + va(ix,iy,ilev)**2))
    enddo
  enddo
enddo
end subroutine calc_gust_b01
!
!-----------------------------------------------------------------------
!
subroutine calc_gust_upp
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
end subroutine calc_gust_upp
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

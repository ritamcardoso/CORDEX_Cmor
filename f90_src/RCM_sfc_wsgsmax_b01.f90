program read_wrfout
!
! RCM_sfc_wsgsmax_b01 — daily maximum near-surface wind speed of gust (wsgsmax, m s-1),
! from the hourly wrfout files, following Brasseur (2001, MWR) as in the CORDEX-WRF
! module (CDXWRF, Fita et al. 2019, GMD 12, 1029; gustwind_Brasseur01 of
! phys/module_diagvar_cordex.F, adapted from clWRF): an air parcel at height zp in the
! boundary layer is deflected to the surface if its mean turbulent kinetic energy
! is larger than the buoyant energy between the surface and zp,
!
!   (1/zp) int_0^zp TKE dz  >=  int_0^zp g (dtheta_v / theta_v) dz
!
! and the gust is the largest wind speed of the levels that satisfy it, going up
! from the surface until the first level that does not (0 if none, as in CDXWRF).
!   theta_v = theta (1 + 0.61 qv - qc)   (T + 300, QVAPOR, QCLOUD)
!   TKE     = TKE_PBL (needs a TKE boundary-layer scheme: MYJ, MYNN, BouLac, ...)
!   levels  : heights above ground (PH + PHB on the mass levels, HGT) <= PBLH
! wsgsmax = maximum of the 24 hourly gusts of each day (cell_methods time: maximum).
! CDXWRF takes the maximum over every model time step; from hourly output the
! maximum can only be lower or equal.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

real, dimension(:,:), allocatable :: gs_u10, gs_v10, gs_pbl, gs_hgt, gs_gust, gs_dmax
real, dimension(:,:,:), allocatable :: gs_us, gs_vs, gs_um, gs_vm, gs_zw, gs_zm, wrfv3D_z
real, dimension(:,:,:), allocatable :: gs_th, gs_qv, gs_qc, gs_tke
integer :: gs_nd, gs_h0, gs_k

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

allocate(gs_u10(nlon,nlat), gs_v10(nlon,nlat), gs_pbl(nlon,nlat), gs_hgt(nlon,nlat))
allocate(gs_gust(nlon,nlat), gs_dmax(nlon,nlat))
allocate(gs_us(nlon+1,nlat,nz), gs_vs(nlon,nlat+1,nz), gs_um(nlon,nlat,nz), gs_vm(nlon,nlat,nz))
allocate(gs_zw(nlon,nlat,nz+1), gs_zm(nlon,nlat,nz))
allocate(wrfv3D_z(nlon,nlat,nz+1), gs_th(nlon,nlat,nz), gs_qv(nlon,nlat,nz), gs_qc(nlon,nlat,nz), gs_tke(nlon,nlat,nz))

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
      gs_dmax = -1.
      do hour = ihour, 23
        ahour = pad_int(hour, 2)
        infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))
        call read2d('U10', gs_u10)
        call read2d('V10', gs_v10)
        call read2d('PBLH', gs_pbl)
        call read2d('HGT', gs_hgt)
        call read3d('U', gs_us, nlon+1, nlat, nz)
        call read3d('V', gs_vs, nlon, nlat+1, nz)
        call read3d('PH', gs_zw, nlon, nlat, nz+1)
        call read3d('PHB', wrfv3D_z, nlon, nlat, nz+1)
        call read3d('T', gs_th, nlon, nlat, nz)
        call read3d('QVAPOR', gs_qv, nlon, nlat, nz)
        call read3d('QCLOUD', gs_qc, nlon, nlat, nz)
        call read3d('TKE_PBL', gs_tke, nlon, nlat, nz)
        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))

        ! winds and heights on the mass levels
        gs_um = 0.5 * (gs_us(1:nlon,:,:) + gs_us(2:nlon+1,:,:))
        gs_vm = 0.5 * (gs_vs(:,1:nlat,:) + gs_vs(:,2:nlat+1,:))
        gs_zw = (gs_zw + wrfv3D_z) / g                           ! geopotential height of the w levels (m)
        gs_zm = 0.5 * (gs_zw(:,:,1:nz) + gs_zw(:,:,2:nz+1))     ! ... of the mass levels

        call calc_gust
        gs_dmax = max(gs_dmax, gs_gust)
      enddo
      ihour = 0

      issh = issh + 1
      bdtime(1, issh) = hours_since_ini(year, month, day, 0)
      bdtime(2, issh) = bdtime(1, issh) + 24
      ttime(issh) = float(bdtime(1, issh)) + 12.
      outvar_h(:,:,issh) = real(nint(100.d0 * gs_dmax, 8)) / 100.
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
subroutine read2d(vname, field)
! a 2-D field of the open wrfout file (ncid)
character(len=*), intent(in) :: vname
real, dimension(:,:), intent(out) :: field
status = nf90_inq_varid(ncid, vname, varid)
call ncerror(status, 'getting var id '//vname//' in '//trim(infile))
status = nf90_get_var(ncid, varid, field, (/xoffset, yoffset/), (/nlon, nlat/))
call ncerror(status, 'reading '//vname//' from '//trim(infile))
end subroutine read2d
!
!-----------------------------------------------------------------------
!
subroutine read3d(vname, field, n1, n2, n3)
! a 3-D field (n1 x n2 x n3, staggered or not) of the open wrfout file (ncid)
character(len=*), intent(in) :: vname
integer, intent(in) :: n1, n2, n3
real, dimension(n1,n2,n3), intent(out) :: field
status = nf90_inq_varid(ncid, vname, varid)
call ncerror(status, 'getting var id '//vname//' in '//trim(infile))
status = nf90_get_var(ncid, varid, field, (/xoffset, yoffset, 1/), (/n1, n2, n3/))
call ncerror(status, 'reading '//vname//' from '//trim(infile))
end subroutine read3d
!
!-----------------------------------------------------------------------
!
subroutine calc_gust
! gust of every grid point for the current hour (gs_gust), Brasseur (2001)
integer :: ix, iy
do iy = 1, nlat
  do ix = 1, nlon
    gs_gust(ix,iy) = gust_b01(gs_zm(ix,iy,:) - gs_hgt(ix,iy), gs_th(ix,iy,:) + 300., gs_qv(ix,iy,:), &
                              gs_qc(ix,iy,:), gs_tke(ix,iy,:), gs_um(ix,iy,:), gs_vm(ix,iy,:), gs_pbl(ix,iy))
  enddo
enddo
end subroutine calc_gust
!
!-----------------------------------------------------------------------
!
function gust_b01(zagl, pt, qv, qc, tke, u, v, hpbl) result(gust)
! one column: gustwind_Brasseur01 of CDXWRF (module_diagvar_cordex.F), speed only
real, dimension(nz), intent(in) :: zagl, pt, qv, qc, tke, u, v
real, intent(in) :: hpbl
real :: gust, tke_int, vpt_int
real, dimension(nz) :: vpt, heights, dheights, dvpt
integer :: k, ilev, nlevs
gust = 0.
heights = 0.; dheights = 0.; vpt = 0.
! levels inside the boundary layer (the level above must still be below PBLH, as CDXWRF)
nlevs = 0
do k = 1, nz-1
  if (zagl(k+1) > hpbl) exit
  vpt(k) = pt(k) * (1. + 0.61 * qv(k) - qc(k))          ! virtual potential temperature
  heights(k) = zagl(k)
  nlevs = k
enddo
if (nlevs <= 1) return
dheights(1:nlevs-1) = heights(2:nlevs) - heights(1:nlevs-1)
! buoyancy term g dtheta_v / theta_v (centred, one-sided at the ends)
dvpt = 0.
dvpt(1) = g * (vpt(2) - vpt(1)) / vpt(1)
if (nlevs > 2) dvpt(2:nlevs-1) = g * (vpt(3:nlevs) - vpt(1:nlevs-2)) / vpt(2:nlevs-1)
dvpt(nlevs) = g * (vpt(nlevs) - vpt(nlevs-1)) / vpt(nlevs)
do ilev = 2, nlevs
  tke_int = 0.
  vpt_int = 0.
  do k = 1, ilev
    tke_int = tke_int + tke(k) * dheights(k)
    vpt_int = vpt_int + dvpt(k)
  enddo
  tke_int = tke_int / heights(ilev)
  if (tke_int < vpt_int) exit                            ! end of the deflection
  gust = max(gust, sqrt(u(ilev)**2 + v(ilev)**2))
enddo
end function gust_b01
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

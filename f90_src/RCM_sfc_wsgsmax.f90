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
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

real, dimension(:,:), allocatable :: gs_u10, gs_v10, gs_pbl, gs_hgt, gs_gust, gs_dmax
real, dimension(:,:,:), allocatable :: gs_us, gs_vs, gs_um, gs_vm, gs_zw, gs_zm, wrfv3D_z

integer :: gs_nd, gs_h0, gs_k

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

allocate(gs_u10(nlon,nlat), gs_v10(nlon,nlat), gs_pbl(nlon,nlat), gs_hgt(nlon,nlat))
allocate(gs_gust(nlon,nlat), gs_dmax(nlon,nlat))
allocate(gs_us(nlon+1,nlat,nz), gs_vs(nlon,nlat+1,nz), gs_um(nlon,nlat,nz), gs_vm(nlon,nlat,nz))
allocate(gs_zw(nlon,nlat,nz+1), gs_zm(nlon,nlat,nz))
allocate(wrfv3D_z(nlon,nlat,nz+1))

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
! gust of every grid point for the current hour (gs_gust)
real :: ws10, wsp, dws
integer :: ix, iy, k, l
do iy = 1, nlat
  do ix = 1, nlon
    l = 1
    do k = 1, nz
      if (gs_zm(ix,iy,k) - gs_hgt(ix,iy) > gs_pbl(ix,iy)) exit
      l = k
    enddo
    ws10 = sqrt(gs_u10(ix,iy)**2 + gs_v10(ix,iy)**2)
    wsp  = sqrt(gs_um(ix,iy,l)**2 + gs_vm(ix,iy,l)**2)
    dws  = (wsp - ws10) * (1. - min(0.5, gs_pbl(ix,iy) / 2000.))
    gs_gust(ix,iy) = max(ws10, ws10 + dws)
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

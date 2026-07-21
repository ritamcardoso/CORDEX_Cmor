module datvar
use datvar_s          ! Inherits dimensions, paths, and shared metadata
implicit none

! --- 1. Constants and Fixed Data ---
integer, parameter :: nseason = 4
integer, parameter :: tmonths = 12

! Physical Constants
real, parameter :: earthrad = 6372.795
real, parameter :: epsilon  = 0.6220
real, parameter :: Rd       = 287.04
real, parameter :: g        = 9.81
real, parameter :: gamma    = 0.0065
real, parameter :: pconst   = 1.0e5

integer, dimension(tmonths), parameter :: days1 = [31,28,31,30,31,30,31,31,30,31,30,31]
integer, dimension(tmonths), parameter :: days2 = [31,29,31,30,31,30,31,31,30,31,30,31]
integer, dimension(nseason), parameter :: sedays1 = [90,92,92,91]
integer, dimension(nseason), parameter :: sedays2 = [91,92,92,91]

! --- 2. Time and Loop Control ---
integer :: nzt, level
integer :: ish, issh, it, iz, isx, isy, iyl
integer :: loop_year
integer :: year, month, day, mydays, hour, nhours, yhours
integer :: ntime
integer, dimension(tmonths) :: days
integer, dimension(nseason) :: sedays

! --- 3. Scientific Data Arrays ---
integer, dimension(8) :: values
integer, dimension(:,:), allocatable :: bdtime
real, dimension(:)  , allocatable :: ttime

real :: cp, rcp, tc, slope

! 2D WRF In/Out Arrays
real, dimension(:,:), allocatable :: outvar_u, outvar_v

! Grid dimensional bounds for staggered grids
integer :: nlon_u, nlat_v

! 3D WRF In/Out Arrays
real, dimension(:,:,:), allocatable :: outvar_h_u, outvar_h_v
real, dimension(:,:,:), allocatable :: p, pb, press, ua, va, wrfv3D_u, wrfv3D_v

! Date and string formatting
character(len=2) :: ahouri, adayi, amonthi, ahourf, adayf, amonthf
character(len=2) :: ahour, aday, amonth, aday_pad,mm,dd,hh,mn,ss
character(len=4) :: ayear, ayearf, ayeari, yyyy
character(len=5)  :: zone
character(len=8)  :: date
character(len=10) :: times
character(len=400) :: fnameout_u, fnameout_v

character(len=3), dimension(nseason) :: snames = ['Win','Spr','Sum','Aut']
character(len=3), dimension(tmonths) :: aname  = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

end module datvar


program read_wrfout
use datvar_s
use datvar
use shared_subs
use netcdf
implicit none

real :: u_unstag, v_unstag
integer :: ix, iy

! Initialize constants and derived values
cp = (7.0/2.0) * Rd
rcp = Rd / cp
tc = 273.16 + 17.5

! Read configuration using shared_subs subroutine
call readdata

! Read Grid Information (Latitude, Longitude)
call read_geog

! Initialising grid and time counters
nzt = nz + 1
nhours = 24
nlon_u = nlon + 1
nlat_v = nlat + 1

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
allocate(outvar_u(nlon, nlat), outvar_v(nlon, nlat))
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(cosalp(nlon, nlat), sinalp(nlon, nlat))
allocate(ua(nlon_u, nlat, nz), va(nlon, nlat_v, nz))
allocate(wrfv3D_u(nlon, nlat, nz), wrfv3D_v(nlon, nlat, nz))

it = 0

do year = yeari, yearf, 1

  write(ayear, '(i4)') year
  issh = 0

  if (mod(year, 4) == 0 .and. year /= 2100) then
    days = days2
    mydays = 366
  else
    days = days1
    mydays = 365
  endif
  ntime = mydays * 4

  if (ihour > 0) then
    nhours = nhours - ihour + 1
    ntime = ntime - ihour + 1
  endif

  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h_u(nlon, nlat, ntime))
  allocate(outvar_h_v(nlon, nlat, ntime))

  ! Loop over months
  do month = imonth, nmonths, 1
    ndays = days(month)
    amonth = pad_int(month, 2)
    write(*,*) 'Processing Year: ', year, ' Month: ', month

    ! Loop over days
    do day = 1, ndays
      aday_pad = pad_int(day, 2)

      ! Loop over hours
      loop_h: do hour = ihour, nhours-1, 6
        ahour = pad_int(hour, 2)

        filename = trim(dir)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday_pad//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        if (status /= nf90_noerr) then
            write(*,*) 'Warning: File skipped or missing: ', trim(infile)
            cycle loop_h
        end if

        if (it == 0) then
          it = it + 1
          status = nf90_inq_varid(ncid, 'COSALPHA', varid)
          call ncerror(status, 'getting var id COSALPHA')
          status = nf90_get_var(ncid, varid, cosalp, (/xoffset, yoffset/), (/nlon, nlat/))
          call ncerror(status, 'reading COSALPHA')

          status = nf90_inq_varid(ncid, 'SINALPHA', varid)
          call ncerror(status, 'getting var id SINALPHA')
          status = nf90_get_var(ncid, varid, sinalp, (/xoffset, yoffset/), (/nlon, nlat/))
          call ncerror(status, 'reading SINALPHA')
        endif

        ! Read Pressures
        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status, 'getting var id P')
        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status, 'reading P')

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status, 'getting var id PB')
        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status, 'reading PB')

        ! Explicitly query and fetch staggered metrics simultaneously
        status = nf90_inq_varid(ncid, 'U', varid)
        call ncerror(status, 'getting var id U')
        status = nf90_get_var(ncid, varid, ua, (/xoffset, yoffset, 1/), (/nlon_u, nlat, nz/))
        call ncerror(status, 'reading U')

        status = nf90_inq_varid(ncid, 'V', varid)
        call ncerror(status, 'getting var id V')
        status = nf90_get_var(ncid, varid, va, (/xoffset, yoffset, 1/), (/nlon, nlat_v, nz/))
        call ncerror(status, 'reading V')

        status = nf90_close(ncid)
        call ncerror(status, 'closing file')

        press = p + pb

        ! Single pass un-staggering and geographic coordinate frame rotation
        do iz = 1, nz
          do iy = 1, nlat
            do ix = 1, nlon
              u_unstag = (ua(ix, iy, iz) + ua(ix+1, iy, iz)) / 2.0
              v_unstag = (va(ix, iy, iz) + va(ix, iy+1, iz)) / 2.0

              ! Earth-relative Eastward Wind component (U)
              wrfv3D_u(ix, iy, iz) = u_unstag * cosalp(ix, iy) - v_unstag * sinalp(ix, iy)
              
              ! Earth-relative Northward Wind component (V)
              wrfv3D_v(ix, iy, iz) = v_unstag * cosalp(ix, iy) + u_unstag * sinalp(ix, iy)
            enddo
          enddo
        enddo

        ! Perform optimized interpolation (Single-pass vertical search loop)
        if (presl >= 50000.0) then
          call calc_plev_dual(wrfv3D_u, wrfv3D_v, outvar_u, outvar_v)
        else
          call calc_invplev_dual(wrfv3D_u, wrfv3D_v, outvar_u, outvar_v)
        endif

        ish = ish + 6
        issh = issh + 1
        ttime(issh) = float(ish) - 6
        bdtime(1, issh) = ish - 6
        bdtime(2, issh) = ish

        outvar_h_u(:, :, issh) = outvar_u(:, :)
        outvar_h_v(:, :, issh) = outvar_v(:, :)

      enddo loop_h
      ihour = 0
      nhours = 24
    enddo
  enddo

  write(ayearf, '(i4)') year
  write(ayeari, '(i4)') year

  call write_dual_output

enddo

contains

subroutine calc_plev_dual(f3d_u, f3d_v, f2d_u, f2d_v)
  real, dimension(nlon, nlat, nz), intent(in)  :: f3d_u, f3d_v
  real, dimension(nlon, nlat),     intent(out) :: f2d_u, f2d_v
  real :: weight_factor
  
  f2d_u = 1.e+20
  f2d_v = 1.e+20
!  pressure(1) = presl
  
  do iy = 1, nlat
    do ix = 1, nlon
      p_loop: do iz = 1, nz - 1
        if (press(ix, iy, iz) < presl) then
          exit p_loop
        endif
        if (press(ix, iy, iz) >= presl .and. press(ix, iy, iz+1) < presl) then
          ! Extract common weighting log factor once
          weight_factor = (log(press(ix, iy, iz)) - log(presl)) / &
                          (log(press(ix, iy, iz)) - log(press(ix, iy, iz+1)))
          
          ! Interpolate both fields simultaneously
          f2d_u(ix, iy) = f3d_u(ix, iy, iz) + weight_factor * (f3d_u(ix, iy, iz+1) - f3d_u(ix, iy, iz))
          f2d_v(ix, iy) = f3d_v(ix, iy, iz) + weight_factor * (f3d_v(ix, iy, iz+1) - f3d_v(ix, iy, iz))
          exit p_loop
        endif
      enddo p_loop
    enddo
  enddo
end subroutine calc_plev_dual

subroutine calc_invplev_dual(f3d_u, f3d_v, f2d_u, f2d_v)
  real, dimension(nlon, nlat, nz), intent(in)  :: f3d_u, f3d_v
  real, dimension(nlon, nlat),     intent(out) :: f2d_u, f2d_v
  real :: weight_factor
  
  f2d_u = 1.e+20
  f2d_v = 1.e+20
!  pressure(1) = presl
  
  do iy = 1, nlat
    do ix = 1, nlon
      p_loop: do iz = nz - 1, 2, -1
        if (press(ix, iy, iz-1) >= presl .and. press(ix, iy, iz) < presl) then
          ! Extract common weighting log factor once
          weight_factor = (log(press(ix, iy, iz-1)) - log(presl)) / &
                          (log(press(ix, iy, iz-1)) - log(press(ix, iy, iz)))
          
          ! Interpolate both fields simultaneously
          f2d_u(ix, iy) = f3d_u(ix, iy, iz-1) + weight_factor * (f3d_u(ix, iy, iz) - f3d_u(ix, iy, iz-1))
          f2d_v(ix, iy) = f3d_v(ix, iy, iz-1) + weight_factor * (f3d_v(ix, iy, iz) - f3d_v(ix, iy, iz-1))
          exit p_loop
        elseif (press(ix, iy, iz) > presl) then
          exit p_loop
        endif
      enddo p_loop
    enddo
  enddo
end subroutine calc_invplev_dual

subroutine write_dual_output
  use datvar_s
  use datvar
  use shared_subs
  use netcdf

  character(len=10) :: p_str
  integer :: p_val

  amonthf = pad_int(month-1, 2)
  adayf = pad_int(day-1, 2)
  ahourf = pad_int(hour-1, 2)

  freq = '6hr'
  frequency = trim(adjustl(freq))

  p_val = int(presl / 100.0)
  p_str = adjustl(pad_int(p_val, 1))

  ! Build unique system output targets natively using context pressure levels
  fnameout_u = trim(dir2)//'ua'//trim(p_str)//trim(outdom)//trim(freq)//'_'//ayeari//amonthi//adayi//ahouri//'-'//ayearf//amonthf//adayf//ahourf//'.nc'
  fnameout_v = trim(dir2)//'va'//trim(p_str)//trim(outdom)//trim(freq)//'_'//ayeari//amonthi//adayi//ahouri//'-'//ayearf//amonthf//adayf//ahourf//'.nc'

  if (factor /= 0.0) then
    outvar_h_u = outvar_h_u * factor
    outvar_h_v = outvar_h_v * factor
  endif

  call date_and_time(date, times, zone, values)
  write(yyyy, '(i4)') values(1)
  mm = pad_int(values(2), 2)
  dd = pad_int(values(3), 2)
  hh = pad_int(values(5), 2)
  mn = pad_int(values(6), 2)
  ss = pad_int(values(7), 2)

  cdate = yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
  creationdate = cdate(1:len_trim(cdate))

  ! Write File 1: Eastward Wind component
  fnameout = trim(adjustl(fnameout_u))
  varname = 'ua'//trim(p_str)
  standardname = 'eastward_wind'
  longname = 'Eastward Wind at ' // trim(p_str) // 'hPa'
  vunits = 'm s-1'
  call write_netcdf_rtime_p(outvar_h_u, ntime, ttime, bdtime)

  ! Write File 2: Northward Wind component
  fnameout = trim(adjustl(fnameout_v))
  varname = 'va'//trim(p_str)
  standardname = 'northward_wind'
  longname = 'Northward Wind at ' // trim(p_str) // 'hPa'
  vunits = 'm s-1'
  call write_netcdf_rtime_p(outvar_h_v, ntime, ttime, bdtime)

  deallocate(ttime)
  deallocate(bdtime)
  deallocate(outvar_h_u)
  deallocate(outvar_h_v)

end subroutine write_dual_output

end program read_wrfout

module datvar
!use datvar_s          ! Inherits dimensions, paths, and shared metadata
!implicit none
!
! Variables unique to datvar.f90 not found in datvar_s.f90
!
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
integer :: year, month, day, mydays, hour, dhour, nhours, yhours
integer :: ntime
integer, dimension(tmonths) :: days
integer, dimension(nseason) :: sedays

! Physical Constants and calculation arrays
!
! --- 3. Scientific Data Arrays ---
! Integer Arrays
integer, dimension(8) :: values
integer, dimension(:,:), allocatable :: bdtime, outvar_a

! Real Arrays
real, dimension(:)  , allocatable :: ttime

! Real Scalars (Unique to datvar)
real :: cp, rcp, tc, slope

! 2D WRF In/Out Arrays
real, dimension(:,:), allocatable :: sftlf,hgt
real, dimension(:,:), allocatable :: wrfv2D, i_wrfv2D, outvar_i
real, dimension(:,:), allocatable :: rainc, rainnc, i_rainc, i_rainnc, rainsh

! 3D WRF In/Out Arrays
real, dimension(:,:,:), allocatable :: wrfv3D, outvar
real, dimension(:,:,:), allocatable :: p, pb, press, phb, ph, phi, zhgt, ua, va, u, v
real, dimension(:,:,:,:), allocatable :: outvar_h

! Date and string formatting
character(len=2) :: ahouri, adayi, amonthi, ahourf, adayf, amonthf
character(len=2) :: ahour, aday, amonth, aiday, mm, dd, hh, mn, ss
character(len=4) :: ayear,ayearf,ayeari,yyyy

! System/Date stamps
character(len=5)  :: zone
character(len=8)  :: date
character(len=10) :: times
!
character(len=3), dimension(nseason) :: snames = ['Win','Spr','Sum','Aut']
character(len=3), dimension(tmonths) :: aname  = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
!
end module datvar
!
program read_wrfout
! Use external modules for variables and shared subroutines
use datvar_s
use datvar
use shared_subs
use netcdf
!implicit none

! Initialize constants and derived values
cp=(7/2)*Rd
rcp = Rd / cp
tc=273.16+17.5

! --- Read configuration using shared_subs subroutine

call readdata

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

! --- Initialising grid and time counters
nz = 10
nzt = nz + 1
nhours = 24
!
!  Compute depth bounds
!
sdepth_bounds(1,1)=0.0
do is=1,nsoil-1
 sdepth_bounds(1,is+1)=sdepth_bounds(1,is)+sdepth(is)
enddo

sdepth_bounds(2,1)=0.1
do is=2,nsoil
 sdepth_bounds(2,is)=sdepth_bounds(2,is-1)+sdepth(is)
enddo

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
allocate(outvar(nlon, nlat, nsoil))
allocate(wrfv3D(nlon, nlat, nsoil))

it = 0
do year = yeari, yearf,1

  write(ayear, '(i4)') year

  ! Compute time length and allocate time sensitive variables
  if (mod(year, 4) == 0 .and. year /= 2100) then
      days = days2
      mydays = 366
  else
      days = days1
      mydays = 365
  endif
!  ntime = mydays * nhours

!  if (ihour > 0) then
!    nhours=nhours-ihour+1
!    ntime = ntime - ihour + 1
!  endif

  ! Loop over months
  do month = imonth, nmonths
!
    issh=0
    ndays=days(month)
    ntime=ndays*4

    allocate(ttime(ntime))
    allocate(bdtime(2, ntime))
    allocate(outvar_h(nlon, nlat, nsoil, ntime))

    ndays = days(month)
    amonth = pad_int(month, 2)

    ! Loop over days
    do day = 1, ndays
      aday = pad_int(day, 2)

      ! Loop over hours
      loop_h: do hour = ihour, nhours-1,6

        ahour = pad_int(hour, 2)

        filename = trim(dir)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening file')

        ! Read wrf var
        status = nf90_inq_varid(ncid, wrfvar, varid)
        call ncerror(status,'getting var id')
        
        status=nf90_get_var(ncid,varid,wrfv3D,(/xoffset,yoffset,1/),(/nlon,nlat,nsoil/),(/1,1,1/))
        call ncerror(status,'reading '//wrfvar)

        status = nf90_close(ncid)
        call ncerror(status,'closing file')
!
! Compute variable
!
        call calc_mrsol

        ish = ish + 6
        issh = issh + 1
        ttime(issh) = float(ish) - 6
        bdtime(1, issh) = ish - 6
        bdtime(2, issh) = ish

        outvar_h(:,:,:,issh)=outvar(:,:,:)

      enddo loop_h    ! end hour
!
      ihour=0
      nhours=24
!
    enddo             ! end day

  ! Write monthly output using shared subroutine
    write(ayearf, '(i4)') year
    write(ayeari, '(i4)') year

    call write_output
  enddo               ! end month

enddo

contains
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_mrsol
use datvar_s
use datvar
!
do ix=1,nlon
  do iy=1,nlat
    if(landmask(ix,iy)>0.)then
      do is=1,nsoil
        outvar(ix,iy,is)=(sdepth(is)*wrfv3D(ix,iy,is))*1000.
      enddo
    else
      outvar(ix,iy,:)=1.e+20
    endif
  enddo
enddo
!
end subroutine calc_mrsol
!
!----------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use datvar
use shared_subs
use netcdf

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)
ahourf = pad_int(hour-1, 2)

freq='6hr'
frequency=trim(adjustl(freq))

! Create output filename based on metadata
outfile=trim(dir2)//trim(vaid)//trim(outdom)//trim(freq)//'_'//ayeari//amonth//'0100-'//ayearf//amonth//adayf//ahourf//'.nc'
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
call write_netcdf_rtime_soil(outvar_h, ntime, ttime, bdtime)

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h)

end subroutine write_output


end program read_wrfout

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
real, dimension(:,:), allocatable :: wrfv2D, i_wrfv2D, outvar, outvar_i
real, dimension(:,:), allocatable :: rainc, rainnc, i_rainc, i_rainnc, rainsh
real, dimension(:,:), allocatable :: psf,t2,mr,mr_sat,e_sfc,esat

! 3D WRF In/Out Arrays
real, dimension(:,:,:), allocatable :: outvar_h, wrfv3D
real, dimension(:,:,:), allocatable :: t, p, pb, press, phb, ph, phi, zhgt, ua, va, u, v

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
allocate(outvar_a(nlon,nlat))
allocate(t2(nlon,nlat))
allocate(mr(nlon,nlat))
allocate(psf(nlon,nlat))
allocate(mr_sat(nlon,nlat))
allocate(e_sfc(nlon,nlat))
allocate(esat(nlon,nlat))

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

        ! Read wrf var
        status=nf90_inq_varid(ncid,'T2',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,t2,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'T2')
!
        status=nf90_inq_varid(ncid,'PSFC',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,psf,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'PSFC')
!
        status=nf90_inq_varid(ncid,wrfvar,varid)
        call ncerror(status,'getting var id')
!
        status=nf90_get_var(ncid,varid,mr,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//wrfvar)
!
        status=nf90_close(ncid)
        call ncerror(status,'closing file')
!
! Compute variable
!
        call calc_rh

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h(:,:,issh)=outvar(:,:)

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
!-----------------------------------------------------------------------------------------------------------------------------------
!
subroutine calc_rh
!
! Calculates relative humidity.
! Following WMO, supercooled water is assumed for temperatures below 0ºC and esat is always calculated in reference to water.
! Enhancement factor is used calculate the effective esat in the presence of other gases
!
! REFERENCES
! Wexler, A., Vapor Pressure Formulation for Water in Range 0 to 100°C. A Revision, Journal of Research of the National Bureau of Standards <96> A. Physics and Chemistry, September <96> December 1976, Vol. 80A, Nos.5 and 6, 775-785
!
! Wexler, A., Vapor Pressure Formulation for Ice, Journal of Research of the National Bureau of Standards <96> A. Physics and Chemistry, January <96> February 1977, Vol. 81A, No. 1, 5-19
!
! Goff, J. A., Standardization of Thermodynamic Properties of Moist Air, Heating, Piping, and Air Conditioning, 1949, Vol. 21, 118.
!
use datvar
real(kind=8) :: fact
real, dimension(nlon,nlat) :: TK
real(kind=8), parameter :: a1=-2.8365744e3,a2=-6.028076559e3,a3=19.54263612,a4=-2.737830188e-2
real(kind=8), parameter :: a5=1.6261698e-5,a6=7.0229056e-10,a7=-1.8680009e-13,a8=2.7150305
real(kind=8), parameter :: b1=-5.8666426e3,b2=22.32870244,b3=1.39387003e-2,b4=-3.4262402e-5
real(kind=8), parameter :: b5=2.7040955e-8,b6=6.7063522e-1
real(kind=8), parameter :: fi1=3.62183e-4,fi2=2.6061244e-5,fi3=3.8667770e-7,fi4=3.8268958e-9,fi5=-10.7604,fi6=6.3987441e-2, &
                           fi7=-2.6351566e-4,fi8=1.6725084e-6
real(kind=8), parameter :: fw1=3.536240e-4,fw2=2.932836e-5,fw3=2.616898e-7,fw4=8.581361e-9,fw5=-10.75880,fw6=6.326813e-2, &
                           fw7=-2.536893e-4,fw8=6.340529e-7
!
TK=t2-273.15
!
do i=1,nlon
  do j=1,nlat
    e_sfc(i,j)=(mr(i,j)/(epsilon+mr(i,j)))*psf(i,j)
!    esat(i,j)=611.2*exp((17.67*TK(i,j))/(TK(i,j)+234.5))                   ! Bolton 1980    0.3% within -35C to 35C
!    esat(i,j)=exp(53.67957-(6743.769/t2(i,j))-4.8451*log(t2(i,j)))*100.    ! 0.7% @ -40C to 0.006% @ 40C
!    esat(i,j)=611.73*exp((2.501e6/461.51)*(1/273.16-1/t2(i,j)))
!    esat(i,j) = exp((-0.58002206e4 / t2(i,j)) + 1.3914993 - 0.48640239e-1 * t2(i,j) + 0.41764768e-4 * t2(i,j)**2 - &
!                       0.14452093e-7 * t2(i,j)**3 + 0.65459673 * log(t2(i,j)))
!
    esat(i,j)=exp(a1*t2(i,j)**-2+a2/t2(i,j)+a3+a4*t2(i,j)+a5*t2(i,j)**2+a6*t2(i,j)**3+a7*t2(i,j)**4+a8*log(t2(i,j))) ! ITS-90 @ -100C to 100C. From 0C to 100C is comparable to Wexler's eq15
!
    if(t2(i,j) <0.)then
      fact=exp((fi1+fi2*TK(i,j)+fi3*TK(i,j)**2+fi4*TK(i,j)**3)*(1.-(esat(i,j)/psf(i,j)))+ &
                    exp(fi5+fi6*TK(i,j)+fi7*TK(i,j)**2+fi8*TK(i,j)**3)*((esat(i,j)/psf(i,j))-1.d0))
    else
      fact=exp((fw1+fw2*TK(i,j)+fw3*TK(i,j)**2+fw4*TK(i,j)**3)*(1.-(esat(i,j)/psf(i,j)))+ &
                    exp(fw5+fw6*TK(i,j)+fw7*TK(i,j)**2+fw8*TK(i,j)**3)*((esat(i,j)/psf(i,j))-1.d0))
    endif
!
    mr_sat(i,j)=epsilon*(esat(i,j)*fact)/(psf(i,j)-(esat(i,j)*fact))
!
    outvar(i,j)=max(min(mr(i,j)/mr_sat(i,j),1.),0.0)*100.
  enddo
enddo
!
end subroutine calc_rh        
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
call write_netcdf_rtime(outvar_h, ntime, ttime, bdtime)

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h)

end subroutine write_output


end program read_wrfout

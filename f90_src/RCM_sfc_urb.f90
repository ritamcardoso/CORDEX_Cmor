program read_wrfout
!
! RCM_sfc_urb — urban variables of FPS-URB-RCC (1hr, instantaneous: time: point),
! from the urban scheme output of WRF (BEP+BEM, sf_urban_physics = 3).
! The variable (vaid in its header) selects the WRF field and the cells kept:
!
!   tasroof    T2R_URB2D      2 m temperature over roofs            urban cells
!   taspav     T2G_URB2D      2 m temperature over roads/pavements  urban cells
!   tasgree    T2VEG_URB2D    2 m temperature over vegetation       urban cells
!   tascan     TCAN_URB2D     canyon air temperature                urban cells
!   sfcWindcan UCAN_URB2D     canyon wind speed                     urban cells
!   husscan    QCAN_URB2D     canyon specific humidity: q = r/(1+r) urban cells
!   hurscan    TCAN_URB2D, QCAN_URB2D, PSFC  canyon relative humidity (as hurs) urban cells
!   tsroof     TROOF_URB2D    roof surface temperature              urban cells
!   tspav      TGROUND_URB2D  road surface temperature              urban cells
!   tsgree     TSK_RURAL      skin temperature of the natural part  urban cells
!   tsskin     TSK            skin temperature                      every cell
!   tsblue     TSK            skin temperature                      water cells
!   tasblue    T2             2 m temperature                       water cells
!
! Urban cells: FRC_URB2D > 0 in the geo_em file; water cells: LANDMASK = 0.
! Other cells are missing (1.e20). Temperatures are rounded to 0.01 K, as tas.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

real, dimension(:,:), allocatable :: ub_frc, ub_f1, ub_f2, ub_f3
logical, dimension(:,:), allocatable :: ub_keep
character(len=20) :: ub_v1, ub_v2, ub_v3, ub_where
logical :: ub_temp

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

! --- The variable: WRF fields, cells kept, rounding
ub_v2 = ''; ub_v3 = ''; ub_where = 'urban'; ub_temp = .true.
select case (trim(vaid))
  case ('tasroof');    ub_v1 = 'T2R_URB2D'
  case ('taspav');     ub_v1 = 'T2G_URB2D'
  case ('tasgree');    ub_v1 = 'T2VEG_URB2D'
  case ('tascan');     ub_v1 = 'TCAN_URB2D'
  case ('sfcWindcan'); ub_v1 = 'UCAN_URB2D';    ub_temp = .false.
  case ('husscan');    ub_v1 = 'QCAN_URB2D';    ub_temp = .false.
  case ('hurscan');    ub_v1 = 'TCAN_URB2D';    ub_v2 = 'QCAN_URB2D'; ub_v3 = 'PSFC'; ub_temp = .false.
  case ('tsroof');     ub_v1 = 'TROOF_URB2D'
  case ('tspav');      ub_v1 = 'TGROUND_URB2D'
  case ('tsgree');     ub_v1 = 'TSK_RURAL'
  case ('tsskin');     ub_v1 = 'TSK';           ub_where = 'all'
  case ('tsblue');     ub_v1 = 'TSK';           ub_where = 'water'
  case ('tasblue');    ub_v1 = 'T2';            ub_where = 'water'
  case default
    print *, 'ERROR: RCM_sfc_urb does not know the variable ', trim(vaid)
    stop 95
end select
write(*,*) trim(vaid), ' from ', trim(ub_v1), ' ', trim(ub_v2), ' ', trim(ub_v3), ', cells: ', trim(ub_where)

! cells kept: urban (FRC_URB2D > 0, from the geo_em file), water (LANDMASK = 0) or all
allocate(ub_keep(nlon,nlat), ub_frc(nlon,nlat))
select case (trim(ub_where))
  case ('urban')
    gfile = trim(dir_in)//trim(geog)//'.nc'
    geofile = gfile(1:len_trim(gfile))
    status = nf90_open(geofile, nf90_nowrite, ncid)
    call ncerror(status, 'opening ' // trim(geofile))
    status = nf90_inq_varid(ncid, 'FRC_URB2D', varid)
    call ncerror(status, 'getting var id FRC_URB2D (urban fraction) in '//trim(geofile))
    status = nf90_get_var(ncid, varid, ub_frc, (/xoffset,yoffset/), (/nlon,nlat/), (/1,1/))
    call ncerror(status, 'reading FRC_URB2D')
    status = nf90_close(ncid)
    call ncerror(status, 'closing file')
    ub_keep = ub_frc > 0.
  case ('water')
    ub_keep = landmask < 0.5
  case default
    ub_keep = .true.
end select
write(*,*) count(ub_keep), ' of ', nlon*nlat, ' cells kept'

! --- Initialising grid and time counters
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
allocate(ub_f1(nlon,nlat), ub_f2(nlon,nlat), ub_f3(nlon,nlat))
if (trim(vaid) == 'hurscan') then
  allocate(t2(nlon,nlat), mr(nlon,nlat), psf(nlon,nlat))
  allocate(mr_sat(nlon,nlat), e_sfc(nlon,nlat), esat(nlon,nlat))
endif

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

        filename = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening file')

        call read_field(ub_v1, ub_f1)
        if (len_trim(ub_v2) > 0) call read_field(ub_v2, ub_f2)
        if (len_trim(ub_v3) > 0) call read_field(ub_v3, ub_f3)

        status = nf90_close(ncid)
        call ncerror(status,'closing file')

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        call calc_urb

        outvar_h(:,:,issh) = outvar(:,:)

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
subroutine read_field(vname, field)
! one 2-D field of the open wrfout file (ncid), cut to the output grid
character(len=*), intent(in) :: vname
real, dimension(:,:), intent(out) :: field
!
status=nf90_inq_varid(ncid,trim(vname),varid)
call ncerror(status,'getting var id '//trim(vname))
status=nf90_get_var(ncid,varid,field,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//trim(vname))
!
end subroutine read_field
!
!----------------------------------------------------------------------------------------------------
!
subroutine calc_urb
! the variable from the fields read, missing outside the cells kept
!
select case (trim(vaid))
  case ('husscan')
    outvar = ub_f1 / (1. + ub_f1)                      ! mixing ratio -> specific humidity
  case ('hurscan')
    t2 = ub_f1; mr = ub_f2; psf = ub_f3
    call calc_rh
  case default
    outvar = ub_f1
end select
where (.not. ub_keep) outvar = 1.e+20
! temperatures to 0.01 K, as tas (only the cells kept: no overflow on fill values)
if (ub_temp) then
  where (ub_keep) outvar = float(nint(100.d0 * outvar)) / 100.
endif
!
end subroutine calc_urb
!
!----------------------------------------------------------------------------------------------------
!
subroutine calc_rh
!
! Relative humidity, as in RCM_sfc_hurs (canyon temperature, humidity and surface pressure).
! Following WMO, supercooled water is assumed for temperatures below 0ºC and esat is always calculated in reference to water.
! Enhancement factor is used calculate the effective esat in the presence of other gases
!
! REFERENCES
! Wexler, A., Vapor Pressure Formulation for Water in Range 0 to 100°C. A Revision, Journal of Research of the National Bureau of Standards - A. Physics and Chemistry, September - December 1976, Vol. 80A, Nos.5 and 6, 775-785
!
! Wexler, A., Vapor Pressure Formulation for Ice, Journal of Research of the National Bureau of Standards - A. Physics and Chemistry, January - February 1977, Vol. 81A, No. 1, 5-19
!
! Goff, J. A., Standardization of Thermodynamic Properties of Moist Air, Heating, Piping, and Air Conditioning, 1949, Vol. 21, 118.
!
real(kind=8) :: fact
real, dimension(nlon,nlat) :: TK
real(kind=8), parameter :: a1=-2.8365744e3,a2=-6.028076559e3,a3=19.54263612,a4=-2.737830188e-2
real(kind=8), parameter :: a5=1.6261698e-5,a6=7.0229056e-10,a7=-1.8680009e-13,a8=2.7150305
real(kind=8), parameter :: fi1=3.62183e-4,fi2=2.6061244e-5,fi3=3.8667770e-7,fi4=3.8268958e-9,fi5=-10.7604,fi6=6.3987441e-2, &
                           fi7=-2.6351566e-4,fi8=1.6725084e-6
real(kind=8), parameter :: fw1=3.536240e-4,fw2=2.932836e-5,fw3=2.616898e-7,fw4=8.581361e-9,fw5=-10.75880,fw6=6.326813e-2, &
                           fw7=-2.536893e-4,fw8=6.340529e-7
!
TK=t2-273.15
!
do i=1,nlon
  do j=1,nlat
    if (.not. ub_keep(i,j)) then
      outvar(i,j)=1.e+20
      cycle
    endif
    e_sfc(i,j)=(mr(i,j)/(epsilon+mr(i,j)))*psf(i,j)
    esat(i,j)=exp(a1*t2(i,j)**-2+a2/t2(i,j)+a3+a4*t2(i,j)+a5*t2(i,j)**2+a6*t2(i,j)**3+a7*t2(i,j)**4+a8*log(t2(i,j))) ! ITS-90 @ -100C to 100C
!
    if(TK(i,j) < 0.)then              ! below 0 degC: enhancement factor over ice
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
use shared_subs
use netcdf

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)
ahourf = pad_int(hour-1, 2)

freq='1hr'
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

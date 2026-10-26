program read_wrfout
!
! RCM_sfc_hurscan — near-surface relative humidity within the canyon (hurscan, 1hr,
! instantaneous, %), as hurs, from the canyon temperature TCAN_URB2D, the canyon
! mixing ratio QCAN_URB2D and the surface pressure PSFC of the urban scheme output.
! Kept only at urban cells (urban_cell in landuse_subs.f90: FRC_URB2D > 0 and
! LU_INDEX an urban category of the MODIS or USGS table of the geo_em file, LCZ
! classes included); missing elsewhere.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_io_subs
use landuse_subs
use netcdf
!implicit none

logical, dimension(:,:), allocatable :: ub_keep

! --- Read configuration using shared_io_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

allocate(ub_keep(nlon,nlat))
ub_keep = urban_cell(urb_frac, luindex)
write(*,*) trim(vaid), ' from TCAN_URB2D, QCAN_URB2D, PSFC, land-use table ', trim(lu_table), ': ', &
           count(ub_keep), ' urban cells of ', nlon*nlat

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

        filename = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile = trim(filename)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        ! Read wrf var
        status=nf90_inq_varid(ncid,'TCAN_URB2D',varid)
        call ncerror(status,'getting var id TCAN_URB2D in '//trim(infile))

        status=nf90_get_var(ncid,varid,t2,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading TCAN_URB2D from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'PSFC',varid)
        call ncerror(status,'getting var id PSFC in '//trim(infile))

        status=nf90_get_var(ncid,varid,psf,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading PSFC from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'QCAN_URB2D',varid)
        call ncerror(status,'getting var id QCAN_URB2D in '//trim(infile))
!
        status=nf90_get_var(ncid,varid,mr,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading QCAN_URB2D from '//trim(infile))
!
        status=nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
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
! Hardy, B., ITS-90 formulations for vapor pressure, frostpoint temperature, dewpoint temperature, and enhancement
!   factors in the range -100 to +100 C, Proc. Third International Symposium on Humidity and Moisture, 1998
!   (enhancement factor f = exp[a (1 - es/P) + b (P/es - 1)]; corrected here from b (es/P - 1))
!
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
    if (.not. ub_keep(i,j)) then
      outvar(i,j)=1.e+20
      cycle
    endif
        
    e_sfc(i,j)=(mr(i,j)/(epsilon+mr(i,j)))*psf(i,j)
!
    esat(i,j)=exp(a1*t2(i,j)**-2+a2/t2(i,j)+a3+a4*t2(i,j)+a5*t2(i,j)**2+a6*t2(i,j)**3+a7*t2(i,j)**4+a8*log(t2(i,j))) ! ITS-90 @ -100C to 100C. From 0C to 100C is comparable to Wexler's eq15
!
    if(TK(i,j) < 0.)then              ! below 0 degC: enhancement factor of supercooled water (Hardy 1998, -50 to 0 degC)
      fact=exp((fi1+fi2*TK(i,j)+fi3*TK(i,j)**2+fi4*TK(i,j)**3)*(1.-(esat(i,j)/psf(i,j)))+ &
                    exp(fi5+fi6*TK(i,j)+fi7*TK(i,j)**2+fi8*TK(i,j)**3)*((psf(i,j)/esat(i,j))-1.d0))   ! Hardy (1998): b (P/es - 1)
    else
      fact=exp((fw1+fw2*TK(i,j)+fw3*TK(i,j)**2+fw4*TK(i,j)**3)*(1.-(esat(i,j)/psf(i,j)))+ &
                    exp(fw5+fw6*TK(i,j)+fw7*TK(i,j)**2+fw8*TK(i,j)**3)*((psf(i,j)/esat(i,j))-1.d0))   ! Hardy (1998): b (P/es - 1)
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
use shared_io_subs
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
! Call the shared NetCDF writer from shared_io_subs
!
call write_netcdf_rtime_3d(outvar_h, ntime, ttime, bdtime)

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h)

end subroutine write_output


end program read_wrfout

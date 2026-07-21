module datvar
use iso_fortran_env, only: sp => real32, dp => real64
use datvar_s          ! Inherits dimensions, paths, and shared metadata
implicit none

! --- 1. Constants and Fixed Data ---
integer, parameter :: nseason = 4
integer, parameter :: tmonths = 12
    
! Physical Constants
real(sp), parameter :: earthrad = 6372.795_sp
real(sp), parameter :: epsilon  = 0.6220_sp
real(sp), parameter :: Rd       = 287.04_sp
real(sp), parameter :: g        = 9.81_sp
real(sp), parameter :: gamma    = 0.0065_sp
real(sp), parameter :: pconst   = 1.0e5_sp

integer, dimension(tmonths), parameter :: days1 = [31,28,31,30,31,30,31,31,30,31,30,31]
integer, dimension(tmonths), parameter :: days2 = [31,29,31,30,31,30,31,31,30,31,30,31]

! --- 2. Time and Loop Control ---
integer :: level
integer :: ish, issh
integer :: ndays, loop_year
integer :: year, month, day, mydays, hour, dhour, nhours, yhours
integer :: ntime
integer, dimension(tmonths) :: days

! --- 3. NetCDF Specifics ---
!integer :: ncid, varid, status

! --- 4. Scientific Data Arrays ---
! Integer Arrays
integer, dimension(:,:), allocatable :: bdtime, outvar_a
integer, dimension(8)                :: values

! Real Scalars (Unique to datvar)
real(sp) :: cp, rcp, tc

! 2D WRF/Output Arrays
real(sp), dimension(:,:), allocatable :: landmask, sftlf
real(dp), dimension(:,:), allocatable :: wrfv2D, i_wrfv2D, outvar, outvar_i
real(dp), dimension(:,:), allocatable :: rainc, rainnc, i_rainc, i_rainnc, rainsh

! 3D WRF/Atmospheric Arrays
real(dp), dimension(:,:,:), allocatable :: outvar_h, wrfv3D
real(dp), dimension(:,:,:), allocatable :: p, pb, press, phb, ph, phi

! --- 5. Character Strings (Unique to datvar) ---
! Time Formatting
character(len=2) :: ahouri, adayi, amonthi, ahourf, adayf, amonthf
character(len=2) :: ahour, aday, amonth, aiday, mm, dd, hh, mn, ss
character(len=4) :: ayear, ayearf, ayeari, ayearini, yyyy
    
! Metadata/Subroutine labels
character(len=25) :: iwrfvar, fname, subrname, subname
    
! System/Date stamps
character(len=8)  :: date
character(len=10) :: times
character(len=5)  :: zone

end module datvar
!
program read_wrfout
use datvar
use datvar_s
use netcdf
!
cp=(7/2)*Rd
rcp=Rd/cp
tc=273.16+17.5
!
!  Reading headers
!
call readdata
!
!  Initialising counters
!
nzt=nz+1
nhours=24
!
write(ayearini,'(i4)')iniyear
!
ish=0
if(yeari == iniyear)then
  ish=0
else
  nyr=yeari-iniyear
  loop_year=iniyear
  do iyl=1,nyr,1
    if(mod(loop_year,4) == 0. .and. loop_year /= 2100)then
      yhours=366*nhours
    else
      yhours=365*nhours
    endif
    ish=ish+yhours
    loop_year=loop_year+1
  enddo
endif
!
if(imonth < 10) then
  write(amonthi,'(a1,i1)') '0',imonth
else
  write(amonthi,'(i2)') imonth
endif

if(iday < 10) then
  write(adayi,'(a1,i1)') '0',iday
else
  write(adayi,'(i2)') iday
endif

if(ihour < 10) then
  write(ahouri,'(a1,i1)') '0',ihour
else
  write(ahouri,'(i2)') ihour
endif
if(ihour > 0)ish=ish+ihour-1
!
! Read latitude,longitude, grid angles and orography
!
allocate(tlon(nlon,nlat))
allocate(tlat(nlon,nlat))
!
gfile=trim(dir)//trim(geog)//'.nc'
geofile=gfile(1:len_trim(gfile))
write(*,*)geofile
!
status=nf90_open(geofile,nf90_nowrite,ncid)
call ncerror(status,'opening file')

status=nf90_inq_varid(ncid,'CLONG',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,tlon,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'CLONG')
!
status=nf90_inq_varid(ncid,'CLAT',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,tlat,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'CLAT')
!
allocate(rlon(nlon))
allocate(rlat(nlat))
!
do i=1,nlon
 rlon(i)=tlon(i,1)
enddo
do j=1,nlat
 rlat(j)=tlat(1,j)
enddo
deallocate(tlon)
deallocate(tlat)
!
allocate(landmask(nlon,nlat))
allocate(lon(nlon,nlat))
allocate(lat(nlon,nlat))
!
status=nf90_inq_varid(ncid,'XLONG_M',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,lon,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'XLONG_M')
!
status=nf90_inq_varid(ncid,'XLAT_M',varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,lat,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'XLAT_M')
!
status=nf90_inq_varid(ncid,'LANDMASK',varid)
call ncerror(status,'getting var id')

status=nf90_get_var(ncid,varid,landmask,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//'LANDMASK')
!
status=nf90_close(ncid)
call ncerror(status,'closing file')
!
!
! Compute variable
!
allocate(outvar(nlon,nlat))
allocate(outvar_i(nlon,nlat))
allocate(rainc(nlon,nlat))
allocate(rainnc(nlon,nlat))
allocate(rainsh(nlon,nlat))
allocate(i_rainc(nlon,nlat))
allocate(i_rainnc(nlon,nlat))
!
it=0
yearf=yeari+1
!
do year=yeari,yearf,1
!
  write(ayear,'(i4)')year
  !
  if(year == yearf)then
    nmonths=1
  endif
!
  if(it == 0)then
!
    write(ayeari,'(i4)')year

    issh=0
    if(mod(year,4) == 0. .and. year /= 2100)then
      days=days2
      mydays=366
    else
      days=days1
      mydays=365
    endif
    ntime=mydays*nhours

    if(ihour > 0)then
      nhours=nhours-ihour+1
      ntime=ntime-ihour+1
    endif  
!
    allocate(ttime(ntime))
    allocate(bdtime(2,ntime))
    allocate(outvar_h(nlon,nlat,ntime))
  endif  
!
  do month=imonth,nmonths,1
!
    ndays=days(month)
!
    if(month < 10) then
      write(amonth,'(a1,i1)') '0',month
    else
      write(amonth,'(i2)') month
    endif
!
   if(year == yearf)then
      ndays=1
      nhours=1
    endif
!
    write(*,*)year,month

    do day=1,ndays,1
!
      if(day < 10) then
        write(aday,'(a1,i1)') '0',day
      else
        write(aday,'(i2)') day
      endif
!
      loop_h : do hour=ihour,nhours-1,1
!
        dhour = hour
!
        if(hour < 10) then
          write(ahour,'(a1,i1)') '0',dhour
        else
          write(ahour,'(i2)') dhour
        endif
!
        filename=trim(dir2)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
        infile=filename(1:len_trim(filename))
!        write(*,*)infile
!
        status=nf90_open(infile,nf90_nowrite,ncid)
        call ncerror(status,'opening file')
!
        status=nf90_inq_varid(ncid,wrfvar,varid)
        call ncerror(status,'getting var id')
!
        status=nf90_get_var(ncid,varid,rainc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//wrfvar)
!
        status=nf90_inq_varid(ncid,'I_RAINC',varid)
        call ncerror(status,'getting var id')
!
        status=nf90_get_var(ncid,varid,i_rainc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'I_RAINC')
!
        status=nf90_inq_varid(ncid,'RAINNC',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,rainnc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'RAINNC')
!
        status=nf90_inq_varid(ncid,'I_RAINNC',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,i_rainnc,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'I_RAINNC')
!
        status=nf90_inq_varid(ncid,'RAINSH',varid)
        call ncerror(status,'getting var id')

        status=nf90_get_var(ncid,varid,rainsh,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading '//'RAINSH')

        status=nf90_close(ncid)
        call ncerror(status,'closing file')
!
! Compute variable
!
        call calc_pr        
!
        if(it == 0)then
          it=it+1
!
          outvar_i=outvar

          cycle loop_h
        endif

        ish=ish+1
        issh=issh+1
        ttime(issh)=float(ish)-0.5
        bdtime(1,issh)=ish-1
        bdtime(2,issh)=ish

        outvar_h(:,:,issh)=(outvar(:,:)-outvar_i(:,:))/3600.
!
        outvar_i=outvar
!
      enddo loop_h ! end hour
!
      ihour=0
      nhours=24
!
    enddo  ! end day
!
  enddo ! end month
!  
  write(ayearf,'(i4)')year
!
enddo  ! end year
!
!  Write output
!
call write_output
!
end ! end program
!
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_pr
use datvar
use datvar_s
!
do ix=1,nlon
  do iy=1,nlat
    outvar(ix,iy)=((rainc(ix,iy)+i_rainc(ix,iy)*1000.)+(rainnc(ix,iy)+i_rainnc(ix,iy)*1000.)+rainsh(ix,iy))
  enddo
enddo
!
end subroutine calc_pr
!
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_prc
use datvar
use datvar_s
!
do ix=1,nlon
  do iy=1,nlat
    outvar(ix,iy)=(rainc(ix,iy)+i_rainc(ix,iy)*1000.)
  enddo
enddo
!
end subroutine calc_prc
!
!----------------------------------------------------------------------------------------------------------------------
!
subroutine write_output
use datvar
use datvar_s
!
write(*,*) 'writing output'
!
if(month-1 < 10) then
   write(amonthf,'(a1,i1)') '0',month-1
else
   write(amonthf,'(i2)') month-1
endif

if(day-1 < 10) then
  write(adayf,'(a1,i1)') '0',day-1
else
 write(adayf,'(i2)') day-1
endif

if(hour-1 < 10) then
  write(ahourf,'(a1,i1)') '0',hour-1
else
 write(ahourf,'(i2)') hour-1
endif
!
outfile=trim(vaid)//trim(outdom)//'1hr_'//ayeari//amonthi//adayi//ahouri//'-'//ayearf//amonthf//adayf//ahourf//'.nc'
fnameout=outfile(1:len_trim(outfile))
tunts='hours since '//ayearini//'-01-01 00:00'
timeunits=tunts(1:len_trim(tunts))
freq='1hr'
frequency=freq(1:len_trim(freq))
experi=trim(dexp_id)
experiment_id=experi(1:len_trim(experi))
exper=trim(adexp)
experiment=exper(1:len_trim(exper))

if(factor /= 0.) outvar_h=outvar_h*factor

call date_and_time(date,times,zone,values)

write(yyyy,'(i4)')values(1)
if(values(2) < 10)then
  write(mm,'(a1,i1)')'0',values(2)
else
  write(mm,'(i2)')values(2)
endif
if(values(3) < 10)then
  write(dd,'(a1,i1)')'0',values(3)
else
  write(dd,'(i2)')values(3)
endif
if(values(5) < 10)then
  write(hh,'(a1,i1)')'0',values(5)
else
  write(hh,'(i2)')values(5)
endif
if(values(6) < 10)then
  write(mn,'(a1,i1)')'0',values(6)
else
  write(mn,'(i2)')values(6)
endif
if(values(7) < 10)then
  write(ss,'(a1,i1)')'0',values(7)
else
  write(ss,'(i2)')values(7)
endif
cdate=yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
creationdate=cdate(1:len_trim(cdate))

call write_netcdf_rtime(outvar_h,ntime,ttime,bdtime)

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h)
!
end subroutine write_output
!

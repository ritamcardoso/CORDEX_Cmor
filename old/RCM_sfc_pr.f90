module datvar
!
!  nz         : total number of vertical levels
!
integer, parameter :: nseason=4,tmonths=12
integer :: nlon,nlat,nz,nzt,xoffset,yoffset,level,nsoil
integer :: ish,issh
integer :: yeari,yearf,iniyear,nmonths,imonth,ndays,iday,ihour,loop_year
integer :: year,month,day,mydays,hour,dhour,nhours,yhours
integer :: ntime
integer, dimension(:,:), allocatable :: bdtime,outvar_a
integer, dimension(8) :: values
integer, dimension(tmonths) :: days,days1,days2
!
integer :: ncid,varid,status
integer :: latid,lonid,timeid,levid,timedim,latdim,londim,levdim
!
real :: cp,rcp,tc,rhours,factor,heightl,presl
real, dimension(1) :: height
real, dimension(1) :: pressure
real, dimension(:), allocatable :: ttime
real, dimension(:), allocatable :: rlon
real, dimension(:), allocatable :: rlat
real, dimension(:,:), allocatable :: lon,lat,tlon,tlat,cosalp,sinalp,landmask,sftlf
real, dimension(:,:), allocatable  :: wrfv2D,i_wrfv2D,outvar,outvar_i
real, dimension(:,:), allocatable  :: rainc,rainnc,i_rainc,i_rainnc,rainsh
real, dimension(:,:,:), allocatable :: outvar_h,wrfv3D
real, dimension(:,:,:), allocatable  :: p,pb,press,phb,ph,phi
real, parameter :: earthrad=6372.795,epsilon=0.6220,Rd=287.04,g=9.81,gamma=0.0065,pconst=1.0e5
!
character*2 ahouri,adayi,amonthi,ahourf,adayf,amonthf,ahour,aday,amonth,aiday,dom,mm,dd,hh,mn,ss
character*4 ayear,ayearf,ayeari,ayearini,yyyy
character*10 vaid,varname,vunts,vunits
character*25 wrfile,wrffile,geo,geog,wrfvar,iwrfvar,fname,wrfvarname,subrname,subname
character*100 longname,standardname,cellmethods,timeunits,frequency,experiment_id,experiment,creationdate
character*100 lname,stname,cmethods,tunts,freq,experi,exper,cdate
character*400 infile,filename,outfile,outdom,fnameout,dir,dir2,gfile,geofile,dexp_id,adexp
character(8) :: date
character(10) :: times
character(5) :: zone
!
data days1/31,28,31,30,31,30,31,31,30,31,30,31/
data days2/31,29,31,30,31,30,31,31,30,31,30,31/
!
end module datvar
!
program read_wrfout
use datvar
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
!-----------------------------------------------------------------------
!
subroutine ncerror(status,info)
use netcdf
integer :: status
character(len=*),optional :: info

if( status /= 0 ) then
  print *, trim(nf90_strerror(status))
  if( present(info) ) print*,trim(info)
  stop 99
endif

end subroutine ncerror
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime(uvar,mtime,utime,btime)
use netcdf
use datvar
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(nf90_noclobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 2)
call handle_err(status)

status = nf90_put_att(ncid, TVarID, "standard_name","time")
status = nf90_put_att(ncid, TVarID, "long_name","time")
status = nf90_put_att(ncid, TVarID, "bounds","time_bnds")
status = nf90_put_att(ncid, TVarID, "units",timeunits)
status = nf90_put_att(ncid, TVarID, "calender","standard")
status = nf90_put_att(ncid, TVarID, "axis","T")

status = nf90_put_att(ncid, TBVarID, "long_name","time bounds")
status = nf90_put_att(ncid, TBVarID, "units",timeunits)
status = nf90_put_att(ncid, TBVarID, "calender","standard")

status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_pole")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)

status = nf90_put_att(ncid, LonVarID, "long_name","longitude")
status = nf90_put_att(ncid, LonVarID, "standard_name","longitude")
status = nf90_put_att(ncid, LonVarID, "units","degrees_east")
status = nf90_put_att(ncid, LonVarID, "_CoordinateAxisType","Lon")
call handle_err(status)

status = nf90_put_att(ncid, LatVarID, "long_name","latitude")
status = nf90_put_att(ncid, LatVarID, "standard_name","latitude")
status = nf90_put_att(ncid, LatVarID, "units","degrees_north")
status = nf90_put_att(ncid, LatVarID, "_CoordinateAxisType","Lat")
call handle_err(status)

status = nf90_put_att(ncid, rlonVarID, "long_name","longitude in rotated pole grid")
status = nf90_put_att(ncid, rlonVarID, "standard_name","grid_longitude")
status = nf90_put_att(ncid, rlonVarID, "units","degrees")
status = nf90_put_att(ncid, rlonVarID, "axis","X")
call handle_err(status)

status = nf90_put_att(ncid, rlatVarID, "long_name","latitude in rotated pole grid")
status = nf90_put_att(ncid, rlatVarID, "standard_name","grid_latitude")
status = nf90_put_att(ncid, rlatVarID, "units","degrees")
status = nf90_put_att(ncid, rlatVarID, "axis","Y")
call handle_err(status)

status = nf90_put_att(ncid, rpVarID, "grid_mapping_name","rotated_latitude_longitude")
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_latitude", 39.25 )
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_longitude", -162. )
status = nf90_put_att(ncid, rpVarID, "earth_radius", 6371229. )
call handle_err(status)

status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.11")
status = nf90_put_att(ncid, nf90_global, "activity_id","DD")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-11")
status = nf90_put_att(ncid, nf90_global, "domain","Europe")
status = nf90_put_att(ncid, nf90_global, "domain_id","EUR-12")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "driving_experiment_id",experiment_id)
status = nf90_put_att(ncid, nf90_global, "driving_institution_id","MPI-M")
status = nf90_put_att(ncid, nf90_global, "driving_source_id","MPI-ESM1-2-HR")
status = nf90_put_att(ncid, nf90_global, "driving_source","MPI-ESM1.2-HR (2017): \naerosol: none, prescribed MACv2-SP\natmos: ECHAM6.3 (spectral T127; 384 x 192 longitude/latitude; 95 levels; top level 0.01 hPa)\natmosChem: none\nland: JSBACH3.20\nlandIce: none/prescribed\nocean: MPIOM1.63 (tripolar TP04, approximately 0.4deg; 802 x 404 longitude/latitude; 40 levels; top grid cell 0-12 m)\nocnBgchem: HAMOCC6\nseaIce: unnamed (thermodynamic (Semtner zero-layer) dynamic (Hibler 79) sea ice model)")
status = nf90_put_att(ncid, nf90_global, "driving_variant_lable","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "further_info_url","https://github.com/CORDEX-WRF-community/euro-cordex-cmip6")
status = nf90_put_att(ncid, nf90_global, "grid","Rotated-pole latitude-longitude with 0.11 degree grid spacing")
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institution_id","IDL-FCUL")
status = nf90_put_att(ncid, nf90_global, "label","WRF V4.5.1-Q")
status = nf90_put_att(ncid, nf90_global, "label_extended","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "license","https://cordex.org/data-access/cordex-cmip6-data/cordex-cmip6-terms-of-use")
status = nf90_put_att(ncid, nf90_global, "mip_era","CMIP6")
status = nf90_put_att(ncid, nf90_global, "product","model-output")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX-CMIP6. CMIP6-driven Coordinated Regional Climate Downscaling Experiment")
status = nf90_put_att(ncid, nf90_global, "release_year","2022")
status = nf90_put_att(ncid, nf90_global, "source","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "source_id","WRF451Q")
status = nf90_put_att(ncid, nf90_global, "source_type","ARMC")
status = nf90_put_att(ncid, nf90_global, "variable_id",varname)
status = nf90_put_att(ncid, nf90_global, "version_realisation","v1-r1")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","2015-01-01_06:00:00")
status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, utime )
call handle_err(status)
status = nf90_put_var(ncid, TBVarID, btime )
call handle_err(status)
status = nf90_put_var(ncid, LonVarId, lon )
call handle_err(status)
status = nf90_put_var(ncid, LatVarId, lat )
call handle_err(status)
status = nf90_put_var(ncid, rlonVarId, rlon )
call handle_err(status)
status = nf90_put_var(ncid, rlatVarId, rlat )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
return
end
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime_h(uvar,mtime,utime,btime)
use netcdf
use datvar
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(nf90_noclobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, "height", nf90_double, HVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 2)
call handle_err(status)

status = nf90_put_att(ncid, TVarID, "standard_name","time")
status = nf90_put_att(ncid, TVarID, "long_name","time")
status = nf90_put_att(ncid, TVarID, "bounds","time_bnds")
status = nf90_put_att(ncid, TVarID, "units",timeunits)
status = nf90_put_att(ncid, TVarID, "calender","standard")
status = nf90_put_att(ncid, TVarID, "axis","T")

status = nf90_put_att(ncid, TBVarID, "long_name","time bounds")
status = nf90_put_att(ncid, TBVarID, "units",timeunits)
status = nf90_put_att(ncid, TBVarID, "calender","standard")

status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_pole")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time height")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)

status = nf90_put_att(ncid, HVarID, "long_name","height above the surface")
status = nf90_put_att(ncid, HVarID, "standard_name","height")
status = nf90_put_att(ncid, HVarID, "positive","up")
status = nf90_put_att(ncid, HVarID, "axis","Z")
status = nf90_put_att(ncid, HVarID, "units","m")

status = nf90_put_att(ncid, LonVarID, "long_name","longitude")
status = nf90_put_att(ncid, LonVarID, "standard_name","longitude")
status = nf90_put_att(ncid, LonVarID, "units","degrees_east")
status = nf90_put_att(ncid, LonVarID, "_CoordinateAxisType","Lon")
call handle_err(status)

status = nf90_put_att(ncid, LatVarID, "long_name","latitude")
status = nf90_put_att(ncid, LatVarID, "standard_name","latitude")
status = nf90_put_att(ncid, LatVarID, "units","degrees_north")
status = nf90_put_att(ncid, LatVarID, "_CoordinateAxisType","Lat")
call handle_err(status)

status = nf90_put_att(ncid, rlonVarID, "long_name","longitude in rotated pole grid")
status = nf90_put_att(ncid, rlonVarID, "standard_name","grid_longitude")
status = nf90_put_att(ncid, rlonVarID, "units","degrees")
status = nf90_put_att(ncid, rlonVarID, "axis","X")
call handle_err(status)

status = nf90_put_att(ncid, rlatVarID, "long_name","latitude in rotated pole grid")
status = nf90_put_att(ncid, rlatVarID, "standard_name","grid_latitude")
status = nf90_put_att(ncid, rlatVarID, "units","degrees")
status = nf90_put_att(ncid, rlatVarID, "axis","Y")
call handle_err(status)

status = nf90_put_att(ncid, rpVarID, "grid_mapping_name","rotated_latitude_longitude")
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_latitude", 39.25 )
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_longitude", -162. )
status = nf90_put_att(ncid, rpVarID, "earth_radius", 6371229. )
call handle_err(status)

status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.11")
status = nf90_put_att(ncid, nf90_global, "activity_id","DD")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-11")
status = nf90_put_att(ncid, nf90_global, "domain","Europe")
status = nf90_put_att(ncid, nf90_global, "domain_id","EUR-12")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "driving_experiment_id",experiment_id)
status = nf90_put_att(ncid, nf90_global, "driving_institution_id","MPI-M")
status = nf90_put_att(ncid, nf90_global, "driving_source_id","MPI-ESM1-2-HR")
status = nf90_put_att(ncid, nf90_global, "driving_source","MPI-ESM1.2-HR (2017): \naerosol: none, prescribed MACv2-SP\natmos: ECHAM6.3 (spectral T127; 384 x 192 longitude/latitude; 95 levels; top level 0.01 hPa)\natmosChem: none\nland: JSBACH3.20\nlandIce: none/prescribed\nocean: MPIOM1.63 (tripolar TP04, approximately 0.4deg; 802 x 404 longitude/latitude; 40 levels; top grid cell 0-12 m)\nocnBgchem: HAMOCC6\nseaIce: unnamed (thermodynamic (Semtner zero-layer) dynamic (Hibler 79) sea ice model)")
status = nf90_put_att(ncid, nf90_global, "driving_variant_lable","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "further_info_url","https://github.com/CORDEX-WRF-community/euro-cordex-cmip6")
status = nf90_put_att(ncid, nf90_global, "grid","Rotated-pole latitude-longitude with 0.11 degree grid spacing")
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institution_id","IDL-FCUL")
status = nf90_put_att(ncid, nf90_global, "label","WRF V4.5.1-Q")
status = nf90_put_att(ncid, nf90_global, "label_extended","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "license","https://cordex.org/data-access/cordex-cmip6-data/cordex-cmip6-terms-of-use")
status = nf90_put_att(ncid, nf90_global, "mip_era","CMIP6")
status = nf90_put_att(ncid, nf90_global, "product","model-output")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX-CMIP6. CMIP6-driven Coordinated Regional Climate Downscaling Experiment")
status = nf90_put_att(ncid, nf90_global, "release_year","2022")
status = nf90_put_att(ncid, nf90_global, "source","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "source_id","WRF451Q")
status = nf90_put_att(ncid, nf90_global, "source_type","ARMC")
status = nf90_put_att(ncid, nf90_global, "variable_id",varname)
status = nf90_put_att(ncid, nf90_global, "version_realisation","v1-r1")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","2015-01-01_06:00:00")
status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, utime )
call handle_err(status)
status = nf90_put_var(ncid, TBVarID, btime )
call handle_err(status)
status = nf90_put_var(ncid, LonVarId, lon )
call handle_err(status)
status = nf90_put_var(ncid, LatVarId, lat )
call handle_err(status)
status = nf90_put_var(ncid, rlonVarId, rlon )
call handle_err(status)
status = nf90_put_var(ncid, rlatVarId, rlat )
call handle_err(status)
status = nf90_put_var(ncid, HVarID, height )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
return
end
!
!-----------------------------------------------------------------------
!
subroutine write_netcdf_rtime_p(uvar,mtime,utime,btime)
use netcdf
use datvar
!
!integer :: status
!integer :: ncid
integer :: LatDimID,LonDimID,rlonDimID,rlatDimID,HDimID,BDimID,HeDimID
integer :: LonVarID,LatVarID,TBVarID,TVarID,rlatVarId,rlonVarID,uVarID,HVarID,rpVarID
integer, dimension(2,mtime) :: btime
real, dimension(mtime) :: utime
real, dimension(nlon,nlat,mtime) :: uvar
real, parameter :: FillValue=1.e+20

status = nf90_create(fnameout, IOR(nf90_noclobber, nf90_netcdf4), ncid)
call handle_err(status)

status = nf90_def_dim(ncid, "rlon", nlon, LonDimID)
status = nf90_def_dim(ncid, "rlat", nlat, LatDimID)
status = nf90_def_dim(ncid, "bnds", 2, BDimID)
status = nf90_def_dim(ncid, "time", nf90_unlimited, HDimID)

status = nf90_def_var(ncid, "time", nf90_double, &
                            (/ HDimID /), TVarId)
status = nf90_def_var(ncid, "time_bnds", nf90_double, &
                            (/ BDimID, HDimID /), TBVarId)

status = nf90_def_var(ncid, "lon", nf90_double, &
                            (/ LonDimId, LatDimID /), LonVarId)
status = nf90_def_var(ncid, "lat", nf90_double, &
                            (/ LonDimId, LatDimID /), LatVarId)
status = nf90_def_var(ncid, "rlon", nf90_double, &
                            (/ LonDimId /), rlonVarId)
status = nf90_def_var(ncid, "rlat", nf90_double, &
                            (/ LatDimID /), rlatVarId)
status = nf90_def_var(ncid, "rotated_pole", nf90_char,rpVarId)

status = nf90_def_var(ncid, "press", nf90_double, HVarId)

status = nf90_def_var(ncid, varname, nf90_float, &
                            (/ LonDimId, LatDimID, HDimID /), uVarId)
call handle_err(status)

! chunk by [nlon, nlat, 1] to optimize for one time-step at a time
status = nf90_def_var_chunking(ncid, uVarId, nf90_chunked, (/ nlon, nlat, 1 /))
call handle_err(status)

! Compression call
status = nf90_def_var_deflate(ncid, uVarId, shuffle = 1, deflate = 1, deflate_level = 2)
call handle_err(status)

status = nf90_put_att(ncid, TVarID, "standard_name","time")
status = nf90_put_att(ncid, TVarID, "long_name","time")
status = nf90_put_att(ncid, TVarID, "bounds","time_bnds")
status = nf90_put_att(ncid, TVarID, "units",timeunits)
status = nf90_put_att(ncid, TVarID, "calender","standard")
status = nf90_put_att(ncid, TVarID, "axis","T")

status = nf90_put_att(ncid, TBVarID, "long_name","time bounds")
status = nf90_put_att(ncid, TBVarID, "units",timeunits)
status = nf90_put_att(ncid, TBVarID, "calender","standard")

status = nf90_put_att(ncid, uVarID, "standard_name",standardname)
status = nf90_put_att(ncid, uVarID, "long_name",longname)
status = nf90_put_att(ncid, uVarID, "units",vunits)
status = nf90_put_att(ncid, uVarID, "grid_mapping","rotated_pole")
status = nf90_put_att(ncid, uVarID, "coordinates","lat lon time press")
status = nf90_put_att(ncid, uVarID, "cell_methods",cellmethods)
status = nf90_put_att(ncid, uVarID, "cell_measures","area: areacella")
status = nf90_put_att(ncid, uVarID, "_FillValue",FillValue)
status = nf90_put_att(ncid, uVarID, "missing_value",FillValue)

status = nf90_put_att(ncid, HVarID, "long_name","pressure")
status = nf90_put_att(ncid, HVarID, "standard_name","air_pressure")
status = nf90_put_att(ncid, HVarID, "positive","down")
status = nf90_put_att(ncid, HVarID, "axis","Z")
status = nf90_put_att(ncid, HVarID, "units","hPa")

status = nf90_put_att(ncid, LonVarID, "long_name","longitude")
status = nf90_put_att(ncid, LonVarID, "standard_name","longitude")
status = nf90_put_att(ncid, LonVarID, "units","degrees_east")
status = nf90_put_att(ncid, LonVarID, "_CoordinateAxisType","Lon")
call handle_err(status)

status = nf90_put_att(ncid, LatVarID, "long_name","latitude")
status = nf90_put_att(ncid, LatVarID, "standard_name","latitude")
status = nf90_put_att(ncid, LatVarID, "units","degrees_north")
status = nf90_put_att(ncid, LatVarID, "_CoordinateAxisType","Lat")
call handle_err(status)

status = nf90_put_att(ncid, rlonVarID, "long_name","longitude in rotated pole grid")
status = nf90_put_att(ncicdd, rlonVarID, "standard_name","grid_longitude")
status = nf90_put_att(ncid, rlonVarID, "units","degrees")
status = nf90_put_att(ncid, rlonVarID, "axis","X")
call handle_err(status)

status = nf90_put_att(ncid, rlatVarID, "long_name","latitude in rotated pole grid")
status = nf90_put_att(ncid, rlatVarID, "standard_name","grid_latitude")
status = nf90_put_att(ncid, rlatVarID, "units","degrees")
status = nf90_put_att(ncid, rlatVarID, "axis","Y")
call handle_err(status)

status = nf90_put_att(ncid, rpVarID, "grid_mapping_name","rotated_latitude_longitude")
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_latitude", 39.25 )
status = nf90_put_att(ncid, rpVarID, "grid_north_pole_longitude", -162. )
status = nf90_put_att(ncid, rpVarID, "earth_radius", 6371229. )
call handle_err(status)

status = nf90_put_att(ncid, nf90_global, "Conventions","CF-1.11")
status = nf90_put_att(ncid, nf90_global, "activity_id","DD")
status = nf90_put_att(ncid, nf90_global, "contact","Rita Cardoso, rmcardoso@fc.ul.pt; Pedro Soares, pmsoares@fc.ul.pt")
status = nf90_put_att(ncid, nf90_global, "creation_date",creationdate)
status = nf90_put_att(ncid, nf90_global, "CORDEX_domain","EUR-11")
status = nf90_put_att(ncid, nf90_global, "domain","Europe")
status = nf90_put_att(ncid, nf90_global, "domain_id","EUR-12")
status = nf90_put_att(ncid, nf90_global, "driving_experiment",experiment)
status = nf90_put_att(ncid, nf90_global, "driving_experiment_id",experiment_id)
status = nf90_put_att(ncid, nf90_global, "driving_institution_id","MPI-M")
status = nf90_put_att(ncid, nf90_global, "driving_source_id","MPI-ESM1-2-HR")
status = nf90_put_att(ncid, nf90_global, "driving_source","MPI-ESM1.2-HR (2017): \naerosol: none, prescribed MACv2-SP\natmos: ECHAM6.3 (spectral T127; 384 x 192 longitude/latitude; 95 levels; top level 0.01 hPa)\natmosChem: none\nland: JSBACH3.20\nlandIce: none/prescribed\nocean: MPIOM1.63 (tripolar TP04, approximately 0.4deg; 802 x 404 longitude/latitude; 40 levels; top grid cell 0-12 m)\nocnBgchem: HAMOCC6\nseaIce: unnamed (thermodynamic (Semtner zero-layer) dynamic (Hibler 79) sea ice model)")
status = nf90_put_att(ncid, nf90_global, "driving_variant_lable","r1i1p1")
status = nf90_put_att(ncid, nf90_global, "frequency",frequency)
status = nf90_put_att(ncid, nf90_global, "further_info_url","https://github.com/CORDEX-WRF-community/euro-cordex-cmip6")
status = nf90_put_att(ncid, nf90_global, "grid","Rotated-pole latitude-longitude with 0.11 degree grid spacing")
status = nf90_put_att(ncid, nf90_global, "institution","Instituto Dom Luiz - Universidade de Lisboa")
status = nf90_put_att(ncid, nf90_global, "institution_id","IDL-FCUL")
status = nf90_put_att(ncid, nf90_global, "label","WRF V4.5.1-Q")
status = nf90_put_att(ncid, nf90_global, "label_extended","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "license","https://cordex.org/data-access/cordex-cmip6-data/cordex-cmip6-terms-of-use")
status = nf90_put_att(ncid, nf90_global, "mip_era","CMIP6")
status = nf90_put_att(ncid, nf90_global, "product","model-output")
status = nf90_put_att(ncid, nf90_global, "project_id","CORDEX-CMIP6. CMIP6-driven Coordinated Regional Climate Downscaling Experiment")
status = nf90_put_att(ncid, nf90_global, "release_year","2022")
status = nf90_put_att(ncid, nf90_global, "source","Weather Research and Forecasting model version 4.5.1, CORDEX WRF Community configuration Q")
status = nf90_put_att(ncid, nf90_global, "source_id","WRF451Q")
status = nf90_put_att(ncid, nf90_global, "source_type","ARMC")
status = nf90_put_att(ncid, nf90_global, "variable_id",varname)
status = nf90_put_att(ncid, nf90_global, "version_realisation","v1-r1")
status = nf90_put_att(ncid, nf90_global, "simulation_start_date","2015-01-01_06:00:00")
status = nf90_put_att(ncid, nf90_global, "west_east_grid_dimension",445)
status = nf90_put_att(ncid, nf90_global, "south_north_grid_dimension",433)
status = nf90_put_att(ncid, nf90_global, "bottom_top_grid_dimension",54)
status = nf90_put_att(ncid, nf90_global, "dx",12229.52)
status = nf90_put_att(ncid, nf90_global, "dy",12229.52)

status = nf90_enddef(ncid)

status = nf90_put_var(ncid, TVarId, utime )
call handle_err(status)
status = nf90_put_var(ncid, TBVarID, btime )
call handle_err(status)
status = nf90_put_var(ncid, LonVarId, lon )
call handle_err(status)
status = nf90_put_var(ncid, LatVarId, lat )
call handle_err(status)
status = nf90_put_var(ncid, rlonVarId, rlon )
call handle_err(status)
status = nf90_put_var(ncid, rlatVarId, rlat )
call handle_err(status)
status = nf90_put_var(ncid, HVarID, pressure )
call handle_err(status)
status = nf90_put_var(ncid, uVarId, uvar )
call handle_err(status)

status = nf90_close(ncid)
call handle_err(status)
!
return
end
!
!
!-------------------------------------------------------------------------------------
!
subroutine handle_err(status)

use netcdf

integer, intent ( in) :: status

if(status /= nf90_noerr) then
  print*, trim(nf90_strerror(status))
  stop "Stopped"
end if
end subroutine handle_err
!
!-----------------------------------------------------------------------
!
subroutine readdata
!
! Reads the input data and the data option switches
!
!     Calls funtion uppercase to transform the indexing keywords into
!     upercase indexes
!
use datvar
integer :: itext,inperr,ichlef,ichrig,ii
real :: verbose
character(20) :: keyword,uppercase
character(80) :: line
external uppercase
logical ok_iniyear,ok_yeari,ok_yearf,ok_nmonth,ok_imonth,ok_ihour
logical ok_ndays,ok_iday,ok_nlon,ok_nlat,ok_nz,ok_xoffset,ok_yoffset,ok_dir,ok_dir2,ok_dom,ok_outdom
logical ok_wrfvar,ok_vaid,ok_vunts,ok_lname,ok_stname,ok_cmethods,ok_geog,ok_wrffile,ok_exp,ok_dexp
!
open(10,file='outputlist.inp')
!
read(10,'(a)')line
if(uppercase(line(1:12)).ne.'CORDEX') then
  write(*,*) 'Wrong Input file outputlist.inp !'
  stop
endif
!
open(27,status='scratch')
!
ok_iniyear=.false.
ok_yeari=.false.
ok_yearf=.false.
ok_nmonth=.false.
ok_imonth=.false.
ok_iday=.false.
ok_ihour=.false.
ok_nlon=.false.
ok_nlat=.false.
ok_nz=.false.
ok_xoffset=.false.
ok_yoffset=.false.
ok_dir=.false.
ok_dir2=.false.
ok_geog=.false.
ok_wrffile=.false.
ok_dom=.false.
ok_outdom=.false.
ok_wrfvar=.false.
ok_vaid=.false.
ok_vunts=.false.
ok_lname=.false.
ok_stname=.false.
ok_cmethods=.false.
!
itext=0
inperr=0
do while(inperr.eq.0)
  read(10,'(a)') line
!
! Isolate keyword
!
  ichlef=1
  do i=1,80
    if(line(i:i).ne.' ') exit
    ichlef=i
  enddo
  if(ichlef.eq.80) cycle
  ichrig=ichlef
  do i=ichlef+1,80
    if(line(i:i).eq.' ') exit
    ichrig=i
  enddo
  keyword=line(ichlef:ichrig)
  call toupcase(keyword)
  write(27,'(a)') line(ichrig+1:80)
  backspace(27)
  if(keyword(1:3).eq.uppercase('end')) then
    exit
  elseif(keyword(1:1).eq.'#') then
    cycle
  elseif(keyword.eq.uppercase('verbose')) then
    read(27,*,iostat=inperr) verbose
    if(verbose.ge.1) write(*,*) 'verbose=',verbose
  elseif(keyword.eq.uppercase('yeari')) then
    read(27,*,iostat=inperr) yeari
    if(verbose.ge.1) write(*,*) 'yeari=',yeari
    ok_yeari=.true.
  elseif(keyword.eq.uppercase('iniyear')) then
    read(27,*,iostat=inperr) iniyear
    if(verbose.ge.1) write(*,*) 'iniyear=',iniyear
    ok_iniyear=.true.
  elseif(keyword.eq.uppercase('yearf')) then
    read(27,*,iostat=inperr) yearf
    if(verbose.ge.1) write(*,*) 'yearf=',yearf
    ok_yearf=.true.
  elseif(keyword.eq.uppercase('nmonth')) then
    read(27,*,iostat=inperr) nmonths
    if(verbose.ge.1) write(*,*) 'nmonth=',nmonths
    ok_nmonth=.true.
  elseif(keyword.eq.uppercase('imonth')) then
    read(27,*,iostat=inperr) imonth
    if(verbose.ge.1) write(*,*) 'imonth=',imonth
    ok_imonth=.true.
  elseif(keyword.eq.uppercase('iday')) then
    read(27,*,iostat=inperr) iday
    if(verbose.ge.1) write(*,*) 'iday=',iday
    ok_iday=.true.
  elseif(keyword.eq.uppercase('ihour')) then
    read(27,*,iostat=inperr) ihour
    if(verbose.ge.1) write(*,*) 'ihour=',ihour
    ok_ihour=.true.
  elseif(keyword.eq.uppercase('xoffset')) then
    read(27,*,iostat=inperr) xoffset
    if(verbose.ge.1) write(*,*) 'xoffset=',xoffset
    ok_xoffset=.true.
  elseif(keyword.eq.uppercase('yoffset')) then
    read(27,*,iostat=inperr) yoffset
    if(verbose.ge.1) write(*,*) 'yoffset=',yoffset
    ok_yoffset=.true.
  elseif(keyword.eq.uppercase('nlon')) then
    read(27,*,iostat=inperr) nlon
    if(verbose.ge.1) write(*,*) 'nlon=',nlon
    ok_nlon=.true.
  elseif(keyword.eq.uppercase('nlat')) then
    read(27,*,iostat=inperr) nlat
    if(verbose.ge.1) write(*,*) 'nlat=',nlat
    ok_nlat=.true.
  elseif(keyword.eq.uppercase('nz')) then
    read(27,*,iostat=inperr) nz
    if(verbose.ge.1) write(*,*) 'nz=',nz
    ok_nz=.true.
  elseif(keyword.eq.uppercase('nsoil')) then
    read(27,*,iostat=inperr) nsoil
    if(verbose.ge.1) write(*,*) 'nsoil=',nsoil
    ok_nsoil=.true.
  elseif(keyword.eq.uppercase('dir')) then
    read(27,*,iostat=inperr) dir
    if(verbose.ge.1) write(*,*) 'dir=',dir
    ok_dir=.true.
  elseif(keyword.eq.uppercase('dir2')) then
    read(27,*,iostat=inperr) dir2
    if(verbose.ge.1) write(*,*) 'dir2=',dir2
    ok_dir2=.true.
  elseif(keyword.eq.uppercase('dom')) then
    read(27,*,iostat=inperr) dom
    if(verbose.ge.1) write(*,*) 'dom=',dom
    ok_dom=.true.
  elseif(keyword.eq.uppercase('outdom')) then
    read(27,*,iostat=inperr) outdom
    if(verbose.ge.1) write(*,*) 'outdom=',outdom
    ok_outdom=.true.
  elseif(keyword.eq.uppercase('dexp_id')) then
    read(27,*,iostat=inperr) dexp_id
    if(verbose.ge.1) write(*,*) 'dexp_id=',dexp_id
    ok_exp=.true.
  elseif(keyword.eq.uppercase('dexp')) then
    read(27,*,iostat=inperr) adexp
    if(verbose.ge.1) write(*,*) 'dexp=',adexp
    ok_dexp=.true.
  elseif(keyword.eq.uppercase('geog')) then
    read(27,*,iostat=inperr) geo
    if(verbose.ge.1) write(*,*) 'geo file=',geo
    ok_geog=.true.

    geog=geo(1:len_trim(geo))

  elseif(keyword.eq.uppercase('wrffile')) then
    read(27,*,iostat=inperr) wrffile
    if(verbose.ge.1) write(*,*) 'wrf file=',wrffile
    ok_wrffile=.true.

    wrfile=wrffile(1:len_trim(wrffile))

  elseif(keyword.eq.uppercase('wrfvar')) then
    read(27,*,iostat=inperr) wrfvar
    if(verbose.ge.1) write(*,*) 'wrfvar=',wrfvar
    ok_wrfvar=.true.

    wrfvarname=wrfvar(1:len_trim(wrfvar))

  elseif(keyword.eq.uppercase('vaid'))then
    read(27,*,iostat=inperr)vaid
    if(verbose.ge.1) write(*,*)'var id=',vaid
    ok_vaid=.true.

    varname=vaid(1:len_trim(vaid))

  elseif(keyword.eq.uppercase('vunts'))then
    read(27,*,iostat=inperr)vunts
    if(verbose.ge.1) write(*,*)'var units=',vunts
    ok_vunts=.true.

    vunits=vunts(1:len_trim(vunts))

  elseif(keyword.eq.uppercase('lname'))then
    read(27,*,iostat=inperr)lname
    if(verbose.ge.1) write(*,*)'var long name=',lname
    ok_lname=.true.

    longname=lname(1:len_trim(lname))

  elseif(keyword.eq.uppercase('stname'))then
    read(27,*,iostat=inperr)stname
    if(verbose.ge.1) write(*,*)'var standard name=',stname
    ok_stname=.true.

    standardname=stname(1:len_trim(stname))

  elseif(keyword.eq.uppercase('cmethods'))then
    read(27,*,iostat=inperr)cmethods
    if(verbose.ge.1) write(*,*)'var time agregation =',cmethods
    ok_cmethods=.true.

    cellmethods=cmethods(1:len_trim(cmethods))

  elseif(keyword.eq.uppercase('height'))then
    read(27,*,iostat=inperr) heightl
    if(verbose.ge.1) write(*,*) 'height=',heightl
    height=heightl
  elseif(keyword.eq.uppercase('pres'))then
    read(27,*,iostat=inperr) presl
    if(verbose.ge.1) write(*,*) 'pressure=',presl
    pressure=presl/100.
  elseif(keyword.eq.uppercase('factor'))then
    read(27,*,iostat=inperr)factor
    if(verbose.ge.1) write(*,*)'factor=',factor
  else
    write(*,*) 'Unrecognized keyword !!:',keyword
    stop
  endif
  if(inperr.gt.0) then
    write(*,*) 'Input error from outputlist'
    stop
  endif
enddo
!
! Check data
!
if(.not.ok_iniyear) then
  write(*,*) 'Aborted due to missing data: iniyear'
  stop
endif
if(.not.ok_yeari) then
  write(*,*) 'Aborted due to missing data: yeari'
  stop
endif
if(.not.ok_yearf) then
  write(*,*) 'Aborted due to missing data: yearf'
  stop
endif
if(.not.ok_nmonth) then
  write(*,*) 'Aborted due to missing data: nmonth'
  stop
endif
if(.not.ok_imonth) then
  write(*,*) 'Aborted due to missing data: imonth'
  stop
endif
if(.not.ok_iday) then
  write(*,*) 'Aborted due to missing data: iday'
  stop
endif
if(.not.ok_ihour) then
  write(*,*) 'Aborted due to missing data: ihour'
  stop
endif
if(.not.ok_dir) then
  write(*,*) 'Aborted due to missing input dir: dir'
  stop
endif
if(.not.ok_dir2) then
  write(*,*) 'Aborted due to missing input dir2: dir2'
  stop
endif
if(.not.ok_geog) then
  write(*,*) 'Aborted due to missing input geo_em file name'
  stop
endif
if(.not.ok_wrffile) then
  write(*,*) 'Aborted due to missing input wrf file name'
  stop
endif
if(.not.ok_dom) then
  write(*,*) 'Aborted due to missing input domain: dom'
  stop
endif
if(.not.ok_outdom) then
  write(*,*) 'Aborted due to missing output domain: outdom'
  stop
endif
if(.not.ok_wrfvar) then
  write(*,*) 'Aborted due to missing wrf input var: wrfvar'
  stop
endif
if(.not.ok_vaid) then
  write(*,*) 'Aborted due to missing output var id: vaid'
  stop
endif
if(.not.ok_vunts) then
  write(*,*) 'Aborted due to missing output var units: vunts'
  stop
endif
if(.not.ok_lname) then
  write(*,*) 'Aborted due to missing output var long name: lname'
  stop
endif
if(.not.ok_stname) then
  write(*,*) 'Aborted due to missing output var standard name: stname'
  stop
endif
if(.not.ok_cmethods) then
  write(*,*) 'Aborted due to missing output var agregation methods: cmethods'
  stop
endif
return
end
!
!-----------------------------------------------------------------------
!
subroutine toupcase(string)
!
! Converts string to uppercase
!
!     From nhli9902 - Miranda 1998
!
character (len=*) string
integer i,ismall,ibig
ismall=ichar('a')
ibig=ichar('A')
do i=1,len(string)
  if(string(i:i).ge.'a' .and. string(i:i).le.'z') then
    string(i:i)=char(ichar(string(i:i))+ibig-ismall)
  endif
enddo
return
end
!
!-----------------------------------------------------------------------
!
function uppercase(string)
!
! Converts string to uppercase
!
!     From nhad9903 - Miranda 1998
!
character (len=*) string
character(20) :: uppercase
integer :: i,ismall,ibig

uppercase=string
ismall=ichar('a')
ibig=ichar('A')
do i=1,len(string)
  if(string(i:i).ge.'a' .and. string(i:i).le.'z') then
    uppercase(i:i)=char(ichar(string(i:i))+ibig-ismall)
  endif
enddo
return
end
!

program read_wrfout
!
! RCM_fx_landCoverFrac — landCoverFrac, percentage of the grid cell covered by each land-use
! category (fx, %, lon x lat x vegtype): LANDUSEF (wrfvar of the header) of the first
! wrfout file of the job year, every category of the file; the string coordinate vegtype
! names the categories of its land-use table (MODIS or USGS, with the LCZ urban classes).
! No sea mask (the water categories are included). An existing fx file is kept.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

logical :: lu_exists

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

outfile=trim(dir_out)//trim(vaid)//trim(outdom)//'fx.nc'
inquire(file=trim(outfile), exist=lu_exists)
if (lu_exists) then
  print *, trim(outfile), ' already exists: kept (fixed field)'
  stop
endif


! --- First wrfout file of the job year
write(ayear, '(i4)') yeari
amonth = pad_int(imonth, 2)
aday = pad_int(iday, 2)
ahour = pad_int(ihour, 2)
infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'

! --- All the categories of LANDUSEF, in % of the grid cell
call landcover_all(infile)

call write_output

contains
!
!----------------------------------------------------------------------------------------------------
!
subroutine landcover_all(lc_file)
! lc_frac(:,:,k) = 100 LANDUSEF(k) for every category k of the file, rounded to 1e-4 %, and
! lc_names(k), the name of k in the land-use table of the MMINLU attribute (MODIS or USGS,
! with the LCZ urban classes 51-61 or 31-41 when the file has them). No sea mask.
use datvar_s
use netcdf
character(len=*), intent(in) :: lc_file
!
status = nf90_open(trim(lc_file), nf90_nowrite, ncid)
call ncerror(status,'opening '//trim(lc_file))
lc_scheme = ''
status = nf90_get_att(ncid, nf90_global, 'MMINLU', lc_scheme)
lc_modis = (index(lc_scheme, 'USGS') == 0)
status = nf90_inq_varid(ncid, wrfvar, varid)
call ncerror(status,'getting var id '//trim(wrfvar)//' in '//trim(lc_file))
status = nf90_inq_dimid(ncid, 'land_cat_stag', lc_dimid)
if (status /= nf90_noerr) status = nf90_inq_dimid(ncid, 'land_cat', lc_dimid)
call ncerror(status,'getting the land_cat dimension in '//trim(lc_file))
status = nf90_inquire_dimension(ncid, lc_dimid, len=lc_ncat)
call ncerror(status,'reading the land_cat dimension from '//trim(lc_file))
allocate(lc_frac(nlon,nlat,lc_ncat), lc_names(lc_ncat))
status = nf90_get_var(ncid, varid, lc_frac, (/xoffset,yoffset,1,1/), (/nlon,nlat,lc_ncat,1/))
call ncerror(status,'reading '//trim(wrfvar)//' from '//trim(lc_file))
status = nf90_close(ncid)
call ncerror(status,'closing '//trim(lc_file))
!
lc_frac = real(nint(1.d6 * lc_frac, 8)) / 1.e4          ! fraction -> %, rounded to 1e-4 %
!
if (lc_modis) then
  lc_lcz1 = 51; lc_nnamed = 21
else
  lc_lcz1 = 31; lc_nnamed = 24
endif
do k = 1, lc_ncat
  if (k <= lc_nnamed) then
    if (lc_modis) then
      lc_names(k) = lc_md_names(k)
    else
      lc_names(k) = lc_us_names(k)
    endif
  else if (k >= lc_lcz1 .and. k <= lc_lcz1 + 10) then
    write(lc_names(k), '(a,i0)') 'urban local climate zone ', k - lc_lcz1 + 1
  else
    write(lc_names(k), '(a,i0,a)') 'category ', k, ' (unused)'
  endif
enddo
write(*,*) trim(wrfvar), ': ', lc_ncat, ' categories, land-use table ', trim(lc_scheme)
!
end subroutine landcover_all
!
!----------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_subs
use netcdf

freq='fx'
frequency=trim(adjustl(freq))

fnameout=trim(adjustl(outfile))

call date_and_time(date,times,zone,values)
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
call write_netcdf_fx_cat(lc_frac)

deallocate(lc_frac, lc_names)

end subroutine write_output


end program read_wrfout

program read_wrfout
!
! RCM_sfc_mrsofc — Capacity of Soil to Store Water (Field Capacity), mrsofc (fx, kg m-2):
!
!   mrsofc = 1000 kg m-3 x REFSMC(soil category) x total depth of the soil layers
!
! REFSMC: field capacity (m3 m-3) of each soil category, from the STAS table of
! SOILPARM.TBL (the one Noah-MP uses; WRF run of FPS-URB-RCC). Soil category: the
! dominant top-soil category SCT_DOM of the geo_em file (what real.exe gives
! Noah-MP as ISLTYP). Layers: the 4 Noah-MP layers (sdepth, 0.1+0.3+0.6+1.0 = 2 m),
! as for mrso. Sea points (LANDMASK = 0) and unknown categories are missing.
! In the soil varset (RCM_sfc_VAR), so it is rewritten (identically) every year.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

! REFSMC of the 19 STAS soil categories (SOILPARM.TBL):
!  1 SAND, 2 LOAMY SAND, 3 SANDY LOAM, 4 SILT LOAM, 5 SILT, 6 LOAM, 7 SANDY CLAY LOAM,
!  8 SILTY CLAY LOAM, 9 CLAY LOAM, 10 SANDY CLAY, 11 SILTY CLAY, 12 CLAY, 13 ORGANIC MATERIAL,
! 14 WATER, 15 BEDROCK, 16 OTHER(land-ice), 17 PLAYA, 18 LAVA, 19 WHITE SAND
real, dimension(19), parameter :: fc_refsmc = [0.192, 0.283, 0.312, 0.360, 0.347, 0.329, 0.315, &
                                               0.387, 0.382, 0.338, 0.404, 0.412, 0.329, &
                                               0.0, 0.17, 0.283, 0.454, 0.17, 0.192]
integer :: fc_cat

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude, LANDMASK) ---

call read_geog

allocate(wrfv2D(nlon,nlat))
allocate(outvar(nlon,nlat))

! Re-open the geog file to read the soil category (wrfvar = SCT_DOM)
gfile = trim(dir_in)//trim(geog)//'.nc'
geofile = gfile(1:len_trim(gfile))

status = nf90_open(geofile, nf90_nowrite, ncid)
call ncerror(status, 'opening ' // trim(geofile))

status=nf90_inq_varid(ncid,wrfvar,varid)
call ncerror(status,'getting var id')
!
status=nf90_get_var(ncid,varid,wrfv2D,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
call ncerror(status,'reading '//wrfvar)
!
status=nf90_close(ncid)
call ncerror(status,'closing file')
!
do ix=1,nlon
  do iy=1,nlat
    fc_cat = nint(wrfv2D(ix,iy))
    if (landmask(ix,iy) > 0. .and. fc_cat >= 1 .and. fc_cat <= 19) then
      outvar(ix,iy) = 1000. * fc_refsmc(fc_cat) * sum(sdepth)
    else
      outvar(ix,iy) = 1.e+20
    endif
  enddo
enddo

call write_output

contains
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

! Create output filename based on metadata
outfile=trim(dir_out)//trim(vaid)//trim(outdom)//'fx.nc'
fnameout=trim(adjustl(outfile))

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
call write_netcdf_2D(outvar)

end subroutine write_output


end program read_wrfout

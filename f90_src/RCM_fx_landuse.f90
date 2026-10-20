program read_wrfout
!
! RCM_fx_landuse — land-cover fractions (fx, % of the grid cell) and the dominant
! land-use category, from LANDUSEF and LU_INDEX of the first wrfout file of the job
! year (so that experiments with land-use change, e.g. LUCAS, use their own maps).
! The variable (vaid in its header) selects what is written:
!
!   treeFrac      % tree cover           (area_type tree)
!   shrubFrac     % shrub cover          (area_type shrubs)
!   grassFrac     % natural grass cover  (area_type natural_grasses)
!   cropFrac      % crop cover           (area_type crops)
!   baresoilFrac  % bare soil            (area_type bare_ground)
!   urbanFrac     % urban                (area_type urban)
!   cnc           % vegetation = tree + shrub + grass + crop
!   luindex       LU_INDEX, dominant land-use category (1)
!
! Each fraction = 100 * sum over categories k of w(k) LANDUSEF(k), with the weight
! tables below (edit them to change the grouping; a mosaic class may be split).
! Water, snow/ice and wetland categories without a group count in none of them.
! The table follows the MMINLU attribute of the wrfout: MODIFIED_IGBP_MODIS_NOAH
! (LCZ urban classes 51-61) or USGS (LCZ 31-41). No sea mask: % of the whole cell.
! An existing fx file is kept (fixed field; the NetCDF writer does not overwrite).
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none

integer, parameter :: lu_max = 61
real, dimension(:,:,:), allocatable :: lu_f
real, dimension(lu_max) :: lu_w
integer :: lu_ncat, lu_dimid, k
character(len=80) :: lu_scheme
logical :: lu_exists, lu_modis
!
! weights per category, MODIFIED_IGBP_MODIS_NOAH:
!  1 evergreen needleleaf  2 evergreen broadleaf  3 deciduous needleleaf  4 deciduous broadleaf
!  5 mixed forest  6 closed shrubland  7 open shrubland  8 woody savanna  9 savanna  10 grassland
! 11 permanent wetland  12 cropland  13 urban  14 cropland/natural vegetation mosaic  15 snow and ice
! 16 barren  17 water  18 wooded tundra  19 mixed tundra  20 barren tundra  21 lakes  51-61 LCZ (urban)
integer, dimension(21), parameter :: &
  md_tree  = [1,1,1,1,1, 0,0,1,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_shrub = [0,0,0,0,0, 1,1,0,0,0, 0,0,0,0,0, 0,0,1,0,0, 0], &
  md_grass = [0,0,0,0,0, 0,0,0,1,1, 1,0,0,0,0, 0,0,0,1,0, 0], &
  md_crop  = [0,0,0,0,0, 0,0,0,0,0, 0,1,0,1,0, 0,0,0,0,0, 0], &
  md_bare  = [0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 1,0,0,0,1, 0], &
  md_urban = [0,0,0,0,0, 0,0,0,0,0, 0,0,1,0,0, 0,0,0,0,0, 0]
!
! weights per category, USGS:
!  1 urban  2 dryland crop  3 irrigated crop  4 mixed dry/irrigated crop  5 crop/grassland mosaic
!  6 crop/woodland mosaic  7 grassland  8 shrubland  9 mixed shrub/grassland  10 savanna
! 11-14 forests  15 mixed forest  16 water  17 herbaceous wetland  18 wooded wetland  19 barren
! 20 herbaceous tundra  21 wooded tundra  22 mixed tundra  23 bare ground tundra  24 snow or ice
! 31-41 LCZ (urban)
real, dimension(24), parameter :: &
  us_tree  = [0.,0.,0.,0.,0., .5,0.,0.,0.,0., 1.,1.,1.,1.,1., 0.,0.,1.,0.,0., 0.,0.,0.,0.], &
  us_shrub = [0.,0.,0.,0.,0., 0.,0.,1.,.5,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 1.,1.,0.,0.], &
  us_grass = [0.,0.,0.,0.,.5, 0.,1.,0.,.5,1., 0.,0.,0.,0.,0., 0.,1.,0.,0.,1., 0.,0.,0.,0.], &
  us_crop  = [0.,1.,1.,1.,.5, .5,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_bare  = [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,1.,0., 0.,0.,1.,0.], &
  us_urban = [1.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.]

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

allocate(wrfv2D(nlon,nlat))
allocate(outvar(nlon,nlat))

! --- First wrfout file of the job year
write(ayear, '(i4)') yeari
amonth = pad_int(imonth, 2)
aday = pad_int(iday, 2)
ahour = pad_int(ihour, 2)
infile = trim(dir_in)//trim(wrfile)//'_d0'//trim(dom)//'_'//ayear//'-'//amonth//'-'//aday//'_'//ahour//'_00_00'
write(*,*) trim(vaid), ' from ', trim(infile)

status = nf90_open(infile, nf90_nowrite, ncid)
call ncerror(status,'opening '//trim(infile))

if (trim(vaid) == 'luindex') then
  status=nf90_inq_varid(ncid,'LU_INDEX',varid)
  call ncerror(status,'getting var id LU_INDEX')
  status=nf90_get_var(ncid,varid,wrfv2D,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
  call ncerror(status,'reading LU_INDEX')
  outvar = real(nint(wrfv2D))
else
  lu_scheme = ''
  status = nf90_get_att(ncid, nf90_global, 'MMINLU', lu_scheme)
  lu_modis = (index(lu_scheme, 'USGS') == 0)
  if (status /= nf90_noerr) then
    print *, 'MMINLU not found: MODIFIED_IGBP_MODIS_NOAH assumed'
  else
    print *, 'land-use table: ', trim(lu_scheme)
  endif
!
  status=nf90_inq_varid(ncid,'LANDUSEF',varid)
  call ncerror(status,'getting var id LANDUSEF')
  status=nf90_inq_dimid(ncid,'land_cat_stag',lu_dimid)
  if (status /= nf90_noerr) status=nf90_inq_dimid(ncid,'land_cat',lu_dimid)
  call ncerror(status,'getting the land_cat dimension')
  status=nf90_inquire_dimension(ncid,lu_dimid,len=lu_ncat)
  call ncerror(status,'reading the land_cat dimension')
  allocate(lu_f(nlon,nlat,lu_ncat))
  status=nf90_get_var(ncid,varid,lu_f,(/xoffset,yoffset,1,1/),(/nlon,nlat,lu_ncat,1/),(/1,1,1,1/))
  call ncerror(status,'reading LANDUSEF')
!
  call set_weights
  outvar = 0.
  do k = 1, min(lu_ncat, lu_max)
    if (lu_w(k) > 0.) outvar = outvar + lu_w(k) * lu_f(:,:,k)
  enddo
  outvar = 100. * outvar
  where (outvar > 100.) outvar = 100.
  where (outvar < 1.e-4) outvar = 0.
  outvar = real(nint(1.d4 * outvar, 8)) / 1.e4
endif

status = nf90_close(ncid)
call ncerror(status,'closing file')

call write_output

contains
!
!----------------------------------------------------------------------------------------------------
!
subroutine set_weights
! weights lu_w(k) of the category k for the group of vaid
real, dimension(24) :: g
integer :: lcz1
!
lu_w = 0.
g = 0.
if (lu_modis) then
  lcz1 = 51
  select case (trim(vaid))
    case ('treeFrac');     g(1:21) = md_tree
    case ('shrubFrac');    g(1:21) = md_shrub
    case ('grassFrac');    g(1:21) = md_grass
    case ('cropFrac');     g(1:21) = md_crop
    case ('baresoilFrac'); g(1:21) = md_bare
    case ('urbanFrac');    g(1:21) = md_urban
    case ('cnc');          g(1:21) = md_tree + md_shrub + md_grass + md_crop
    case default; call unknown
  end select
  lu_w(1:21) = g(1:21)
else
  lcz1 = 31
  select case (trim(vaid))
    case ('treeFrac');     g = us_tree
    case ('shrubFrac');    g = us_shrub
    case ('grassFrac');    g = us_grass
    case ('cropFrac');     g = us_crop
    case ('baresoilFrac'); g = us_bare
    case ('urbanFrac');    g = us_urban
    case ('cnc');          g = us_tree + us_shrub + us_grass + us_crop
    case default; call unknown
  end select
  lu_w(1:24) = g
endif
! LCZ urban classes (11 of them), when the file has them
if (trim(vaid) == 'urbanFrac') lu_w(lcz1:lcz1+10) = 1.
!
end subroutine set_weights
!
subroutine unknown
print *, 'ERROR: RCM_fx_landuse does not know the variable ', trim(vaid)
stop 95
end subroutine unknown
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
call write_netcdf_2D(outvar)

deallocate(outvar)

end subroutine write_output


end program read_wrfout

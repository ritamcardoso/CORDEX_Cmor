module landuse_subs
!
! Land use and urban cells: urban_cell (where WRF runs the urban scheme, from FRC_URB2D,
! LU_INDEX and the land-use table read by read_geog) and landuse_field (land-cover fractions
! and the dominant category from LANDUSEF / LU_INDEX of a wrfout file). Used by the land-use
! (RCM_fx_landuse, RCM_sfc_landuse, RCM_sfc_albc) and urban (RCM_sfc_urb, RCM_sfc_hurscan,
! RCM_sfc_husscan, RCM_sfc_sfcWindcan) programs (use landuse_subs). read_geog, which reads
! LU_INDEX, MMINLU and FRC_URB2D from the geo_em file, stays in shared_io_subs.f90.
! Compiled after shared_io_subs (it uses ncerror; scripts/run_out_generic.sh).
!
use datvar_s
use shared_io_subs, only: ncerror
use netcdf
!
contains
!
logical elemental function urban_cell(frc, lu)
! .true. where WRF runs the urban scheme: urban fraction > 0 and the dominant land-use
! category (LU_INDEX) urban, for the land-use table of the geo_em file (read_geog):
!   MODIFIED_IGBP_MODIS_NOAH: 13, or the LCZ classes 51-61
!   USGS:                      1, or the LCZ classes 31-41
real, intent(in) :: frc, lu
integer :: k
k = nint(lu)
if (lu_usgs) then
  urban_cell = frc > 0. .and. (k == 1 .or. (k >= 31 .and. k <= 41))
else
  urban_cell = frc > 0. .and. (k == 13 .or. (k >= 51 .and. k <= 61))
endif
end function urban_cell
!
!-----------------------------------------------------------------------
!
subroutine landuse_field(fname, lu_out)
! Land-cover fraction (% of the grid cell) or dominant category of the variable vaid,
! from LANDUSEF / LU_INDEX of the wrfout file fname (RCM_fx_landuse, RCM_sfc_landuse):
!   treeFrac, shrubFrac, grassFrac, cropFrac, baresoilFrac, urbanFrac: 100 * sum over
!   the categories k of w(k) LANDUSEF(k), with the weight tables below (edit them to
!   change the grouping; a mosaic class may be split); cnc: tree+shrub+grass+crop (also
!   for albc, the canopy albedo of RCM_sfc_albc);
!   treeFracBdlDcd, treeFracBdlEvg, treeFracNdlDcd, treeFracNdlEvg: the pure forest
!   classes of each leaf type and phenology (mixed forest and the mosaics in none);
!   residualFrac: land neither vegetated nor bare (urban, incl. LCZ, and snow/ice);
!   pastureFrac: the grassland class (MODIS 10, USGS 7), taken as pasture (the tables have
!   no pasture class; it is also part of grassFrac);
!   lcvr: LU_INDEX. Water, snow/ice and ungrouped wetland count in none of the others.
! The table follows the MMINLU attribute of the file: MODIFIED_IGBP_MODIS_NOAH
! (LCZ urban classes 51-61) or USGS (LCZ 31-41). No sea mask.
use netcdf
character(len=*), intent(in) :: fname
real, dimension(nlon,nlat), intent(out) :: lu_out
integer, parameter :: lu_max = 61
real, dimension(:,:), allocatable :: lu_f
real, dimension(lu_max) :: lu_w
real, dimension(24) :: g
integer :: lu_ncat, lu_dimid, k, lu_ncid, lu_varid, lu_st, lcz1
character(len=80) :: lu_scheme
logical :: lu_modis
logical, save :: lu_told = .false.
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
  md_urban = [0,0,0,0,0, 0,0,0,0,0, 0,0,1,0,0, 0,0,0,0,0, 0], &
  md_ndlevg= [1,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_bdlevg= [0,1,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_ndldcd= [0,0,1,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_bdldcd= [0,0,0,1,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0], &
  md_resid = [0,0,0,0,0, 0,0,0,0,0, 0,0,1,0,1, 0,0,0,0,0, 0], &
  md_past  = [0,0,0,0,0, 0,0,0,0,1, 0,0,0,0,0, 0,0,0,0,0, 0]
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
  us_urban = [1.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_bdldcd= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 1.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_ndldcd= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,1.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_bdlevg= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,1.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_ndlevg= [0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,1.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.], &
  us_resid = [1.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,1.], &
  us_past  = [0.,0.,0.,0.,0., 0.,1.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.,0., 0.,0.,0.,0.]
!
lu_st = nf90_open(trim(fname), nf90_nowrite, lu_ncid)
call ncerror(lu_st,'opening '//trim(fname))
!
if (trim(vaid) == 'lcvr') then
  lu_st=nf90_inq_varid(lu_ncid,'LU_INDEX',lu_varid)
  call ncerror(lu_st,'getting var id LU_INDEX in '//trim(fname))
  lu_st=nf90_get_var(lu_ncid,lu_varid,lu_out,(/xoffset,yoffset,1/),(/nlon,nlat,1/),(/1,1,1/))
  call ncerror(lu_st,'reading LU_INDEX from '//trim(fname))
  lu_out = real(nint(lu_out))
else
  lu_scheme = ''
  lu_st = nf90_get_att(lu_ncid, nf90_global, 'MMINLU', lu_scheme)
  lu_modis = (index(lu_scheme, 'USGS') == 0)
  if (lu_st /= nf90_noerr) lu_scheme = 'MODIFIED_IGBP_MODIS_NOAH (no MMINLU attribute: assumed)'
!
  lu_st=nf90_inq_varid(lu_ncid,'LANDUSEF',lu_varid)
  call ncerror(lu_st,'getting var id LANDUSEF in '//trim(fname))
  lu_st=nf90_inq_dimid(lu_ncid,'land_cat_stag',lu_dimid)
  if (lu_st /= nf90_noerr) lu_st=nf90_inq_dimid(lu_ncid,'land_cat',lu_dimid)
  call ncerror(lu_st,'getting the land_cat dimension in '//trim(fname))
  lu_st=nf90_inquire_dimension(lu_ncid,lu_dimid,len=lu_ncat)
  call ncerror(lu_st,'reading the land_cat dimension from '//trim(fname))
!
! weights lu_w(k) of the category k for the group of vaid
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
      case ('cnc', 'albc');  g(1:21) = md_tree + md_shrub + md_grass + md_crop
      case ('treeFracBdlDcd'); g(1:21) = md_bdldcd
      case ('treeFracBdlEvg'); g(1:21) = md_bdlevg
      case ('treeFracNdlDcd'); g(1:21) = md_ndldcd
      case ('treeFracNdlEvg'); g(1:21) = md_ndlevg
      case ('residualFrac');   g(1:21) = md_resid
      case ('pastureFrac');    g(1:21) = md_past
      case default
        print *, 'ERROR: landuse_field does not know the variable ', trim(vaid)
        stop 95
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
      case ('cnc', 'albc');  g = us_tree + us_shrub + us_grass + us_crop
      case ('treeFracBdlDcd'); g = us_bdldcd
      case ('treeFracBdlEvg'); g = us_bdlevg
      case ('treeFracNdlDcd'); g = us_ndldcd
      case ('treeFracNdlEvg'); g = us_ndlevg
      case ('residualFrac');   g = us_resid
      case ('pastureFrac');    g = us_past
      case default
        print *, 'ERROR: landuse_field does not know the variable ', trim(vaid)
        stop 95
    end select
    lu_w(1:24) = g
  endif
  ! LCZ urban classes (11 of them), when the file has them
  if (trim(vaid) == 'urbanFrac' .or. trim(vaid) == 'residualFrac') lu_w(lcz1:lcz1+10) = 1.
!
  allocate(lu_f(nlon,nlat))
  lu_out = 0.
  do k = 1, min(lu_ncat, lu_max)
    if (lu_w(k) > 0.) then
      ! only the categories of this group are read (one 2-D slice each)
      lu_st=nf90_get_var(lu_ncid,lu_varid,lu_f,(/xoffset,yoffset,k,1/),(/nlon,nlat,1,1/),(/1,1,1,1/))
      call ncerror(lu_st,'reading LANDUSEF from '//trim(fname))
      lu_out = lu_out + lu_w(k) * lu_f
    endif
  enddo
  lu_out = 100. * lu_out
  where (lu_out > 100.) lu_out = 100.
  where (lu_out < 1.e-4) lu_out = 0.
  lu_out = real(nint(1.d4 * lu_out, 8)) / 1.e4
  deallocate(lu_f)
  if (.not. lu_told) write(*,*) trim(vaid), ' from LANDUSEF, land-use table ', trim(lu_scheme)
  lu_told = .true.
endif
!
lu_st = nf90_close(lu_ncid)
call ncerror(lu_st,'closing '//trim(fname))
!
end subroutine landuse_field
!
!-----------------------------------------------------------------------
!
end module landuse_subs

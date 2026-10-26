module vert_interp_subs
!
! Interpolation to pressure and height levels: plev_map (the model levels bracketing a pressure
! level, carried from one time step to the next) and plev_interp (linear in log p), zlev_heights
! (heights above the ground from PH, PHB and HGT, read only up to the levels needed) and
! zlev_map. Used by the RCM_plev_* and RCM_zlev_* programs (use vert_interp_subs). Their
! variables (plev_k, plev_w, zlev_k ...) are in datvar_s. Compiled after shared_io_subs
! (it uses ncerror; scripts/run_out_generic.sh).
!
use datvar_s
use shared_io_subs, only: ncerror
use netcdf
!
contains
!
subroutine plev_map(pr, pl)
! Map of the model levels that bracket the pressure level pl (Pa): plev_k(ix,iy) = k
! with pr(k) >= pl > pr(k+1), and the log(p) weight plev_w of level k+1, used by
! plev_interp. Pressure is smooth in the horizontal, so the level of the previous point
! (the point to the west; at the start of a row, the first point of the row below) is
! the first guess, and the search walks from it: down (k-1) while pr(k) < pl, up (k+1)
! while pr(k+1) >= pl - usually 0 to 2 steps. Points where pl is below the surface
! (pr(1) < pl) or above the model top (pr(nz) >= pl) get plev_k = 0 (missing).
! If the walk does not end within nz steps (non-monotonic column), the column is
! scanned from the bottom, as the earlier RCM_plev programs did.
! The map is kept for the next call (the next time step): the search of the first point
! starts from its level of the previous time step (else from the last level found then).
! plev_k1..plev_k2 (plev_nk levels) are the model levels plev_interp needs, k and k+1 of
! every point: the programs read and compute their fields only on these levels.
use datvar_s
real, dimension(nlon,nlat,nz), intent(in) :: pr
real, intent(in) :: pl
integer :: pm_i, pm_j, pm_k
!
if (.not. allocated(plev_k)) then
  allocate(plev_k(nlon,nlat), plev_w(nlon,nlat))
  plev_k = 0
  plev_kg = 1
endif
! first guess of the first point: its level of the previous time step
if (plev_k(1,1) > 0) plev_kg = plev_k(1,1)
plev_k = 0
plev_w = 0.
plev_steps = 0
plev_scan = 0
do pm_j = 1, nlat
  if (pm_j > 1) then
    if (plev_k(1,pm_j-1) > 0) plev_kg = plev_k(1,pm_j-1)
  endif
  do pm_i = 1, nlon
    if (pr(pm_i,pm_j,1) < pl .or. pr(pm_i,pm_j,nz) >= pl) cycle      ! below ground / above top
    pm_k = max(1, min(nz-1, plev_kg))
    walk: do plev_it = 1, nz
      if (pr(pm_i,pm_j,pm_k) < pl) then
        pm_k = pm_k - 1
      else if (pr(pm_i,pm_j,pm_k+1) >= pl) then
        pm_k = pm_k + 1
      else
        exit walk
      endif
      plev_steps = plev_steps + 1
      if (pm_k < 1 .or. pm_k > nz-1) exit walk
    enddo walk
    if (pm_k < 1 .or. pm_k > nz-1 .or. plev_it > nz) then
      ! not monotonic: first bracket from the bottom
      plev_scan = plev_scan + 1
      pm_k = 0
      do plev_it = 1, nz-1
        if (pr(pm_i,pm_j,plev_it) >= pl .and. pr(pm_i,pm_j,plev_it+1) < pl) then
          pm_k = plev_it
          exit
        endif
      enddo
      if (pm_k == 0) cycle
    endif
    plev_k(pm_i,pm_j) = pm_k
    plev_w(pm_i,pm_j) = (log(pr(pm_i,pm_j,pm_k)) - log(pl)) / (log(pr(pm_i,pm_j,pm_k)) - log(pr(pm_i,pm_j,pm_k+1)))
    plev_kg = pm_k
  enddo
enddo
! the levels plev_interp needs (1 level if pl is below the ground or above the top everywhere)
if (any(plev_k > 0)) then
  plev_k1 = minval(plev_k, mask = plev_k > 0)
  plev_k2 = maxval(plev_k) + 1
else
  plev_k1 = 1
  plev_k2 = 1
endif
plev_nk = plev_k2 - plev_k1 + 1
!
end subroutine plev_map
!
!-----------------------------------------------------------------------
!
subroutine zlev_map(zh, hl, kz)
! Map of the model levels that bracket the height hl (m above the ground): zlev_k(ix,iy) = k
! with zh(k) < hl <= zh(k+1), zh the height of the mass levels above the ground (from PH,
! PHB and HGT). zlev_k = 0 (missing) where hl is not above the lowest model level
! (zh(1) >= hl) or is above the top (zh(nz) < hl): the same brackets as the search from the
! bottom of the earlier RCM_zlev programs, which the programs use with their own
! interpolation (linear in z, or the power law of the winds).
! Height is smooth in the horizontal, so the level of the previous point (the point to the
! west; at the start of a row, the first point of the row below) is the first guess, and
! the search walks from it: down (k-1) while zh(k) >= hl, up (k+1) while zh(k+1) < hl.
! If the walk does not end within nz steps (non-monotonic column), the column is searched
! from the bottom as before. The map is kept for the next call (the next time step): the
! search of the first point starts from its level of the previous time step.
! zlev_k1..zlev_k2 (zlev_nk levels) are the model levels the interpolation needs, k and k+1
! of every point: the programs read and compute their fields only on these levels.
! kz (optional, default nz): zh is known on the levels 1..kz only (kz <= nz; zlev_heights),
! and kz takes the place of nz as the top of the column.
use datvar_s
real, dimension(nlon,nlat,nz), intent(in) :: zh
real, intent(in) :: hl
integer, intent(in), optional :: kz
integer :: zm_i, zm_j, zm_k, zm_kz
!
zm_kz = nz
if (present(kz)) zm_kz = kz
if (.not. allocated(zlev_k)) then
  allocate(zlev_k(nlon,nlat))
  zlev_k = 0
  zlev_kg = 1
endif
! first guess of the first point: its level of the previous time step
if (zlev_k(1,1) > 0) zlev_kg = zlev_k(1,1)
zlev_k = 0
zlev_steps = 0
zlev_scan = 0
do zm_j = 1, nlat
  if (zm_j > 1) then
    if (zlev_k(1,zm_j-1) > 0) zlev_kg = zlev_k(1,zm_j-1)
  endif
  do zm_i = 1, nlon
    if (zh(zm_i,zm_j,1) >= hl .or. zh(zm_i,zm_j,zm_kz) < hl) cycle      ! not above level 1 / above the top
    zm_k = max(1, min(zm_kz-1, zlev_kg))
    walk: do zlev_it = 1, nz
      if (zh(zm_i,zm_j,zm_k) >= hl) then
        zm_k = zm_k - 1
      else if (zh(zm_i,zm_j,zm_k+1) < hl) then
        zm_k = zm_k + 1
      else
        exit walk
      endif
      zlev_steps = zlev_steps + 1
      if (zm_k < 1 .or. zm_k > zm_kz-1) exit walk
    enddo walk
    if (zm_k < 1 .or. zm_k > zm_kz-1 .or. zlev_it > nz) then
      ! not monotonic: the search from the bottom of the earlier programs
      zlev_scan = zlev_scan + 1
      zm_k = 0
      do zlev_it = 1, zm_kz-1
        if (zh(zm_i,zm_j,zlev_it) > hl) exit
        if (zh(zm_i,zm_j,zlev_it+1) >= hl .and. zh(zm_i,zm_j,zlev_it) < hl) then
          zm_k = zlev_it
          exit
        endif
      enddo
      if (zm_k == 0) cycle
    endif
    zlev_k(zm_i,zm_j) = zm_k
    zlev_kg = zm_k
  enddo
enddo
! the levels the interpolation needs (1 level if hl is missing everywhere)
if (any(zlev_k > 0)) then
  zlev_k1 = minval(zlev_k, mask = zlev_k > 0)
  zlev_k2 = maxval(zlev_k) + 1
else
  zlev_k1 = 1
  zlev_k2 = 1
endif
zlev_nk = zlev_k2 - zlev_k1 + 1
!
end subroutine zlev_map
!
!-----------------------------------------------------------------------
!
subroutine zlev_heights(hl)
! The heights above the ground of the mass levels, zhgt = (phi(k) + phi(k+1)) / 2 - hgt with
! phi = (PH + PHB) / g, and the map of the levels that bracket the height hl (zlev_map), for
! the open wrfout file (ncid and infile of datvar_s; hgt read by the program).
! After the first time step, PH and PHB are read only up to the face above the mass level
! zlev_kz = zlev_k2 + 1 of the previous step's map (at most nz). If a point that is above
! level 1 might need a higher level (zhgt(zlev_kz) <= hl), they are read again up to nz
! (zlev_nfull counts these steps). The map, and so the results, are then those of a read of
! all nz levels: with zhgt(zlev_kz) > hl, the bracket of every point is below zlev_kz.
use datvar_s
use netcdf
real, intent(in) :: hl
integer :: zh_st, zh_vid
!
if (.not. allocated(ph)) allocate(ph(nlon,nlat,nzt), phb(nlon,nlat,nzt), phi(nlon,nlat,nzt))
if (allocated(zlev_k)) then
  zlev_kz = min(nz, zlev_k2 + 1)
else
  zlev_kz = nz                                  ! first time step: every level
endif
call read_ph(zlev_kz)
if (zlev_kz < nz) then
  if (any(zhgt(:,:,1) < hl .and. zhgt(:,:,zlev_kz) <= hl)) then
    zlev_nfull = zlev_nfull + 1
    if (zlev_nfull <= 3 .or. mod(zlev_nfull, 1000) == 0) &
      write(*,'(a,i0,a,i0,a,i0,a)') ' zlev_heights: PH and PHB read again up to level ', nz, &
        ' (', zlev_kz, ' were not enough; ', zlev_nfull, ' time steps so far)'
    zlev_kz = nz
    call read_ph(zlev_kz)
  endif
endif
call zlev_map(zhgt, hl, zlev_kz)
!
contains
  subroutine read_ph(kk)
  ! PH and PHB on the faces 1..kk+1, and zhgt on the mass levels 1..kk
  integer, intent(in) :: kk
  integer :: zh_k
  zh_st = nf90_inq_varid(ncid, 'PH', zh_vid)
  call ncerror(zh_st,'getting var id PH in '//trim(infile))
  zh_st = nf90_get_var(ncid, zh_vid, ph(:,:,1:kk+1), (/xoffset, yoffset, 1/), (/nlon, nlat, kk+1/))
  call ncerror(zh_st,'reading PH from '//trim(infile))
  zh_st = nf90_inq_varid(ncid, 'PHB', zh_vid)
  call ncerror(zh_st,'getting var id PHB in '//trim(infile))
  zh_st = nf90_get_var(ncid, zh_vid, phb(:,:,1:kk+1), (/xoffset, yoffset, 1/), (/nlon, nlat, kk+1/))
  call ncerror(zh_st,'reading PHB from '//trim(infile))
  phi(:,:,1:kk+1) = (ph(:,:,1:kk+1) + phb(:,:,1:kk+1)) / g
  do zh_k = 1, kk
    zhgt(:, :, zh_k) = ((phi(:, :, zh_k) + phi(:, :, zh_k+1)) / 2.) - hgt(:, :)
  enddo
  end subroutine read_ph
end subroutine zlev_heights
!
!-----------------------------------------------------------------------
!
subroutine plev_interp(f3d, f2d)
! f3d on the model levels -> f2d on the pressure level of the last plev_map, linear in
! log(p): f2d = f3d(k) + plev_w (f3d(k+1) - f3d(k)); missing (1e20) where plev_k = 0
use datvar_s
real, dimension(nlon,nlat,nz), intent(in) :: f3d
real, dimension(nlon,nlat), intent(out) :: f2d
integer :: pm_i, pm_j, pm_k
!
do pm_j = 1, nlat
  do pm_i = 1, nlon
    pm_k = plev_k(pm_i,pm_j)
    if (pm_k > 0) then
      f2d(pm_i,pm_j) = f3d(pm_i,pm_j,pm_k) + plev_w(pm_i,pm_j) * (f3d(pm_i,pm_j,pm_k+1) - f3d(pm_i,pm_j,pm_k))
    else
      f2d(pm_i,pm_j) = 1.e+20
    endif
  enddo
enddo
!
end subroutine plev_interp
!
!-----------------------------------------------------------------------
!
end module vert_interp_subs

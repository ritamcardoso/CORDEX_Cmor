# f90_src/deprecated

The earlier pressure-level programs (`RCM_plev_*.f90`), kept for reference. They are no longer built by the scripts, which compile from `f90_src`.

Each column was searched on its own, from the bottom for levels at or below 500 hPa and from the top above 500 hPa.

The programs in `f90_src` build a map of the model levels that bracket the pressure level instead (`plev_map` and `plev_interp` in `shared_subs_v2.f90`):
- The search for each point starts from the level found at its neighbour, because pressure varies smoothly in the horizontal.
- One map is used for every field interpolated to that level.

The interpolation in log(p) is unchanged.

`RCM_sfc_cape.f90` is the earlier CAPE program. It also wrote `lcl`, read HGT every hour for it, and lifted the parcel only up to 100 hPa. The CAPE program in `f90_src` writes cape, cin and li and lifts the parcel to the model top; `lcl` is now written by `RCM_sfc_lcl.f90`. The OpenMP copy of the earlier program is in `f90_src_parallel/deprecated`.

Programs that wrote some variables more often than CORDEX-CMIP6 or FPS-LUCAS request (1hr): `RCM_sfc_snw`, `snd`, `snc`, `mrfso`, `snm`, `siconca`, `alb`, `albc`, `cVeg`, `lai`, `npp`, `rough`, `rad`, `cloud`, `clouds`, `mrro`, `mrros`, `mrso`. The programs in `f90_src` write at the step set in the variable's header (`outstep`, in hours: 1, 3, 6, 24, or 0 for `wp_step`). The pressure-level and soil-layer programs read the files every `outstep` hours instead of every `wp_step` hours. The OpenMP copies of the earlier `cloud` and `clouds` are in `f90_src_parallel/deprecated`.

`RCM_sfc_evspsblpot.f90` (potential evapotranspiration) used the FAO-56 Tetens formula for es and its slope; the earlier version is kept here. The program in `f90_src` uses the saturation vapour pressure of hurs and cape (`es_wexler_dt`).

`RCM_sfc_hurs.f90` and `RCM_sfc_hurscan.f90` computed es inline. The enhancement factor had the second term as b (es/P − 1) instead of Hardy's (1998) b (P/es − 1), giving f ≈ 1.0010 instead of ≈ 1.0039 at 20 °C and 1000 hPa, so RH was about 0.3 % (relative) too high. The copies kept here have the term corrected. The programs in `f90_src` call `es_wexler_dt` (shared_subs_v2.f90), which had the same error and is also corrected (it is used by cape and evspsblpot too).

`plev_fullread/`: the pressure-level programs with the level map (`plev_map`, `plev_interp`) that read every model level (`nz`) of the fields they interpolate (T, QVAPOR, U, V, W, PH, PHB). In them, a pressure level between the surface and the lowest model level was missing.

The programs in `f90_src` use `plev_map_s` and `plev_interp_s` instead:
- The surface is level 0 (`press(:,:,0)` = PSFC). A level between the surface and level 1 is interpolated between the surface value of the variable (T2, Q2, U10/V10 …) and level 1; a level below the surface (−1 in the map) is missing, with no interpolation.
- The map is built first, from P, PB and PSFC, and the fields are read and computed only on the levels it uses (`plev_k1`..`plev_k2`).
- The map is carried to the next time step: the search of the first point starts from its previous level.

At the points between model levels the results are identical. The variable-calendar versions of these copies are in `f90_src_varcalendar/deprecated/plev_fullread`.

# f90_src/deprecated

The earlier pressure-level programs (`RCM_plev_*.f90`), kept for reference. They are no longer built by the scripts, which compile from `f90_src`.

Each column was searched on its own, from the bottom for levels at or below 500 hPa and from the top above 500 hPa.

The programs in `f90_src` build a map of the model levels that bracket the pressure level instead (`plev_map` and `plev_interp` in `shared_subs_v2.f90`):
- The search for each point starts from the level found at its neighbour, because pressure varies smoothly in the horizontal.
- One map is used for every field interpolated to that level.

The interpolation in log(p) is unchanged.

`RCM_sfc_cape.f90` is the earlier CAPE program. It also wrote `lcl`, read HGT every hour for it, and lifted the parcel only up to 100 hPa. The CAPE program in `f90_src` writes cape, cin and li and lifts the parcel to the model top; `lcl` is now written by `RCM_sfc_lcl.f90`. The OpenMP copy of the earlier program is in `f90_src_parallel/deprecated`.

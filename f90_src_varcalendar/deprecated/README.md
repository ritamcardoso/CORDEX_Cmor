# f90_src_varcalendar/deprecated

Earlier variable-calendar versions, kept for reference; the scripts do not build them. `tools/make_varcalendar.py` does not read or change this folder.

`plev_fullread/`: the pressure-level programs that read every model level of the fields they interpolate. See `f90_src/deprecated/README.md`.

`RCM_zlev_*.f90`: the height-level programs that searched each column from the bottom and read every model level of the fields. The programs in `f90_src_varcalendar` build a map of the bracketing levels first (`zlev_map`, from PH, PHB and HGT), carry it to the next time step, and read and compute the fields only on the levels it uses. The results are identical, except that the wind programs (ua, va, uava) now use 20 levels, like hus and ta, instead of 15 and 14.

`zlev_fullph/`: the height-level programs that read PH and PHB on all 20 levels at every time step. See `f90_src/deprecated/README.md`.

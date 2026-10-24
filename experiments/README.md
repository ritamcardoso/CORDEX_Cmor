# `experiments`

One folder per experiment. The folder name is the experiment name, and it's what `EXPERIMENT` in `env.site.sh` selects (see the main [README.md](../README.md), §2). Each folder holds everything for that experiment:

```
experiments/<name>/
  <name>.sh                              <- grids to process and, per grid, WRF input / output / archive paths
  <name>_<DOMAIN_ID>_<grid>.ini          <- grid/domain setup        (one per grid)
  <name>_global_<DOMAIN_ID>_<grid>.ini   <- global attributes        (one per grid)
```

e.g. `experiments/fpsurb/` has `fpsurb.sh`, `fpsurb_EUR-12_d01.ini`, `fpsurb_global_EUR-12_d01.ini`, `fpsurb_PARIS-3_d02.ini` and `fpsurb_global_PARIS-3_d02.ini`.

To add an experiment, copy an existing folder, rename the folder and the files inside to the new name, and fill them in. Under normal circumstances you only set these files up once.

The settings in `<name>.sh` are described in the main README, §2. The rest of this page covers the two ini files each grid needs, both read by every `RCM_*` Fortran program via `run_out_generic.sh`.

In both file names:

- **`<name>`** — the experiment name, the same as its folder; e.g. `cordex` for standard CORDEX-CMIP6 runs, `fpsurb` for FPS-URB-RCC runs.
- **`<DOMAIN_ID>`** — the CORDEX domain identifier for that grid, from `DOMAIN_ID[]` in `<name>.sh` (e.g. `EUR-12`, `PARIS-3`). It can differ per grid within one experiment: fpsurb is `EUR-12` on `d01` and `PARIS-3` on `d02`.
- **`<grid>`** — a key in `run[]` in `<name>.sh` (e.g. `d01`, `d02`).

## `<name>_<DOMAIN_ID>_<grid>.ini` — grid/domain setup

The `&cordex_config` namelist. Set:

- **Domain & geography** — the grid dimensions (`nz`/`nlon`/`nlat`/`xoffset`/`yoffset`) and the matching `geog` name.
- **Naming conventions** — `dom`/`outdom`, the domain and model names used in the CMORised output filenames.
- **Sub-daily step** — `wp_step` (default 6): output step, in hours, of the variables whose header has `outstep = 0`. These are the variables that CORDEX-CMIP6 and FPS-LUCAS request at different frequencies: mrso, mrro, mrros, mrsol and tsl (CORDEX 6hr, LUCAS 1hr). So `wp_step = 6` for CORDEX and `wp_step = 1` for LUCAS. It must divide 24. Every other variable has its output step in its header (`outstep` = 1, 3, 6 or 24 hours).
- **Simulation period (optional)** — `sim_start` and `sim_end`, `'YYYY-MM-DD_HH'` (UTC): the first and the last wrfout file of the simulation. Set both explicitly, or neither. If they are set, the programs are built from [`f90_src_varcalendar`](../f90_src_varcalendar/README.md) and write only the time steps inside the period, which may start and end at any hour (e.g. `sim_end = '2100-12-31_18'`) and last from a few hours to many years. A day, 6 hours or month that is not complete in the period is not written. `imonth`, `iday`, `ihour` and `nmonths` are then not used, and `run_out_generic.sh` limits the years of each job (and of the chain) to the years of the period. Without them, the programs of `f90_src` process whole calendar years. Each ini has the two lines commented out, as an example.
- **Map projection** — `projection`, the CF name of the output grid's projection, plus its parameters. It sets the 1-D coordinates and the grid-mapping variable (named after the projection) in every output file; the job stops if it is missing.

  | `projection` | Parameters | Written to the files |
  |---|---|---|
  | `'rotated_latitude_longitude'` | `pole_lat`, `pole_lon` (required) | `rlon`/`rlat` (degrees), `grid_north_pole_latitude`/`_longitude` |
  | `'lambert_conformal_conic'` | `truelat1`, `truelat2`, `stand_lon`, `cen_lat`, optional `false_easting`/`false_northing` (m, default 0) | `x`/`y` (m), `standard_parallel`, `longitude_of_central_meridian`, `latitude_of_projection_origin` |

  For Lambert, any of `truelat1`, `truelat2`, `stand_lon`, `cen_lat` left out is read from the geo_em file (WRF's `TRUELAT1`, `TRUELAT2`, `STAND_LON`, `MOAD_CEN_LAT`), so `projection = 'lambert_conformal_conic'` alone is usually enough. Both write `lon`/`lat` and `earth_radius` (6370000 m, WRF's sphere). Keep the global ini's `grid` description consistent with it.

Leave these placeholders as they are — `run_out_generic.sh` fills them in for each job:

- **`_START_YY_` / `_END_YY_`** — the year being processed.
- **`dir_in` / `dir_out`** — `_OUTPUT_WRF_` / `_OUTPUT_DIR_`, from that grid's `OUTPUT_WRF[<grid>]` / `OUTPUT_DIR[<grid>]` in `<name>.sh` (a trailing `/` is added automatically). Don't hardcode real paths here — edit `<name>.sh` instead. Each grid's output must go to its own directory.
- **`wrffile`** — `_WRFFILE_`: `wrfxtrm` for the `wxtrm` (and `testex`) varset, which runs `RCM_sfc_xtrm`; `wrfout` for every other varset.

## `<name>_global_<DOMAIN_ID>_<grid>.ini` — global attributes

The `&global_metadata` namelist: global (file-level) CF/CMOR attributes written into every output NetCDF file (institution, driving experiment, domain ID, and so on).

**The values must come from the official CORDEX-CMIP6 controlled vocabulary, not be made up per experiment:**

- **[WCRP-CORDEX/cordex-cmip6-cv](https://github.com/WCRP-CORDEX/cordex-cmip6-cv)**
  — the controlled vocabulary (CV) for CORDEX-CMIP6: valid domain IDs,
  institution IDs, driving-model/experiment IDs, and the other global
  attributes CMOR compliance depends on. Any global attribute here that
  identifies your experiment (domain, institution, driving model,
  experiment, ...) should be checked against this CV before a real run —
  using a value that isn't in it will produce output that isn't
  CORDEX-CMIP6 compliant even if it runs successfully.

**Written automatically, not set in the ini** (by `write_global_attributes` in `f90_src/shared_subs_v2.f90`):

- `creation_date` — the time the file is written, in UTC (`YYYY-MM-DDThh:mm:ssZ`).
- `tracking_id` — `hdl:21.14103/<UUID>`, a new random UUID (version 4) for every file, so there is no need to add it afterwards with cdo.
- `history` — `<creation time>;rewrote data to be consistent with <activity_id> for variable <variable> found in table CORDEX-CMIP6_<frequency>.` (activity_id from the ini, e.g. DD)
- `frequency` — set by each program: `1hr` (or `6hr`) for most, `day` for the daily extremes, `fx` for the fixed fields.
- `source` — the ini's `source_desc`, which must match a `source` entry for your `source_id` in the CV.
- `external_variables` — `areacella` (the cell area referred to by `cell_measures`).

Check your values against the CV; for example, `driving_variant` must be the full `r<n>i<n>p<n>f<n>` form (`r1i1p1f1`).

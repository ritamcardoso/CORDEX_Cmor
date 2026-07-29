# `header_ini`

Per-domain grid and global-attribute configuration, read by every
`RCM_*` Fortran program via `run_out_generic.sh` (see the main
[README.md](../README.md), §2 and §3, for how these fit into a run).

Every filename here follows one pattern:

```
<EXPERIMENT>_[global_|xtrm_]<DOMAIN_ID>_<grid>.ini
```

- **`<EXPERIMENT>`** — the campaign prefix, from `env.site.sh`'s
  `EXPERIMENT[]` map: `cordex` for standard CORDEX-CMIP6 runs, `fpsurb` for
  FPS-URB-RCC runs.
- **`<DOMAIN_ID>`** — the CORDEX domain identifier, from `env.site.sh`'s
  `DOMAIN_ID[]` map (e.g. `EUR-11`, `EUR-12`, `PARIS-3`).
- **`<grid>`** — matches a key in the `run` associative array in
  `env.site.sh` (e.g. `d01`, `d02`).

There are two kinds of file `run_out_generic.sh` actually reads:

## `<EXPERIMENT>_[xtrm_]<DOMAIN_ID>_<domain>.ini` — grid/domain setup

The `&cordex_config` namelist: raw-data paths and grid dimensions. 
Under normal circumstances you do not need to modify these files

- **`dir` / `dir2`** — placeholders `_OUTPUT_WRF_`/`_OUTPUT_DIR_`, sed'd in
  by `run_out_generic.sh` from `env.site.sh`'s `OUTPUT_WRF`/`OUTPUT_DIR`
  (a trailing `/` is appended automatically, so don't include one in
  either the `.ini` placeholder or the `env.site.sh` value). Don't
  hardcode real paths here — edit `env.site.sh` instead. Note these are
  **not** per-grid like `DOMAIN_ID`/`EXPERIMENT`: `OUTPUT_WRF`/`OUTPUT_DIR`
  are single site-wide values, so if you're mixing experiments across
  grids (e.g. `d01` on `cordex`, `d02` on `fpsurb`) you currently need to
  point them at whichever experiment you're actively running — see the
  commented-out "urban downscaling" block in `env.site.sh.example`.
- **Domain & geography** — the `wrfout` domain (`nz`/`nlon`/`nlat`/
  `xoffset`/`yoffset`), and the matching `geog` name.
- **Naming conventions** — `dom`/`outdom`, the domain and model names used
  in the CMORised output filenames.

`run_out_generic.sh` automatically picks the `xtrm_` variant (sourced from
`wrfxtrm` rather than `wrfout` — note the `wrffile` value inside) when, and
only when, `<varset>` is `wxtrm` (the one that runs `RCM_sfc_xtrm`); every
other varset uses the plain filename. Keep both files in sync on anything
that isn't specific to the extreme-variable run (`dir`, `geog`, `dom`,
`outdom`, ...) — only `wrffile` and the grid/timing fields are expected to
differ.

## `<EXPERIMENT>_global_<DOMAIN_ID>_<domain>.ini` — global attributes

The `&global_metadata` namelist: global (file-level) CF/CMOR attributes
written into every output NetCDF file (institution, driving experiment,
domain ID, and so on). `run_out_generic.sh` stamps the current year into
the *grid/domain setup* file above (via the `_START_YY_`/`_END_YY_`
placeholders) before assembling each run's namelist — this file needs no
such stamping.

**The actual values you fill in must come from the official CORDEX-CMIP6
controlled vocabulary, not be made up per-experiment:**

- **[WCRP-CORDEX/cordex-cmip6-cv](https://github.com/WCRP-CORDEX/cordex-cmip6-cv)**
  — the controlled vocabulary (CV) for CORDEX-CMIP6: valid domain IDs,
  institution IDs, driving-model/experiment IDs, and the other global
  attributes CMOR compliance depends on. Any global attribute here that
  identifies your experiment (domain, institution, driving model,
  experiment, ...) should be checked against this CV before a real run —
  using a value that isn't in it will produce output that isn't
  CORDEX-CMIP6 compliant even if it runs successfully.

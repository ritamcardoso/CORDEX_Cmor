# `header_ini`

Per-domain grid and global-attribute configuration, read by every `RCM_*` Fortran program via `run_out_generic.sh` (see the main [README.md](../README.md), §2 and §3, for how these fit into a run).

There are two kinds of file `run_out_generic.sh` actually reads (Under normal circumstances you just need to setup these files once):

  1) The `&cordex_config` namelist with raw-data paths and grid dimensions

  ## `<EXPERIMENT>_<DOMAIN_ID>_<domain>.ini` — grid/domain setup

- **`<EXPERIMENT>`** — the experiment prefix, from `env.site.sh`'s single `EXPERIMENT` value (**not** per-grid, unlike `DOMAIN_ID` below — an experiment always covers every grid in `run` together); 
     e.g. `cordex` for standard CORDEX-CMIP6 runs, `fpsurb` for FPS-URB-RCC runs.

- **`<DOMAIN_ID>`** — the CORDEX domain identifier for that grid, from   `env.site.sh`'s `DOMAIN_ID[]` map (e.g. `EUR-12`, `PARIS-3`) — this one
     *does* vary per grid, even within one experiment (euro-cordex is `EUR-12` on `d01` ,fpsurb is `EUR-12` on `d01`, `PARIS-3` on `d02`).

- **`<grid>`** — matches a key in the `run` associative array in `env.site.sh` (e.g. `d01`, `d02`).


  In the `&cordex_config` namelist, set:
  
  - **Domain & geography** — the experiment  domain (`nz`/`nlon`/`nlat`/`xoffset`/`yoffset`), and the matching `geog` name.
  - **Naming conventions** — `dom`/`outdom`, the domain and model names used in the CMORised output filenames.


  - **`dir` / `dir2`** — placeholders `_OUTPUT_WRF_`/`_OUTPUT_DIR_`, sed'd in by `run_out_generic.sh` from `env.site.sh`'s `OUTPUT_WRF`/`OUTPUT_DIR` 
     a trailing `/` is appended automatically, so don't include one in either the `.ini` placeholder or the `env.site.sh` value). Don't hardcode real paths here 
     — edit `env.site.sh` instead. Note these are **not** per-grid like `DOMAIN_ID`/`EXPERIMENT`: `OUTPUT_WRF`/`OUTPUT_DIR` are single site-wide values, 
     so if you're mixing experiments across grids (e.g. `d01` on `cordex`, `d02` on `fpsurb`) you currently need to point them at whichever experiment you're actively running 
     — see the commented-out "urban downscaling" block in `env.site.sh.example`.

  - **`wrffile`** - placeholder `_WRFFILE_`,  sed'd in by `run_out_generic.sh` automatically picks the `wrfout` or `wrfxtrm` the variant. When, and only when, `<varset>` is `wxtrm` 
     (the one that runs `RCM_sfc_xtrm`); every other varset uses wrfout.

  2) The `&global_metadata` namelist: global (file-level) CF/CMOR attributes written into every output NetCDF file (institution, driving experiment, domain ID, and so on).
  
## `<EXPERIMENT>_global_<DOMAIN_ID>_<domain>.ini` — global attributes


   **The actual values you fill in must come from the official CORDEX-CMIP6 controlled vocabulary, not be made up per-experiment:**

- **[WCRP-CORDEX/cordex-cmip6-cv](https://github.com/WCRP-CORDEX/cordex-cmip6-cv)**
  — the controlled vocabulary (CV) for CORDEX-CMIP6: valid domain IDs,
  institution IDs, driving-model/experiment IDs, and the other global
  attributes CMOR compliance depends on. Any global attribute here that
  identifies your experiment (domain, institution, driving model,
  experiment, ...) should be checked against this CV before a real run —
  using a value that isn't in it will produce output that isn't
  CORDEX-CMIP6 compliant even if it runs successfully.

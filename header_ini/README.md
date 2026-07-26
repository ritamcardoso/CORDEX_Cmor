# `header_ini`

Per-domain grid and global-attribute configuration, read by every
`RCM_*` Fortran program via `run_out_generic.sh` (see the main
[README.md](../README.md), §2 and §3, for how these fit into a run).

There are two kinds of file here:

## `global_EUR-11_<domain>.ini` — grid/domain setup

One per domain (matching the `run=(...)` array in `env.site.sh`). Update
per your simulation:

- **`dir` / `dir2`** — `dir` points to your raw `wrfout` files; `dir2` is
  the destination for the CMORised output.
- **Domain & geography** — the `wrfout` domain, and the matching `geog`
  name.
- **Naming conventions** — the general domain and model names used in the
  CMORised output filenames/attributes.

## `cordex_EUR-11_<domain>.ini` — global attributes

Contains the global (file-level) CF/CMOR attributes written into every
output NetCDF file (institution, driving experiment, domain ID, and so
on). `run_out_generic.sh` stamps the current year into this file (via the
`_START_YY_`/`_END_YY_` placeholders) before assembling each run's
namelist — you don't need to touch that part.

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

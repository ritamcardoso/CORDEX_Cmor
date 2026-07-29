# Migration: old scripts -> new varsets

Verified directly against the live `scripts/` and `f90_src/` folders in
[ritamcardoso/CORDEX_Cmor](https://github.com/ritamcardoso/CORDEX_Cmor).
Each row is now one entry in `config/varsets.sh`.

Submit with (see README.md §6 for `submit.sh` — no need to export
`ROOT_DIR` yourself, it's auto-detected from `submit.sh`'s location):

```bash
$ROOT_DIR/submit.sh --job-name=wrf-<varset> --time=<TIME[varset]> \
       --output=wrf-<varset>.%j.out --error=wrf-<varset>.%j.out \
       run_out_generic.sh <datebeg> <dateend> <year_lim> <varset>
```

| Old script              | New varset    | Program(s)                          |
|--------------------------|---------------|--------------------------------------|
| run_out.sh                | `out`         | RCM_sfc_\<var\>                      |
| run_out_soil.sh           | `soil`        | RCM_sfc_\<var\>                      |
| run_out_acum.sh (radiation vars only) | `rad` | RCM_sfc_rad (fixed, 14 radiation vars) |
| run_out_acum.sh (pr/prc/sund) + run_out_snw.sh | `snw` | RCM_sfc_\<var\>       |
| run_out_cloud.sh          | `cloud`       | RCM_sfc_cloud (fixed)                |
| run_out_wxtrm.sh          | `wxtrm`       | RCM_sfc_xtrm (fixed)                 |
| run_out_tau.sh            | `tau`         | RCM_sfc_\<var\>                      |
| run_out_wpth.sh           | `wpth`        | RCM_sfc_\<var\>                      |
| run_out_plev_wa.sh        | `plev_wa`     | RCM_plev_wa (fixed, all levels)      |
| run_out_plev_zg.sh        | `plev_zg`     | RCM_plev_zg (fixed, all levels)      |
| run_out_plev_uava.sh      | `plev_uava`   | RCM_plev_uava (fixed, all levels — processes va\*) |
| run_out_plev_hus.sh       | `plev_hus`    | RCM_plev_hus (fixed, all levels)     |
| run_out_plev_ta.sh        | `plev_ta`     | RCM_plev_ta (fixed, all levels)      |
| run_out_zlev_hus.sh       | `zlev_hus`    | RCM_zlev_hus (fixed)                 |
| run_out_zlev_ta.sh        | `zlev_ta`     | RCM_zlev_ta (fixed)                  |
| run_out_zlev_uava0.sh     | `zlev_uava0`  | RCM_zlev_uava (fixed — processes va\*) |
| run_out_zlev_uava1.sh     | `zlev_uava1`  | RCM_zlev_uava (fixed — processes va\*) |
| run_out_fx.sh              | `fx`          | RCM_fx_\<var\> (`orog`, `sftlaf`, `sftlf`, `sfturf`, `sftgif`) |

**Renamed / restructured:** `acum` mixed two unrelated things — `pr`/`prc`/
`sund` (each its own `RCM_sfc_<var>.f90`) and 14 radiation variables (all
through the single `RCM_sfc_rad.f90`). Those have been split apart:
`pr`/`prc`/`sund` now live in `snw` (alongside `prsn`, `snm`, `snc`, `snw`,
`snd`, `siconca`), and the radiation-only group was renamed `rad`.

**Disabled for processing (old/superseded versions)** — commented out at
the bottom of `config/varsets.sh`, not deleted:

| Old script            | Would-be varset | Program        |
|-------------------------|------------------|-----------------|
| run_out_plev_va.sh       | `plev_va`        | RCM_plev_va     |
| run_out_zlev_va0.sh      | `zlev_va0`       | RCM_zlev_va     |
| run_out_zlev_va1.sh      | `zlev_va1`       | RCM_zlev_va     |

`plev_ua`, `zlev_ua0`, `zlev_ua1` were also disabled for processing, but are
reactivated in `VARSETS[]` as **archive-only** entries — see Archiving,
above — since `plev_uava`/`zlev_uava0`/`zlev_uava1` need their variable
lists to archive the "u" files. They're still absent from
`ORDER`/`NEXT`/`TIME`, so they never run as their own processing job.

**`fx` (time-invariant fields):** unlike every other varset above, `fx` is
deliberately **not** in `ORDER` or `NEXT[]` — these fields (orography, land
fraction, urban fraction, ...) don't vary by year, so there's nothing to
chain and `run_Analysis_v2.sh` never submits it automatically. It has a
`TIME[fx]` entry and is submitted like any other single varset (see
README.md §10, "Extracting a single variable/varset").

## Archiving

`run_cp_out.sh` and its siblings (`run_cp_soil.sh`, etc.) are replaced by
`scripts/run_cp_generic.sh`, which reads the same `VARSETS[<varset>]` entry
`run_out_generic.sh` already uses — no separate variable list to keep in
sync. `run_out_generic.sh` submits it automatically after processing each
varset, matching the original's unconditional `sbatch ... run_cp_out.sh`
call at the bottom of `run_out.sh`.

`plev_uava`, `zlev_uava0`, `zlev_uava1` only process `va*` variables, but
the underlying programs also produce `ua*` files — so each gets a second
`run_cp_generic.sh` call for its "u" companion (`plev_ua`, `zlev_ua0`,
`zlev_ua1`), reactivated from the deprecated block below purely as archive
sources (`CP_EXTRA[]` in `config/varsets.sh`). They're still not in
`ORDER`/`NEXT`/`TIME`, so they're never run as their own processing job.

## Chaining (`NEXT[]`)

```
2-cycles (A resubmits B, B resubmits A):
  out <-> soil         rad <-> snw            cloud <-> wxtrm
  tau <-> wpth         plev_wa <-> plev_zg    plev_hus <-> zlev_hus
  plev_ta <-> zlev_ta

Self-loops (resubmits itself each year):
  plev_uava   zlev_uava0   zlev_uava1
```

`plev_hus <-> zlev_hus` and `plev_ta <-> zlev_ta` are both now 2-cycles —
previously `zlev_hus -> plev_hus` and `zlev_ta -> plev_ta` were one-way and
the chain just stopped there.

Only the *second* varset in each 2-cycle (`soil`, `snw`, `wxtrm`, `wpth`,
`plev_zg`, `plev_hus`, `plev_ta`) plus the self-looping varsets
(`plev_uava`, `zlev_uava0`, `zlev_uava1`) actually advances `yeari`/`yearf`
before resubmitting (`ADVANCE_YEAR[]` in `config/varsets.sh`) — so each
2-cycle advances one year per full round-trip, not per hop.

## Directly submitted by `run_Analysis_v2.sh` (`ORDER`)

```
out, rad, cloud, plev_wa, plev_uava, zlev_hus, zlev_ta, zlev_uava0, zlev_uava1, tau
```

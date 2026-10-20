# `config/varsets.sh`

This file is the single source of truth for the whole pipeline: which
variables exist, which Fortran program processes them, how long to
schedule each job for, and how (or whether) jobs chain into one another.
`scripts/run_out_generic.sh` and `scripts/run_cp_generic.sh` are generic —
everything specific to a given "varset" lives here, not in the scripts.

The scripts only ever read `config/varsets.sh`. Two saved layouts sit
next to it, to copy over it when needed (main README §0):

| File | Layout |
|---|---|
| `varsets_chain.sh` | the chained streams (main README §8) — a saved copy of the default `varsets.sh` |
| `varsets_single.sh` | every varset loops on itself, year by year |

When you change a varset, make the same change in all three files.

See the main [README.md](../README.md) (§0 to start, §5 for this file)
for the walkthrough. This file goes one level deeper into the mechanics.

## The arrays

| Array | Keyed by | Meaning |
|---|---|---|
| `VARSETS[]` | varset name | one or more `PROGRAM_PATTERN:var1,var2,...` groups, `;`-separated (see below) |
| `TIME[]` | varset name | `--time` walltime for that varset's **processing** job |
| `MEM[]` / `DEFAULT_MEM` | varset name | `--mem` for that varset's **processing** job (falls back to `DEFAULT_MEM`, 8G, if unset) |
| `CP_TIME[]` / `DEFAULT_CP_TIME` | varset name | `--time` walltime for that varset's **archive** job (falls back to the default if unset) |
| `ADVANCE_YEAR[]` | varset name | `1` if this varset moves on to the next year(s) before resubmitting; unset/`0` otherwise |
| `NEXT[]` | varset name | which varset to auto-resubmit once this one finishes (empty/unset = don't chain) |
| `CP_EXTRA[]` | varset name | an additional varset to archive alongside this one (see "uava" u+v note below) |
| `ORDER` | — (plain array) | the varsets `run_analysis.sh` submits directly, in order |

### `VARSETS[]` syntax

```
VARSETS[name] = "<program-pattern>:<var1>,<var2>,...[;<program-pattern>:<var...>...]"
```

`<program-pattern>` is either:
- a literal program name, used as-is for every variable in that group
  (e.g. `RCM_sfc_cloud`, `RCM_plev_ta`), or
- a name containing the literal string `VAR`, substituted with each
  variable in turn (e.g. `RCM_sfc_VAR` → `RCM_sfc_tas`, `RCM_sfc_ts`, ...)

Most varsets are a single group. A varset can mix programs by listing
several groups, e.g.
`[mix]="RCM_sfc_VAR:tas,pr;RCM_sfc_rad:rsds"` runs `RCM_sfc_tas`,
`RCM_sfc_pr`, then `RCM_sfc_rad` for `rsds`, all in one job.

### Special entries in `VARSETS[]`

- **Manual runs only** (not in any stream): `cloud`, `tau`, `zlev_va0`,
  `zlev_va1` — now covered by `cloud1`/`cloud2`, `out2` and
  `zlev_uava0`/`zlev_uava1`, kept for one-off runs.
- **Archive-only**: `plev_ua`, `zlev_ua0`, `zlev_ua1`. Never processed
  (not in `ORDER` or `NEXT[]`); they exist so `run_cp_generic.sh` can
  archive the "u" files that `plev_uava`/`zlev_uava0`/`zlev_uava1` produce
  alongside their "v" files — see `CP_EXTRA[]` and main README §7.
- **`wxtrm`** must keep that name (or `testex`): only those names make
  `run_out_generic.sh` read `wrfxtrm` instead of `wrfout`.

## Current layout: 10 streams

Redistributed on 2026-10-14 using the measured maximum run times (`sacct`,
August–October 2026): 10 processing streams, leaving 1 of the 11 allowed
processors free for archive (`cp-*`) jobs. Costs of split varsets are
scaled per variable or level from the measured varset (e.g. cloud = 24h06
for 4 variables → 6h02 per variable). "est" = no measured run yet.

| Stream | Chain (per model year) | ~Time per year |
|---|---|---|
| 1 | `plev_uava` → `wxtrm` | 19h38 |
| 2 | `zlev_uava0` (self) | 20h54 est |
| 3 | `zlev_uava1` (self) | 20h54 est |
| 4 | `cloud1` → `wpth1` | 20h46 |
| 5 | `cloud2` → `wpth3` | 20h46 |
| 6 | `plev_zg` → `snw` | 20h41 |
| 7 | `plev_ta` → `wpth2` | 20h01 |
| 8 | `rad` → `out1` | 20h51 (out1 est) |
| 9 | `plev_wa` → `zlev_hus` → `zlev_ta` | 20h39 |
| 10 | `plev_hus` → `soil` → `out2` | 20h59 (out2 est) |

Changes from the 2026-08-13 layout:

- `zlev_uava0`/`zlev_uava1` (16G memory) replace the separate
  `zlev_ua0/1` + `zlev_va0/1` processing runs;
- `cloud` (24h06, the old ceiling) split into `cloud1` + `cloud2`;
- `wpth1` (17h25 for 2 variables) split into `wpth1` (clivi) + `wpth3`
  (clwvi);
- `out3` and `tau` folded into `out1`/`out2` (fewer chain hops).

The slowest stream went from 28h06 per year (`plev_hus` → `wpth1`) to
about 21h, roughly 25% faster per model year; total work is unchanged
(~206h per year), just spread evenly. The `zlev_uava0/1` estimate is
1.1 × `zlev_va0`, taken as its 19h limit since there's no measured run yet.
Re-run `tools/report_walltimes.sh` (main README §11) after the first full year
and rebalance if these, `out1` or `out2` differ much from the estimates.

## Time limits (`TIME[]`)

Unchanged varsets keep their limit (all are above the measured maximum).
New and re-split varsets get the expected run time + 4h, rounded up to the
hour.

| Varset | `TIME[]` | Basis |
|---|---|---|
| `out1` | 14:00 | est ~9h12 (13 variables) |
| `out2` | 10:00 | est ~5h12 (ps, sfcWind, z0 + tau's 3h05), + ~2h for evspsblpot (13 fields per hour; to be confirmed with report_walltimes.sh) |
| `soil` | 12:00 | max 5h05 |
| `rad` | 18:00 | max 11h39 |
| `snw` | 12:00 | max 6h06 |
| `cloud1`, `cloud2` | 17:00 | ~12h03 each (half of cloud's 24h06) |
| `wxtrm` | 08:00 | max 0h00m17s |
| `wpth1`, `wpth3` | 13:00 | ~8h43 each (half of old wpth1's 17h25) |
| `wpth2` | 10:00 | max 7h58 |
| `plev_wa` | 22:00 | max 10h57 |
| `plev_zg` | 22:00 | max 14h35 |
| `plev_uava` | 28:00 | max 19h38 |
| `plev_hus` | 18:00 | max 10h41 |
| `plev_ta` | 18:00 | max 12h03 |
| `zlev_hus` | 10:00 | max 4h05 |
| `zlev_ta` | 10:00 | max 5h37 |
| `zlev_uava0`, `zlev_uava1` | 25:00 | est ~20h54 (was 12:00 — too short) |
| `cloud` (manual) | 28:00 | max 24h06 (was 26:00 — under 2h to spare) |
| `tau` (manual) | 16:00 | max 3h05 |

The limits are for **one** model year; with a second grid enabled (main
README §2) every job does both grids, so raise them accordingly.

`CP_TIME[]`: every varset uses 20h; the longest archive job measured is
`cp-out1` at 1h31.

## Memory (`MEM[]`)

Only varsets that need more than the machine's default (8 GB per job at
ECMWF) are listed. A program keeps the whole year of its output in memory:

| | Size |
|---|---|
| one hourly variable, 424 × 412 × 8760 × 4 bytes | 6.1 GB (fits in 8G) |
| `zlev_uava`: ua and va, both hourly | 12.2 GB (needs 16G) |
| `soil`: one 6-hourly 4-layer variable, 424 × 412 × 4 × 1460 × 4 bytes | 4.1 GB, plus read buffers (set to 16G) |

## How a run actually flows

1. `run_out_generic.sh <datebeg> <dateend> <year_lim> <varset>` looks up
   `VARSETS[<varset>]`, loops over every group/variable, compiles+runs the
   matching Fortran program for each year in `[datebeg, dateend]`.
2. If `ARCHIVE="on"` in `env.site.sh`, it then submits `run_cp_generic.sh`
   for the same varset (archiving) — and a second time for
   `CP_EXTRA[<varset>]` if set.
3. It then checks `NEXT[<varset>]`. If set, and if `yeari <= year_lim`
   (`yeari` is the year of `datebeg`), it submits that next varset for
   the same dates. If `ADVANCE_YEAR[<varset>]=1`, it instead checks
   `yearf < year_lim` (`yearf` is the year of `dateend`) and submits the
   next block of years, the same length as this one, cut off at
   `year_lim` — so the stream stops after `year_lim`.

Step 3 is the chaining: it runs each stream year after year
(`rad→out1→rad`, self-loops like `zlev_uava0`, etc. — see the main README
§8). Steps 1–2 happen regardless of `NEXT[]`/`ADVANCE_YEAR[]`.

## Turning chaining off

If you'd rather drive year progression yourself (e.g. from a workflow
manager, a cron job, or by calling `./submit.sh` once per year yourself)
instead of letting each varset resubmit the next one:

Whatever you change, make the same change in `varsets_chain.sh` (or
`varsets_single.sh`) if you want to keep it when you next switch layouts.

- **Per varset:** leave `NEXT[<varset>]` unset (or delete its entry). Step
  3 above becomes a no-op for that varset — it processes its date range,
  archives, and stops. Nothing else changes; `ORDER` and `run_analysis.sh`
  still work exactly the same for one-shot submission.
- **Globally:** clear the whole `NEXT[]` array (`declare -A NEXT=()`).
  Every varset in `ORDER` then becomes a single one-shot job per
  invocation of `run_analysis.sh` — call it again yourself whenever you
  want the next batch processed. With only the stream heads in `ORDER`,
  the other links would then never run, so list every varset you need.
- **Each varset on its own, year by year:** use
  `config/varsets_single.sh`, where every varset loops on itself (main
  README §0 has the steps for switching to it).
- Archiving is unaffected either way — it's step 2 (controlled only by
  `ARCHIVE` in `env.site.sh`), not part of the chain.
- `ADVANCE_YEAR[]` only matters to varsets that still have a `NEXT[]`
  entry, so there's nothing extra to clean up there.

## I just want a few variables

Two ways to get there, depending on whether you want the existing
scheduling/chaining or not:

- **Trim an existing varset:** just remove variables from its comma list
  in `VARSETS[]`, e.g. shrink `[out1]="RCM_sfc_VAR:tas,ts,th,..."` down to
  the ones you need. Everything else (`TIME`, `NEXT`, `CP_TIME`, `ORDER`
  membership) keeps working unchanged.
- **Add a new, smaller varset:** give it its own entry, e.g.
  `[my_few]="RCM_sfc_VAR:tas,pr"`, plus a `TIME[my_few]` entry (required —
  `submit.sh` uses it as the job's `--time`). You do
  **not** need to add it to `ORDER` or `NEXT[]` if you're only ever going
  to submit it manually:

  ```bash
  ./submit.sh run_out_generic.sh 19900101 19901231 1990 my_few
  ```

  `CP_TIME[my_few]` and `MEM[my_few]` are optional (they fall back to
  `DEFAULT_CP_TIME` and `DEFAULT_MEM`).

## Where variable names and definitions come from

The variable short names used throughout `VARSETS[]` (`tas`, `hus850`,
`va50m`, ...) follow the CORDEX CMIP6 variable request, not an internal
convention — cross-check any new variable against:

- **[WCRP-CORDEX/data-request-table](https://github.com/WCRP-CORDEX/data-request-table)**
  — the authoritative list of requested CORDEX-CMIP6 variables: short
  names, units, frequency, priority, and definitions. This is the source
  of truth for *what a variable is called and what it means*.
- **[CORDEX-WRF-community/WRF-CMORizer](https://github.com/CORDEX-WRF-community/WRF-CMORizer/tree/main)**
  — the community Fortran source for actually extracting/CMORising each
  variable from WRF output. The `RCM_sfc_*`/`RCM_plev_*`/`RCM_zlev_*`
  programs referenced in `VARSETS[]` (living in `f90_src/` in this repo)
  correspond to sources there; check it before adding a variable this repo
  doesn't have a program for yet.

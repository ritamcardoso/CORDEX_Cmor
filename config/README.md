# `config/varsets.sh`

This file is the single source of truth for the whole pipeline: which
variables exist, which Fortran program processes them, how long to
schedule each job for, and how (or whether) jobs chain into one another.
`scripts/run_out_generic.sh` and `scripts/run_cp_generic.sh` are generic —
everything specific to a given "varset" lives here, not in the scripts.

See the main [README.md](../README.md) (§5) for the full onboarding walkthrough.
This file goes one level deeper into the mechanics.

## The arrays

| Array | Keyed by | Meaning |
|---|---|---|
| `VARSETS[]` | varset name | one or more `PROGRAM_PATTERN:var1,var2,...` groups, `;`-separated (see below) |
| `TIME[]` | varset name | `--time` walltime for that varset's **processing** job |
| `CP_TIME[]` / `DEFAULT_CP_TIME` | varset name | `--time` walltime for that varset's **archive** job (falls back to the default if unset) |
| `ADVANCE_YEAR[]` | varset name | `1` if this varset's own script increments `yeari`/`yearf` by 1 before resubmitting; unset/`0` otherwise |
| `NEXT[]` | varset name | which varset to auto-resubmit once this one finishes (empty/unset = don't chain) |
| `CP_EXTRA[]` | varset name | an additional varset to archive alongside this one (see "uava" u+v note below) |
| `ORDER` | — (plain array) | the varsets `run_Analysis_v2.sh` submits directly, in order |

### `VARSETS[]` syntax

```
VARSETS[name] = "<program-pattern>:<var1>,<var2>,...[;<program-pattern>:<var...>...]"
```

`<program-pattern>` is either:
- a literal program name, used as-is for every variable in that group
  (e.g. `RCM_sfc_cloud`, `RCM_plev_ta`), or
- a name containing the literal string `VAR`, substituted with each
  variable in turn (e.g. `RCM_sfc_VAR` → `RCM_sfc_tas`, `RCM_sfc_ts`, ...)

Most varsets are a single group. `acum`'s replacement (`rad`) used to need
two — see the git history / `MIGRATION.md` for a worked example of a
multi-group entry.

## How a run actually flows

1. `run_out_generic.sh <datebeg> <dateend> <year_lim> <varset>` looks up
   `VARSETS[<varset>]`, loops over every group/variable, compiles+runs the
   matching Fortran program for each year in `[datebeg, dateend]`.
2. It then **unconditionally** submits `run_cp_generic.sh` for the same
   varset (archiving) — and a second time for `CP_EXTRA[<varset>]` if set.
3. It then checks `NEXT[<varset>]`. If set, and if `yeari <= year_lim`
   (where `yeari` is derived from `datebeg`, not from the internal
   per-year loop), it resubmits itself for that next varset — advancing
   the year first if `ADVANCE_YEAR[<varset>]=1`.

Step 3 is what's referred to below as the "legacy loop": it reproduces the
original per-script self/pair-resubmission behaviour (`out↔soil`,
`rad↔snw`, self-loops like `plev_uava`, etc. — see the main README §8).
Steps 1–2 happen regardless of `NEXT[]`/`ADVANCE_YEAR[]`.

## I don't want the legacy self-resubmission loops

If you'd rather drive year progression yourself (e.g. from a workflow
manager, a cron job, or by just calling `sbatch` once per year externally)
instead of letting each varset re-queue itself or its pair indefinitely:

- **Per varset:** leave `NEXT[<varset>]` unset (or delete its entry). Step
  3 above becomes a no-op for that varset — it processes its date range,
  archives, and stops. Nothing else changes; `ORDER` and `run_Analysis_v2.sh`
  still work exactly the same for one-shot submission.
- **Globally:** clear out the whole `NEXT[]` array (comment out every
  line, or replace the block with `declare -A NEXT=()`). Every varset in
  `ORDER` then becomes a single one-shot job per invocation of
  `run_Analysis_v2.sh` — call it again yourself whenever you want the next
  batch processed.
- Archiving is unaffected either way — it's unconditional (step 2), not
  part of the chain.
- `ADVANCE_YEAR[]` only matters to varsets that still have a `NEXT[]`
  entry, so there's nothing extra to clean up there.

## I just want a few variables

Two ways to get there, depending on whether you want the existing
scheduling/chaining or not:

- **Trim an existing varset:** just remove variables from its comma list
  in `VARSETS[]`, e.g. shrink `[out]="RCM_sfc_VAR:tas,ts,th,..."` down to
  the ones you need. Everything else (`TIME`, `NEXT`, `CP_TIME`, `ORDER`
  membership) keeps working unchanged.
- **Add a new, smaller varset:** give it its own entry, e.g.
  `[my_few]="RCM_sfc_VAR:tas,pr"`, plus a `TIME[my_few]` entry (required —
  it's read either by your own manual `sbatch --time=...` or, if something
  chains into it, by the resubmitting script via `TIME[$next]`). You do
  **not** need to add it to `ORDER` or `NEXT[]` if you're only ever going
  to submit it manually:

  Make sure you link submit.sh to your submission folder

  ```bash
  ./submit.sh --job-name=wrf-my_few --time=04:00:00 \
         --output=wrf-my_few.%j.out --error=wrf-my_few.%j.out \
         run_out_generic.sh 19900101 19901231 2000 my_few
  ```

  `CP_TIME[my_few]` is optional (falls back to `DEFAULT_CP_TIME`).

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

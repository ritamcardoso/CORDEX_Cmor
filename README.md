# Guide to CMORising WRF Output

[![shellcheck](https://github.com/ritamcardoso/CORDEX_Cmor/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/ritamcardoso/CORDEX_Cmor/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

These Fortran programs and accompanying scripts extract and convert WRF
output into CMOR-compliant format on a yearly basis, and archive the result
to ECFS and a remote server.

This used to be two dozen near-duplicate submission scripts, one per
variable group, each with its own hardcoded paths and variable list. It's
now 3 generic scripts driven by one small config file
(`config/varsets.sh`) plus one site-specific settings file
(`env.site.sh`), submitted through a single wrapper (`submit.sh`) —
everything below walks through the full setup, start to finish.

## 1. Directory Setup

Place all files and subfolders into a single root directory, maintaining
the provided folder structure:

```
f90_src/       <- Fortran source (RCM_sfc_*.f90, RCM_plev_*.f90, RCM_zlev_*.f90, ...)
header/        <- per-variable namelist headers
header_ini/    <- per-domain grid/global config (see header_ini/README.md)
config/        <- varsets.sh: the single source of truth for variables/programs/scheduling (see config/README.md)
                  lint_varsets.sh: static consistency check for varsets.sh (also runs in CI)
scripts/       <- the 3 generic job scripts, plus report_walltimes.sh (see "Notes", below)
submit.sh, env.site.sh.example, LICENSE, README.md, MIGRATION.md
```

This root directory is referred to as `ROOT_DIR` everywhere below — see
[§9, Where the code lives](#9-where-the-code-lives-root_dir) for how the
scripts find it. It does not need to be, and generally shouldn't be, the
same directory you submit jobs from.

## 2. Configuration (`header_ini`)

Update the grid characteristics in the `header_ini` files to match your
specific simulation (see [`header_ini/README.md`](header_ini/README.md)
for the full filename pattern):

* **Directories:** now set in `env.site.sh` (§4) as `OUTPUT_WRF` (raw
  `wrfout` location) and `OUTPUT_DIR` (CMORised-output destination), not
  in the `.ini` files — the `.ini` files just hold the
  `_OUTPUT_WRF_`/`_OUTPUT_DIR_` placeholders `run_out_generic.sh`
  substitutes at run time.
* **Domain & Geography:** in `<EXPERIMENT>_<DOMAIN_ID>_<grid>.ini` (e.g.
  `cordex_EUR-12_d01.ini`), update the domain of the `wrfout` file (and
  the matching `geog` name).
* **Naming Conventions:** change the general domain and model names used
  for the CMORised variables (`dom`/`outdom`, same file).
* **Global Properties:** edit `<EXPERIMENT>_global_<DOMAIN_ID>_<grid>.ini`
  (e.g. `cordex_global_EUR-12_d01.ini`) — the global characteristics of
  the variables, tailored to your experiment. `<EXPERIMENT>` and
  `<DOMAIN_ID>` must match what you set in `env.site.sh`'s
  `EXPERIMENT[]`/`DOMAIN_ID[]` maps for that grid (§4) — every
  `<EXPERIMENT>`/`<DOMAIN_ID>` pair needs **both** an
  `<EXPERIMENT>_<DOMAIN_ID>_<grid>.ini` and a matching
  `<EXPERIMENT>_global_<DOMAIN_ID>_<grid>.ini`; a domain-ID mismatch
  between the two (one says `EUR-12`, the other `EUR-11`, say) will break
  the lookup for whichever one doesn't match `DOMAIN_ID[]`. These must
  also match the official CORDEX-CMIP6 controlled vocabulary — see
  [`header_ini/README.md`](header_ini/README.md) and
  [WCRP-CORDEX/cordex-cmip6-cv](https://github.com/WCRP-CORDEX/cordex-cmip6-cv)
  for the valid values.

## 3. Headers (`header` folder)

The `header` folder contains the specific namelist header for each
variable (`header_<var>`). Under normal circumstances you do not need to
modify these files — the scripts assemble a full namelist per run by
concatenating the relevant `header_<var>` onto the `header_ini` grid config
(see `run_out_generic.sh`'s processing loop).

## 4. Site Environment (`env.site.sh`)

This is the one file that's genuinely different per user/machine, and the
only one you need to copy and edit:

```bash
cp env.site.sh.example env.site.sh
# then edit it
```

It covers everything the old per-script "TO CHANGE" sections used to hold,
now in one place:

* **Paths** — `PROG_DIR`, `HEADER_DIR`, `HEADER_INI_DIR` (all derived from
  `ROOT_DIR`, so you don't repeat yourself), and `RUN_DIR` — the scratch
  working directory each run processes in. Each run generates its own
  namelist and works in this folder; don't change that behaviour, just
  point it wherever you want the scratch data to live.
* **Compiler/library versions** — `intel_v`, `hdf5_v`, `netcdf_v`, `FC`,
  `FFLAGS`, and the NetCDF/HDF5 include/lib paths.
* **Domains** — `run` is the set of grids to process, keyed the same way
  as `DOMAIN_ID[]` below it (only the keys matter; the value is unused,
  `1` by convention) — e.g. `run=([d01]=1)`, plus a matching entry in
  `DOMAIN_ID[]` (e.g. `[d01]="EUR-12"`) for each. Together with
  `EXPERIMENT` (below) these select `<EXPERIMENT>_<DOMAIN_ID>_<grid>.ini` /
  `<EXPERIMENT>_global_<DOMAIN_ID>_<grid>.ini` out of `header_ini/` — see
  [`header_ini/README.md`](header_ini/README.md). Add as many
  `run`/`DOMAIN_ID` entries as you need, provided you have a matching
  `header_ini` file for each. Comment a grid's line out in `run` to
  disable it without deleting its `DOMAIN_ID` entry.
* **Experiment + raw/output directories** — `EXPERIMENT` (the campaign
  prefix, `cordex` for standard CORDEX-CMIP6 runs or `fpsurb` for
  FPS-URB-RCC runs), `OUTPUT_WRF` (raw `wrfout` location) and `OUTPUT_DIR`
  (CMORised-output destination, sed'd into each `.ini` file's
  `_OUTPUT_WRF_`/`_OUTPUT_DIR_` placeholders at run time). **Unlike
  `DOMAIN_ID`, these three are single site-wide values, not per-grid** —
  an experiment always spans every grid in `run` together (`cordex` only
  ever runs `d01`; `fpsurb` runs `d01` *and* `d02` at once, just on
  different domain IDs — `EUR-12` and `PARIS-3` respectively).
  `env.site.sh.example` ships two ready-made blocks (CORDEX vs.
  urban-downscaling); uncomment whichever matches what you're currently
  running, together with the matching `run`/`DOMAIN_ID` entries above.
  **Uncomment the whole block, not just some lines** — the two blocks
  work by plain sequential reassignment (the urban block, being lower in
  the file, simply overwrites `EXPERIMENT`/`ROOT_RUN_DIR`/`OUTPUT_DIR`/
  `OUTPUT_WRF` if you leave the CORDEX block active above it), so leaving
  any one of those four commented out in the block you actually want
  silently keeps that variable's CORDEX-block value instead.
* **Archive step settings** — `CP_MODULES`, `CP_RUN_DIR`, `ECFS_BASE`,
  `REMOTE_HOST`, `REMOTE_BASE` (see [§7, Archiving](#7-archiving)).

`env.site.sh` is gitignored — it never gets committed.

**`--account` / `--mail-user` / `--chdir` are not set here** — see
[§6](#6-submission-scripts-scripts-folder) below.

## 5. Variable Sets (`config/varsets.sh`)

This file replaces both the old "define variables in each individual
script" step and `summary_list.txt` — it's the single place that defines
every variable group ("varset"), what Fortran program(s) process it, how
long to schedule it for, and how it chains to other varsets. You will
rarely need to touch anything else once this is set up.

**[`config/README.md`](config/README.md) covers this file in full**,
including how to turn off the legacy self-resubmission chaining if you
just want one-shot runs, and how to cut it down to only the variables you
need. Variable names follow the
[CORDEX-CMIP6 data request](https://github.com/WCRP-CORDEX/data-request-table),
and the Fortran programs referenced in each entry correspond to
[CORDEX-WRF-community/WRF-CMORizer](https://github.com/CORDEX-WRF-community/WRF-CMORizer/tree/main) —
see `config/README.md` before adding a variable this repo doesn't have a
program for yet.

### Fortran program naming

Each varset maps to one or more variable "groups", each with its own
program pattern:

```
[out]="RCM_sfc_VAR:tas,ts,th,..."                 # RCM_sfc_tas.f90, RCM_sfc_ts.f90, ...
[cloud]="RCM_sfc_cloud:clh,clm,cll,clt"            # always RCM_sfc_cloud.f90
[plev_ta]="RCM_plev_ta:ta1000,ta925,...,ta30"      # always RCM_plev_ta.f90, all 16 levels
[zlev_uava0]="RCM_zlev_uava:va50m,va150m,va100m"   # always RCM_zlev_uava.f90
```

`VAR` in a program pattern gets substituted with the current variable; a
pattern without `VAR` is used as-is for every variable in that group.
Per-variable programs turn out to be **the exception, not the rule** once
you include plev/zlev:

- **sfc**: mostly per-variable (`RCM_sfc_<var>`) — `out`, `soil`, `snw`,
  `tau`, `wpth`. But `cloud` → always `RCM_sfc_cloud`, `wxtrm` → always
  `RCM_sfc_xtrm`, and `rad` → always `RCM_sfc_rad` (14 radiation variables,
  one fixed program).
- **plev**: always one fixed program per family, covering every pressure
  level in one program (`RCM_plev_ta.f90` handles `ta1000`...`ta30`).
- **zlev**: same — one fixed program per family, covering every height
  level (`RCM_zlev_ua.f90` handles `ua50m`, `ua100m`, `ua150m`, ...).

`plev_uava` and `zlev_uava0`/`zlev_uava1` process `ua`and `va` variables through a
program literally named `RCM_plev_uava` / `RCM_zlev_uava` — that's how the
source names those programs, not a bug in this config.

**Fixed (time-invariant) fields** are handled the same way, just with
their own varset: `[fx]="RCM_fx_VAR:orog,sftlaf,sftlf,sfturf,sftgif"` →
`RCM_fx_orog.f90`, `RCM_fx_sftlaf.f90`, `RCM_fx_sftlf.f90`,
`RCM_fx_sfturf.f90`, `RCM_fx_sftgif.f90`. `fx` is deliberately **not** in
`ORDER`, so `run_Analysis_v2.sh` never submits it automatically — these
fields don't vary by year, so there's nothing to chain. Submit it once, on
its own, the same way as any other single varset (§10, "Extracting a
single variable/varset").

### Scheduling and chaining

Alongside `VARSETS[]`, the same file holds:

* **`TIME[]`** — walltime to request for each varset's processing job.
* **`CP_TIME[]`** / **`DEFAULT_CP_TIME`** — walltime for each varset's
  archive job.
* **`ORDER`** — the varsets `run_Analysis_v2.sh` submits directly (see
  [§10](#10-job-submission-instructions)).
* **`NEXT[]`** and **`ADVANCE_YEAR[]`** — see
  [§8, Chaining behaviour](#8-chaining-behaviour).
* **`CP_EXTRA[]`** — see [§7, Archiving](#7-archiving).

See [§11, Adding/changing a variable set](#11-addingchanging-a-variable-set)
for how to extend this file.

## 6. Submission Scripts (`scripts` folder + `submit.sh`)

Only 3 job scripts now, each replacing what used to be a whole family of
per-variable files:

| Script | Replaces | Role |
|---|---|---|
| `run_out_generic.sh` | all `run_out_*.sh` | processes one varset for a year range, then submits the archive job and (if configured) the next varset in the chain |
| `run_cp_generic.sh` | all `run_cp_*.sh` | archives one varset's output to ECFS + remote |
| `run_Analysis_v2.sh` | itself (orchestrator) | submits every varset in `ORDER`, 120s apart |

**Slurm account/mail/chdir:** with only 3 scripts, there's no separate
options file to maintain — `sbatch` has no flag to merge one in anyway
(not supported by ECMWF's `sbatch`). Just edit the `#SBATCH --account=`,
`--mail-type=`, `--mail-user=`, `--chdir=` lines directly at the top of
all 3 scripts (identical in each).

Everything else in these 3 scripts is generic — you should not need to
edit anything below their `#SBATCH` block.

### `submit.sh` — how you actually submit

`submit.sh`, at the repo root, is the wrapper you invoke instead of calling
`sbatch` directly. It auto-detects `ROOT_DIR` from its own location, then
re-exports it into the job's environment for you:

```bash
./submit.sh [sbatch options...] <script-name> [script-args...]

# e.g.
./submit.sh run_Analysis_v2.sh 20010101 20011231 2005
./submit.sh --job-name=wrf-fx --time=01:00:00 \
       --output=wrf-fx.%j.out --error=wrf-fx.%j.out \
       run_out_generic.sh 20010101 20011231 2000 fx
```

`<script-name>` is looked up under `$ROOT_DIR/scripts/` automatically —
you don't type `scripts/` or the full path. Anything before it that starts
with `-` is passed straight through to `sbatch` (`--job-name`, `--time`,
`--output`, `--error`, ...); anything after it is passed to the target
script as its own arguments (`<datebeg> <dateend> <year_lim> [<varset>]`).

This is also how the pipeline chains itself internally —
`run_Analysis_v2.sh` and `run_out_generic.sh` both call
`${REPO_DIR}/submit.sh` (not `sbatch` directly) whenever they submit a
follow-up or archive job, so `ROOT_DIR` propagates automatically through
every hop of the chain without you needing to export it anywhere.

You can still call `sbatch $ROOT_DIR/scripts/<script>.sh ...` directly if
you'd rather — every script still validates `ROOT_DIR` and fails with a
clear error if it isn't set — but then `ROOT_DIR` **does** need to already
be exported in your environment (e.g. `~/.bashrc`), since that path
skips `submit.sh`'s auto-detection. `submit.sh` is the recommended way in
because it removes that manual step.

## 7. Archiving

After processing each varset, `run_out_generic.sh` unconditionally submits
`run_cp_generic.sh` for the same varset — matching the original scripts'
unconditional call to their `run_cp_<varset>.sh` sibling. It reads the same
`VARSETS[<varset>]` entry, flattens every group into one plain variable
list, and archives each `<var>_*.nc` to ECFS and a remote server. There's
nothing varset-specific to write — adding a new varset to
`config/varsets.sh` automatically gets archiving for free.

`plev_uava`, `zlev_uava0`, and `zlev_uava1`  *process* the u and v-components 
so their archive step needs two calls, not one. `CP_EXTRA[]` in `config/varsets.sh`
 names the "u" companion varset to also archive (`plev_ua`, `zlev_ua0`, `zlev_ua1` respectively —
reactivated from the deprecated block purely for this, since they're not
used for processing and aren't in `ORDER`/`NEXT`/`TIME`). When
`CP_EXTRA[$VARSET]` is set, `run_out_generic.sh` submits a second
`run_cp_generic.sh` job for that companion.

The archive step's modules and remote paths (which differ from the
compile/run environment) live in `env.site.sh`: `CP_MODULES`, `CP_RUN_DIR`,
`ECFS_BASE`, `REMOTE_HOST`, `REMOTE_BASE`.

## 8. Chaining behaviour

Each varset's year loop resubmits another varset when it finishes (`NEXT[]`
in `config/varsets.sh`), verified against each live script's *uncommented*
`sbatch` call:

- **2-cycles**: `out↔soil`, `rad↔snw`, `cloud↔wxtrm`, `tau↔wpth`,
  `plev_wa↔plev_zg`, `plev_hus↔zlev_hus`, `plev_ta↔zlev_ta`
- **Self-loops** (resubmits itself each year): `plev_uava`, `zlev_uava0`,
  `zlev_uava1`

Only about half the varsets actually advance `yeari`/`yearf` before
resubmitting (`ADVANCE_YEAR[]`) — in each 2-cycle, one side advances the
year and the other doesn't, so the pair advances one year per full
round-trip rather than per hop. This is preserved as-is from the original
scripts rather than "fixed", since changing it would double the effective
year-advance rate.

## 9. Where the code lives (`ROOT_DIR`)

This repo can live anywhere (e.g. `ROOT_DIR=$HPCPERM/CORDEX/scenarios/Analysis`)
— it does **not** need to be checked out into your submission/scratch
directory, and you don't need to `cd` into it before running `sbatch`.

Every script requires `ROOT_DIR` to already be set when it runs, checked at
startup with a clear error if it isn't. **The 3 job scripts in `scripts/`
do not try to auto-detect their own location from `$0`/`dirname`** —
`sbatch` copies the submitted script into a spool directory before running
it, so `$0` at runtime often doesn't point at this repo at all, especially
once you submit from somewhere else (e.g. `$SCRATCH/Analysis`) than where
the code lives.

`submit.sh`, the wrapper at the repo root (§6), sidesteps this: it *is*
where `$0`/`dirname` still works (you run it directly, so it isn't copied
to a spool dir), so it auto-detects `ROOT_DIR` from its own location and
passes it into the job via `sbatch --export`. If you always submit through
`submit.sh`, you never need to export `ROOT_DIR` yourself.

If you call `sbatch $ROOT_DIR/scripts/<script>.sh ...` directly instead
(bypassing `submit.sh`), you do need `ROOT_DIR` set in your own
environment first. Export it once, e.g. in `~/.bashrc` so every future
shell (and every batch job, since Slurm inherits your environment by
default) has it:

```bash
export ROOT_DIR=$HPCPERM/CORDEX/scenarios/Analysis
```

This is completely independent of:
- **where you submit from** — anywhere, e.g. `$SCRATCH/Analysis` (set as
  `--chdir` in the 3 scripts' `#SBATCH` headers if you want job logs to
  land there)
- **`RUN_DIR`** (`env.site.sh`) — per-run scratch working directory used
  while processing (e.g. `$SCRATCH/ssp370/out`)
- **`CP_RUN_DIR`** (`env.site.sh`) — where finished output files land
  before archiving (e.g. `$SCRATCH/ssp370/output`)

## 10. Job Submission Instructions

### First-time setup checklist

1. Check out this repo somewhere permanent — that's `ROOT_DIR`. If you
   always submit via `submit.sh` (§6, recommended) it auto-detects this
   for you; otherwise `export ROOT_DIR=/path/to/it` (add to `~/.bashrc`).
2. Fill in `header_ini/` and confirm `header/` (§2, §3).
3. `cp env.site.sh.example env.site.sh` and fill it in (§4).
4. Check `config/varsets.sh` covers the variables you need (§5) —
   `MIGRATION.md` maps old script names to varsets if you're coming from
   the previous per-variable-script layout.
5. Fill in `--account`/`--mail-user`/`--chdir` at the top of all 3 scripts
   in `scripts/` (§6).

### Standard submission

`run_Analysis_v2.sh` is the main controller — it submits every varset in
`ORDER` (`config/varsets.sh`), each of which manages its own dependencies
via `NEXT[]`, submitting some archival/follow-up tasks as soon as its own
processing finishes. `year_lim` is a failsafe: it stops each chain's
self-resubmission at a specific year so a stuck loop doesn't run forever.

```bash
cd $SCRATCH/Analysis   # or wherever you want to submit from — doesn't have to be ROOT_DIR

# Syntax
$ROOT_DIR/submit.sh run_Analysis_v2.sh <datebeg> <dateend> <year_lim>

# Example: process 2001, then keep chaining year by year until 2005
$ROOT_DIR/submit.sh run_Analysis_v2.sh 20010101 20011231 2005
```

(If `ROOT_DIR` isn't exported yet, run `submit.sh` by its full or relative
path the first time, e.g. `/path/to/repo/submit.sh ...` — it doesn't need
`ROOT_DIR` set beforehand, since it auto-detects it from its own location.)

### Extracting a single variable/varset

Check `config/varsets.sh` (or `MIGRATION.md` if you're looking for where an
old `run_out_<x>.sh` script went) to find which varset covers your
variable, then submit it directly — no file to modify:

```bash
$ROOT_DIR/submit.sh --job-name=wrf-soil --time=12:00:00 \
       --output=wrf-soil.%j.out --error=wrf-soil.%j.out \
       run_out_generic.sh 19900101 19901231 2000 soil
```

`fx` (§5) — the time-invariant fields — is submitted the same way, just
with a short walltime and no year range that actually matters:

```bash
$ROOT_DIR/submit.sh --job-name=wrf-fx --time=01:00:00 \
       --output=wrf-fx.%j.out --error=wrf-fx.%j.out \
       run_out_generic.sh 19900101 19900101 1900 fx
```

### Extracting multiple years in a single submission

Set `datebeg`/`dateend` to span the whole period you want processed in one
job — `run_out_generic.sh`'s internal year loop already handles a range,
independent of the chaining. To stop it from *also* auto-chaining to the
next varset afterward, set `year_lim` to a year **before** your start year
— the chain-resubmission check (`yeari <= year_lim`) then evaluates false,
so no follow-up job gets submitted (the archive step still runs regardless,
since that part is unconditional):

```bash
# Process 2001-2005 in one job, no auto-chained follow-up job
$ROOT_DIR/submit.sh --job-name=wrf-out --time=18:00:00 \
       --output=wrf-out.%j.out --error=wrf-out.%j.out \
       run_out_generic.sh 20010101 20051231 2000 out
```

(Previously this required commenting out lines in every `run_out*.sh` file
by hand; now it's just a parameter choice.)

## 11. Adding/changing a variable set

Edit **only** `config/varsets.sh`:

```bash
declare -A VARSETS=(
  ...
  [my_new_set]="RCM_sfc_VAR:varA,varB,varC"          # per-variable program
  # or: [my_new_set]="RCM_sfc_myprog:varA,varB,varC" # one fixed program
)
declare -A TIME=(
  ...
  [my_new_set]="04:00:00"
)
```

Add it to `ORDER` if it should be submitted directly by `run_Analysis_v2.sh`,
to `NEXT[]` if some varset should chain into (or from) it, and to
`ADVANCE_YEAR[]=1` if it should advance the year before resubmitting.

## Notes / things to double check before first real run

- The compile step (Fortran module + subs + program) is now cached per run
  (§6): the shared module/subroutines build once, and each program builds
  once even for fixed-program groups shared across many variables/levels
  (e.g. `RCM_plev_ta.f90` across all 16 pressure levels) — not once per
  variable/year, as in the original scripts. Set `FORCE_REBUILD=1` to
  bypass the cache (e.g. right after editing `f90_src/`).
- Per-variable, per-year output is skipped if it already exists in
  `OUTPUT_DIR` (checked against `<var>_*<year>*.nc`) — reruns/resubmits are
  safe without reprocessing finished years. Set `FORCE_REPROCESS=1` to
  redo it anyway.
- `run_cp_generic.sh`'s ECFS and `scp` archive steps now run up to
  `MAX_PARALLEL_CP` (default 8) transfers concurrently instead of one
  variable at a time — override with `MAX_PARALLEL_CP=<n>` if the
  remote/ECFS can't take that many connections at once.
- `config/lint_varsets.sh` statically checks `config/varsets.sh` for
  dangling `NEXT[]`/`CP_EXTRA[]` references, `VARSETS[]` entries missing
  `TIME[]`, and programs/variables with no matching file under `f90_src/`
  or `header/`. It runs in CI on every push (`.github/workflows/`); run it
  yourself after editing `config/varsets.sh` (`config/lint_varsets.sh`).
- Scripts use `#!/bin/bash` explicitly (not `#!/bin/sh`) since they rely on
  bash associative arrays — the originals already used bash-only syntax
  under a `#!/bin/sh` shebang, which only worked if `/bin/sh` happened to be
  bash on your system. This makes that assumption explicit and portable.
- `TIME[]` values for `out` and `plev_ta` were confirmed against the live
  scripts; the rest are carried over/estimated and worth a check — `rad`
  and `snw` especially, since what they cover just changed.
  `scripts/report_walltimes.sh` pulls real elapsed times from `sacct` for
  jobs this pipeline has already submitted and suggests `TIME[]`/
  `CP_TIME[]` updates from that history, once you have some runs behind
  you (run it on the HPC login node, not in CI).
- `CP_TIME[]` (archive-step walltime) is only confirmed for `out`
  (`20:00:00`, from the live `run_cp_out.sh`); everything else falls back
  to `DEFAULT_CP_TIME` (`04:00:00`) until you've checked real numbers (see
  `scripts/report_walltimes.sh` above).
- `plev_va`, `zlev_va0`, `zlev_va1` are disabled on purpose (old/superseded
  versions) — commented out at the bottom of `config/varsets.sh` rather
  than deleted, so they're easy to compare against or resurrect.
  `plev_ua`, `zlev_ua0`, `zlev_ua1` are also disabled *for processing*, but
  reactivated as archive-only `VARSETS[]` entries (see §7, above).

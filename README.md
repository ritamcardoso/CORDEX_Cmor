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
(`env.site.sh`) — everything below walks through the full setup, start to
finish.

## 1. Directory Setup

Place all files and subfolders into a single root directory, maintaining
the provided folder structure:

```
f90_src/       <- Fortran source (RCM_sfc_*.f90, RCM_plev_*.f90, RCM_zlev_*.f90, ...)
header/        <- per-variable namelist headers
header_ini/    <- per-domain grid/global config
config/        <- varsets.sh: the single source of truth for variables/programs/scheduling
scripts/       <- the 3 generic job scripts
env.site.sh.example, LICENSE, README.md, MIGRATION.md
```

This root directory is referred to as `ROOT_DIR` everywhere below — see
[§9, Where the code lives](#9-where-the-code-lives-root_dir) for how the
scripts find it. It does not need to be, and generally shouldn't be, the
same directory you submit jobs from.

## 2. Configuration (`header_ini`)

Update the grid characteristics in the `header_ini` files to match your
specific simulation:

* **Directories:** update `dir` to point to the location of your raw
  `wrfout` files, and `dir2` to the destination folder for the CMORised
  output.
* **Domain & Geography:** update the domain of the `wrfout` file (and the
  matching `geog` name).
* **Naming Conventions:** change the general domain and model names used
  for the CMORised variables.
* **Global Properties:** edit `global_EUR-11_d01.ini` — the global
  characteristics of the variables, tailored to your experiment.

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
* **Domains** — `run=("d01")`. Add as many as you need, provided you have
  a matching `header_ini` file for each.
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

`plev_uava` and `zlev_uava0`/`zlev_uava1` process `va*` variables through a
program literally named `RCM_plev_uava` / `RCM_zlev_uava` — that's how the
source names those programs, not a bug in this config.

`run_out_fx.sh` (`orog`, `sftlaf`, `sftlf`, `sfturf`, `sftgif` →
`RCM_fx_<var>`) is intentionally **not** wired in yet — those
`RCM_fx_*.f90` sources don't exist in `f90_src/` in this repo yet. Add an
`[fx]="RCM_fx_VAR:orog,sftlaf,sftlf,sfturf,sftgif"` entry once they do.

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

## 6. Submission Scripts (`scripts` folder)

Only 3 scripts now, each replacing what used to be a whole family of
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

## 7. Archiving

After processing each varset, `run_out_generic.sh` unconditionally submits
`run_cp_generic.sh` for the same varset — matching the original scripts'
unconditional call to their `run_cp_<varset>.sh` sibling. It reads the same
`VARSETS[<varset>]` entry, flattens every group into one plain variable
list, and archives each `<var>_*.nc` to ECFS and a remote server. There's
nothing varset-specific to write — adding a new varset to
`config/varsets.sh` automatically gets archiving for free.

`plev_uava`, `zlev_uava0`, and `zlev_uava1` only *process* the v-component
(their `VARSETS[]` entries list `va*` variables), but the underlying
programs produce matching `u*` files too — so their archive step needs two
calls, not one. `CP_EXTRA[]` in `config/varsets.sh` names the "u" companion
varset to also archive (`plev_ua`, `zlev_ua0`, `zlev_ua1` respectively —
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

Every script requires `ROOT_DIR` to already be set in your environment,
checked at startup with a clear error if it isn't. **Scripts do not try to
auto-detect their own location from `$0`/`dirname`** — `sbatch` copies the
submitted script into a spool directory before running it, so `$0` at
runtime often doesn't point at this repo at all, especially once you submit
from somewhere else (e.g. `$SCRATCH/Analysis`) than where the code lives.

Export it once, e.g. in `~/.bashrc` so every future shell (and every batch
job, since Slurm inherits your environment by default) has it:

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

1. Check out this repo somewhere permanent — that's `ROOT_DIR`.
2. `export ROOT_DIR=/path/to/it` (add to `~/.bashrc`).
3. Fill in `header_ini/` and confirm `header/` (§2, §3).
4. `cp env.site.sh.example env.site.sh` and fill it in (§4).
5. Check `config/varsets.sh` covers the variables you need (§5) —
   `MIGRATION.md` maps old script names to varsets if you're coming from
   the previous per-variable-script layout.
6. Fill in `--account`/`--mail-user`/`--chdir` at the top of all 3 scripts
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
sbatch $ROOT_DIR/scripts/run_Analysis_v2.sh <datebeg> <dateend> <year_lim>

# Example: process 2001, then keep chaining year by year until 2005
sbatch $ROOT_DIR/scripts/run_Analysis_v2.sh 20010101 20011231 2005
```

### Extracting a single variable/varset

Check `config/varsets.sh` (or `MIGRATION.md` if you're looking for where an
old `run_out_<x>.sh` script went) to find which varset covers your
variable, then submit it directly — no file to modify:

```bash
sbatch --job-name=wrf-soil --time=12:00:00 \
       --output=wrf-soil.%j.out --error=wrf-soil.%j.out \
       $ROOT_DIR/scripts/run_out_generic.sh 19900101 19901231 2000 soil
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
sbatch --job-name=wrf-out --time=18:00:00 \
       --output=wrf-out.%j.out --error=wrf-out.%j.out \
       $ROOT_DIR/scripts/run_out_generic.sh 20010101 20051231 2000 out
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

- The compile step (Fortran module + subs + program) still runs once per
  variable, per year, exactly as in the original — including recompiling
  the same fixed program (e.g. `RCM_sfc_rad.f90`, `RCM_plev_ta.f90`)
  repeatedly for each variable/level in its group. Harmless, just matches
  the original's per-variable compile pattern.
- Scripts use `#!/bin/bash` explicitly (not `#!/bin/sh`) since they rely on
  bash associative arrays — the originals already used bash-only syntax
  under a `#!/bin/sh` shebang, which only worked if `/bin/sh` happened to be
  bash on your system. This makes that assumption explicit and portable.
- `TIME[]` values for `out` and `plev_ta` were confirmed against the live
  scripts; the rest are carried over/estimated and worth a check — `rad`
  and `snw` especially, since what they cover just changed.
- `CP_TIME[]` (archive-step walltime) is only confirmed for `out`
  (`20:00:00`, from the live `run_cp_out.sh`); everything else falls back
  to `DEFAULT_CP_TIME` (`04:00:00`) until you've checked real numbers.
- `plev_va`, `zlev_va0`, `zlev_va1` are disabled on purpose (old/superseded
  versions) — commented out at the bottom of `config/varsets.sh` rather
  than deleted, so they're easy to compare against or resurrect.
  `plev_ua`, `zlev_ua0`, `zlev_ua1` are also disabled *for processing*, but
  reactivated as archive-only `VARSETS[]` entries (see §7, above).

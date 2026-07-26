# CORDEX_Cmor — WRF/CORDEX post-processing pipeline

[![shellcheck](https://github.com/ritamcardoso/CORDEX_Cmor/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/ritamcardoso/CORDEX_Cmor/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Runs the `RCM_*.f90` post-processing programs (`f90_src/`) over a set of
years, grouped into "varsets" (`out`, `soil`, `rad`, `plev_ta`, ...). This
used to be two dozen near-duplicate submission scripts differing in
variable list, program-naming pattern, and chaining behaviour; it's now one
generic script driven by a small config file.

## Layout

```
f90_src/                    <- Fortran source (RCM_sfc_*.f90, RCM_plev_*.f90, RCM_zlev_*.f90, ...)
header/                     <- per-variable namelist headers
header_ini/                 <- per-domain grid/global config
config/varsets.sh           <- variable lists, program naming, walltimes, chaining, submit order
env.site.sh.example         <- template for YOUR paths/modules (copy -> env.site.sh)
scripts/run_out_generic.sh  <- the one worker script (replaces all run_out_*.sh)
scripts/run_cp_generic.sh   <- the one archive/copy script (replaces all run_cp_*.sh)
scripts/run_Analysis_v2.sh  <- orchestrator, submits every varset in ORDER
MIGRATION.md                <- old filename -> new varset name, verified against the live repo
```

`env.site.sh` is gitignored — it's the one file that differs per
user/machine. `--account`/`--mail-user`/`--chdir` are plain `#SBATCH` lines
at the top of each of the 3 scripts above — with only 3 scripts total,
that's simpler than maintaining a shared-options file/parser. Fill them in
directly in all three (they're identical in each).

## Fortran program naming

Each varset in `config/varsets.sh` maps to one or more variable "groups",
each with its own program pattern:

```
[out]="RCM_sfc_VAR:tas,ts,th,..."                 # RCM_sfc_tas.f90, RCM_sfc_ts.f90, ...
[cloud]="RCM_sfc_cloud:clh,clm,cll,clt"            # always RCM_sfc_cloud.f90
[plev_ta]="RCM_plev_ta:ta1000,ta925,...,ta30"      # always RCM_plev_ta.f90, all 16 levels
[zlev_uava0]="RCM_zlev_uava:va50m,va150m,va100m"   # always RCM_zlev_uava.f90
```

`VAR` in a program pattern gets substituted with the current variable; a
pattern without `VAR` is used as-is for every variable in that group. Turns
out **per-variable programs are the exception, not the rule** once you
include plev/zlev:

- **sfc**: mostly per-variable (`RCM_sfc_<var>`) — `out`, `soil`, `snw`,
  `tau`, `wpth`. But `cloud` → always `RCM_sfc_cloud`, `wxtrm` → always
  `RCM_sfc_xtrm`, and `rad` → always `RCM_sfc_rad` (14 radiation variables,
  one fixed program — this replaced the old `acum` varset, which mixed
  `pr`/`prc`/`sund` into the same job; those three now live in `snw`
  instead).
- **plev**: always one fixed program per family, covering every pressure
  level in one program (`RCM_plev_ta.f90` handles `ta1000`...`ta30`).
- **zlev**: same — one fixed program per family, covering every height
  level (`RCM_zlev_ua.f90` handles `ua50m`, `ua100m`, `ua150m`, ...).

Note: `plev_uava` and `zlev_uava0`/`zlev_uava1` process `va*` variables
through a program literally named `RCM_plev_uava` / `RCM_zlev_uava` — that's
how the source names those programs, not a bug in this config.

`run_out_fx.sh` (`orog`, `sftlaf`, `sftlf`, `sfturf`, `sftgif` →
`RCM_fx_<var>`) is intentionally **not** wired into `config/varsets.sh` yet —
those `RCM_fx_*.f90` sources don't exist in `f90_src/` in this repo yet, so
including it would just fail at compile time. Add it once they do.

## Archiving

After processing each varset, `run_out_generic.sh` unconditionally submits
`run_cp_generic.sh` for the same varset — matching the original scripts'
unconditional call to their `run_cp_<varset>.sh` sibling (see `run_out.sh`
→ `run_cp_out.sh`). It reads the same `VARSETS[<varset>]` entry, flattens
every group into one plain variable list, and archives each `<var>_*.nc` to
ECFS and a remote server. There's nothing varset-specific to write — adding
a new varset to `config/varsets.sh` automatically gets archiving for free.

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

## Chaining behaviour

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

## Where the code lives

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

## First-time setup

```bash
export ROOT_DIR=$HPCPERM/CORDEX/scenarios/Analysis   # add to ~/.bashrc too
cp env.site.sh.example env.site.sh
# edit env.site.sh with your paths / modules
```

Then set `--account`/`--mail-user`/`--chdir` directly in the `#SBATCH`
header of all 3 scripts (`scripts/run_out_generic.sh`,
`scripts/run_cp_generic.sh`, `scripts/run_Analysis_v2.sh`) — they're
identical in each, just edit all three.

## Running

```bash
cd $SCRATCH/Analysis   # or wherever you want to submit from — doesn't have to be ROOT_DIR
sbatch $ROOT_DIR/scripts/run_Analysis_v2.sh 19900101 19901231 2000
```

This submits every varset listed in `ORDER` (config/varsets.sh), 120s apart,
each as `run_out_generic.sh <datebeg> <dateend> <year_lim> <varset>`.

You can also submit a single varset by hand:

```bash
sbatch --job-name=wrf-soil --time=12:00:00 \
       --output=wrf-soil.%j.out --error=wrf-soil.%j.out \
       $ROOT_DIR/scripts/run_out_generic.sh 19900101 19901231 2000 soil
```

## Adding/changing a variable set

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

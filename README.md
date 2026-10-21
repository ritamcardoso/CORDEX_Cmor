# Guide to CMORising WRF Output

[![shellcheck](https://github.com/ritamcardoso/CORDEX_Cmor/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/ritamcardoso/CORDEX_Cmor/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

These Fortran programs and accompanying scripts extract and convert WRF
output into CMOR-compliant format on a yearly basis, and archive the result
to ECFS and a remote server.

This used to be two dozen near-duplicate submission scripts, one per
variable group, each with its own hardcoded paths and variable list. It's
now 3 generic job scripts, submitted through `submit.sh` and driven by:

- **`env.site.sh`** — your site settings (Slurm, compiler, modules; §4);
- **`experiments/<name>/`** — one folder per experiment: its grids, paths
  and ini files (§2);
- **`config/varsets.sh`** — the variable sets, time limits and chaining (§5).

§0 is the quick start; §1–§11 go through each part in detail.

## 0. Job Submission Instructions

### First-time setup checklist

1. Check out this repo somewhere permanent — that's `ROOT_DIR` (found
   automatically by `submit.sh`, nothing to export; §9).
2. Fill in your experiment's folder in `experiments/` — its `.sh` file
   and ini files (§2) — and confirm `header/` (§3).
3. `cp env.site.sh.example env.site.sh` and fill it in (§4): at least
   `JOB_ACCOUNT`, `JOB_MAIL_USER`, `JOB_CHDIR`, and `EXPERIMENT` set to
   your experiment folder's name. Nothing to edit in `scripts/`.
4. Check `config/varsets.sh` covers the variables you need (§5), and run
   `bash tools/lint_varsets.sh` (§11) after any change to it.

### Quick start: `run.sh`

Once the setup above is done, start everything with one command:

```bash
cd $ROOT_DIR                         # the repo (or a symlink to run.sh)
./run.sh fpsurb 2015 2020            # every stream, 2015 to 2020, one year per job
./run.sh fpsurb 2015                 # 2015 only
./run.sh fpsurb 2015 2020 soil fx    # only these varsets, each on its own
./run.sh -n fpsurb 2015 2020         # dry run: check and show, submit nothing
./run.sh -a fpsurb 2015 2020         # afterwards: daily and monthly files (§11)
```

`run.sh <experiment> <first year> [<last year>] [<varset> ...]` works out
the dates and `year_lim`, checks the setup and calls `submit.sh` for you.
It checks `env.site.sh`, the experiment folder and its ini files, and the
varset names, and warns if there are no `wrfout` files for the first year.
It lists every problem and submits nothing until they are fixed.

* **Without varsets** it submits `run_analysis.sh`: every stream in
  `ORDER`, chained year by year (as in *Standard submission* below).
* **With varsets** each one runs on its own, using
  `config/varsets_single.sh`: it processes a year, submits its archive job
  and resubmits itself for the next year, up to the last year. You don't
  need to copy anything over `config/varsets.sh`. The layout is passed to
  every job of the loop, so queued and running jobs of other loops are not
  affected. Add `-c` to let them hand over to their stream instead
  (`config/varsets.sh`).

The time limits, memory and other job settings still come from
`config/varsets.sh` (or `varsets_single.sh`) and `env.site.sh`, as below.
The rest of this section describes what `run.sh` does underneath, and how
to submit by hand (e.g. several years in one job).

### Standard submission

`run_analysis.sh` is the main controller — it submits every varset in
`ORDER` (`config/varsets.sh`), each of which manages its own dependencies
via `NEXT[]`, submitting some archival/follow-up tasks as soon as its own
processing finishes. `year_lim` is the last year to process: each stream
stops after it (§8).

```bash
cd $SCRATCH/Analysis   # anywhere with a symlink to submit.sh (§9), or call it by its path

# Syntax
./submit.sh run_analysis.sh <datebeg> <dateend> <year_lim>

# Example: process 2001, then keep chaining year by year until 2005
./submit.sh run_analysis.sh 20010101 20011231 2005
```

Always submit through `submit.sh` (not plain `sbatch`): it's what applies
the `env.site.sh` job settings (§6).

### Extracting a single variable/varset

Check `config/varsets.sh` to find which varset covers your variable, then
submit it directly:

```bash
# soil for 1990 only
./submit.sh run_out_generic.sh 19900101 19901231 1990 soil
```

`submit.sh` takes the job name, time limit, memory and log files from
`config/varsets.sh`, exactly as for `run_analysis.sh` (§6). To change one
for this submission, add it before the script name, written as
`--option=value`, e.g. `./submit.sh --time=02:00:00 run_out_generic.sh ...`.

With the normal `config/varsets.sh`, most varsets hand over to the next
varset of their stream when they finish (soil → out2, …), so do this with
`config/varsets_single.sh` in place (see the next section). There, a
varset only resubmits itself, and setting `year_lim` to the same year
makes it stop after that year. `fx` has no `NEXT[]` entry in either file,
so it never chains.

### Extracting several years of one varset

**Take care with `NEXT[]`.** With the normal `config/varsets.sh`, a
finished job hands over to the next varset in its stream (`NEXT[]`, §8),
so submitting one varset on its own starts the other varsets of its
stream too, year by year until `year_lim`.

To run varsets on their own, use **`config/varsets_single.sh`**. It has
the same varsets, time limits and memory, but every varset loops on
itself, like `zlev_uava0` and `zlev_uava1` do: it processes one year,
submits its archive (`cp-*`) job, and resubmits itself for the next year,
stopping after `year_lim`.

`run.sh` does this for you (see *Quick start*). By hand, set
`CMOR_VARSETS=varsets_single.sh` when you submit: `submit.sh` passes it to
the job and the job passes it on to the jobs it submits, so the whole loop
uses that file:

```bash
CMOR_VARSETS=varsets_single.sh ./submit.sh run_out_generic.sh 20010101 20011231 2005 soil
```

Without `CMOR_VARSETS` the scripts read `config/varsets.sh`, so you can
also switch by copying a layout over it. `config/` holds both:

* `varsets_chain.sh` — the normal chained streams (§8), a saved copy of
  what `varsets.sh` holds by default;
* `varsets_single.sh` — every varset loops on itself.

```bash
cd $ROOT_DIR    # the repo
cp config/varsets_single.sh config/varsets.sh   # every varset loops on itself
```

and to go back to the normal streams:

```bash
cp config/varsets_chain.sh config/varsets.sh
```

Every job reads `config/varsets.sh` when it **starts**, so only switch when
no chained jobs are queued or running — otherwise those jobs pick up the
new `NEXT[]` at their next link.

Then submit the varset for its first year, with the last year as
`year_lim`:

```bash
# soil, 2001 to 2005, one year per job
./submit.sh run_out_generic.sh 20010101 20011231 2005 soil
```

Or process all the years **in one job**: give the end year as `dateend`
and set `year_lim` to that same end year, so the job doesn't resubmit
itself afterwards:

```bash
# soil, 2001 to 2005, all in one job (~5h per year)
./submit.sh --time=32:00:00 run_out_generic.sh 20010101 20051231 2005 soil
```

The `TIME[]` limits in `config/varsets.sh` are for **one** year, so give
the job a longer `--time` yourself (about the number of years × the
one-year time, plus a margin), within the queue's maximum walltime — split
long periods into a few jobs. If `year_lim` is later than `dateend`, the
job resubmits itself for the next block of the same length (2006–2010
here, cut off at `year_lim`).

`run_analysis.sh` works with `varsets_single.sh` too, but its `ORDER` is
empty by default: each entry starts its own loop and they all run at
once, so uncomment one of the two batches in the file (10 varsets each,
within the 11-processor limit), or list only the varsets you need.

## 1. Directory Setup

Place all files and subfolders into a single root directory, maintaining
the provided folder structure:

```
f90_src/       <- Fortran source (RCM_sfc_*.f90, RCM_plev_*.f90, RCM_zlev_*.f90, ...)
header/        <- per-variable namelist headers
experiments/   <- one folder per experiment: <name>.sh (grids, paths) + its ini files (§2, experiments/README.md)
config/        <- varsets.sh: the active variables/programs/scheduling, the only one the scripts read (§5, config/README.md);
                  varsets_chain.sh: saved copy of the chained streams (§8); varsets_single.sh: every varset loops on itself (§0)
scripts/       <- the 3 generic job scripts (+ load_experiment.sh, which they source; §6)
.github/       <- ShellCheck run on GitHub
run.sh         <- the simple way to start: ./run.sh <experiment> <first year> [<last year>] [<varset> ...] (§0)
submit.sh      <- submits every job (§6, §9)
tools/         <- helper scripts (§11): report_walltimes.sh, lint_varsets.sh, merge_soil_monthly.sh,
                  check_and_found_var.sh, check_archive.sh + variables.txt;
                  ncrepack-cordex (+ its LICENSE), run on every new file (§6);
                  aggregate.sh + aggregation_table.txt: daily and monthly files (§11)
env.site.sh.example  <- copy to env.site.sh and fill in (§4)
LICENSE, README.md
```

This root directory is referred to as `ROOT_DIR` everywhere below — see
[§9, Where the code lives](#9-where-the-code-lives-root_dir) for how the
scripts find it. It does not need to be, and generally shouldn't be, the
same directory you submit jobs from.

## 2. Experiments (`experiments/<name>/`)

Everything that's specific to one experiment lives in **one folder**,
`experiments/<name>/` — the folder name is the experiment name:

```
experiments/
  fpsurb/
    fpsurb.sh                       <- grids and paths (below)
    fpsurb_EUR-12_d01.ini           <- grid/domain setup, one per grid
    fpsurb_global_EUR-12_d01.ini    <- global attributes, one per grid
    fpsurb_PARIS-3_d02.ini
    fpsurb_global_PARIS-3_d02.ini
  cordex/
    cordex.sh
    cordex_EUR-12_d01.ini
    cordex_global_EUR-12_d01.ini
```

`EXPERIMENT` in `env.site.sh` (§4) picks the folder.

### The experiment file (`<name>.sh`)

* **`ROOT_RUN_DIR`** — scratch working directory; each varset works in
  `${ROOT_RUN_DIR}/<varset>`. The experiment file creates it (`mkdir -p`).
* **`run[]`** — the grids to process (`[d01]=1`, `[d02]=1`, ...; only the
  keys matter). Comment a line out to skip that grid.
* Per grid, keyed the same way as `run[]`:
  * **`DOMAIN_ID[]`** — CORDEX domain ID (`EUR-12`, `PARIS-3`), which picks
    that grid's two ini files: `<name>_<DOMAIN_ID>_<grid>.ini` and
    `<name>_global_<DOMAIN_ID>_<grid>.ini`.
  * **`OUTPUT_WRF[]`** — raw WRF output location.
  * **`OUTPUT_DIR[]`** — where that grid's CMORised output is written.
    **Each grid needs its own directory**: the archive step sends
    everything in it to that grid's archive paths. The experiment file
    creates the output folder of every grid in `run[]` (`mkdir -p`).
  * **`ECFS_BASE[]`**, **`REMOTE_BASE[]`** — that grid's ECFS and remote
    archive paths.

Every processing job loops over the grids in `run[]` in order (`d01`,
then `d02`, ...), and every archive job archives each grid's output to its
own paths. A grid in `run[]` that's missing any of these entries or one of
its two ini files, or two grids sharing an `OUTPUT_DIR`, stops the job at
the start with a message saying what's wrong.

Enabling a second grid makes **every** job do both, so raise `TIME[]` in
`config/varsets.sh` accordingly, and remember both grids' output stays on
disk — the archive step (§7) copies it but doesn't delete it.

### The ini files (one pair per grid)

See [`experiments/README.md`](experiments/README.md) for the full details.

* **Domain & Geography:** in `<name>_<DOMAIN_ID>_<grid>.ini` (e.g.
  `cordex_EUR-12_d01.ini`), update the domain of the output file (and
  the matching `geog` name).
  * **Directories:** not set in the ini files — they hold
    `_OUTPUT_WRF_`/`_OUTPUT_DIR_` placeholders that `run_out_generic.sh`
    fills in from that grid's `OUTPUT_WRF[]`/`OUTPUT_DIR[]` in `<name>.sh`.
  * **Naming Conventions:** change the general domain and model names used
    for the CMORised variables (`dom`/`outdom`, same file).
* **Global Properties:** edit `<name>_global_<DOMAIN_ID>_<grid>.ini`
  (e.g. `cordex_global_EUR-12_d01.ini`) — the global characteristics of
  the variables, tailored to your experiment. Both files of a grid must
  use the same `<DOMAIN_ID>` as its `DOMAIN_ID[]` entry. The values must
  also match the official CORDEX-CMIP6 controlled vocabulary — see
  [`experiments/README.md`](experiments/README.md) and
  [WCRP-CORDEX/cordex-cmip6-cv](https://github.com/WCRP-CORDEX/cordex-cmip6-cv)
  for the valid values.
  * **`title`** is written automatically from the entries of this file:
    `<institution_id> <source_id> downscaling of <driving_source_id>
    <experiment_id> for <project_id> <domain_id>`, e.g. *IDL-FCUL WRF451Q
    downscaling of MPI-ESM1-2-HR ssp370 for CORDEX-CMIP6 EUR-12*. To use
    your own, add a `title = '...'` line.
  * **`references`**: the page or publication describing the simulation
    (cordex: euro-cordex-cmip6, fpsurb: fps-urb-rcc, lucas: fps-lucas). It is
    left out of the files if the line is missing.

### Switching or adding an experiment

To run a different experiment, change `EXPERIMENT` in `env.site.sh`, or
override it for one run:

```bash
EXPERIMENT=cordex ./submit.sh run_analysis.sh 20010101 20011231 2005
```

`submit.sh` passes the experiment on to every job of that run, so a chain
keeps the experiment it was started with even if you change
`env.site.sh` while it's running.

To add an experiment, copy an existing folder, rename the folder and the
files inside it to the new name (e.g. `cp -r experiments/cordex
experiments/ssp585`, then rename `cordex*` to `ssp585*` inside), and fill
them in.

## 3. Headers (`header` folder)

The `header` folder contains the specific namelist header for each
variable (`header_<var>`). Under normal circumstances you do not need to
modify these files — the scripts assemble a full namelist per run by
concatenating the relevant `header_<var>` onto the experiment's grid ini file
(see `run_out_generic.sh`'s processing loop).

`header_sftlaf`, `header_sfturf` and the land-cover fractions of
`RCM_fx_landuse` / `RCM_sfc_landuse` (`treeFrac`, `urbanFrac`, …) also set `area_type`
(`'lake_and_inland_sea'`, `'urban'`, `'tree'`, …): it becomes the scalar
coordinate `type` that the CORDEX tables require for these variables (in the
fx and the hourly files). Leave it
out for every other variable.

## 4. Site Environment (`env.site.sh`)

This is the one file that's genuinely different per user/machine. Together
with your experiment's folder (§2), it's all you need to edit:

```bash
cp env.site.sh.example env.site.sh
# then edit it
```

* **Paths** — `PROG_DIR`, `HEADER_DIR` (both derived from `ROOT_DIR`, so
  you don't repeat yourself).
* **Modules** — `MODULES`, built from the versions `intel_v`, `hdf5_v`,
  `netcdf_v`, `hpx_v`. Every job loads it from here (`run_analysis.sh`,
  `run_out_generic.sh`, `run_cp_generic.sh`), so a module change is made
  once. Check the template's list against the modules your site provides
  (`module avail`). The commented `source ~/.bash_compile_wrf` line is the
  IDL-FCUL alternative — a personal file other users don't have.
* **Compiler/library versions** — `FC`, `FFLAGS`, and the NetCDF/HDF5
  include/lib paths. They come from `$NETCDF` / `$HDF5` when those are
  already set (as `~/.bash_compile_wrf` does), otherwise from
  `/usr/local/apps/<lib>/<version>/INTEL/<intel_dir_v>/HPCX/<hpx_dir_v>`.
  `intel_dir_v` and `hpx_dir_v` default to the module versions, but the
  folder names can be written differently (check with
  `ls /usr/local/apps/netcdf4-parallel/<netcdf_v>/INTEL/*/HPCX/`). If there is
  no `netcdf.mod` in the include folder, sourcing `env.site.sh` prints a
  warning (otherwise the compile fails with `error #7002 ... [NETCDF]`).
* **Experiment** — `EXPERIMENT`, the name of the experiment folder to use
  (`experiments/<name>/`, §2). Everything that differs per experiment or
  per domain lives there, not here.
* **Archive step settings** — `ARCHIVE`, `CP_MODULES`, `REMOTE_HOST`
  (see [§7, Archiving](#7-archiving)). The archive *paths* are per grid,
  in the experiment file. **`ARCHIVE` is `"off"` in the template**: the
  archive step (copying to ECMWF's ECFS and `scp` to a remote server) is
  specific to the IDL-FCUL setup, so turn it on only if you use the same
  arrangement. An older `env.site.sh` without an `ARCHIVE` line keeps
  archiving on.
* **Repacking** — `REPACK` (`"on"` by default, also when the line is
  missing): every file is repacked with `tools/ncrepack-cordex` as soon as it
  is written (§6), so no repacking is needed afterwards. Needs `h5repack`,
  `h5stat` and `h5dump` on the `PATH` (from the HDF5 module in `MODULES`);
  if one is missing the job stops at the start. `"off"` leaves the files as
  the programs write them.

* **Slurm job settings** — `JOB_QOS`, `JOB_NODES`, `JOB_NTASKS`,
  `JOB_HINT`, `JOB_ACCOUNT`, `JOB_MAIL_TYPE`, `JOB_MAIL_USER`,
  `JOB_CHDIR`. `submit.sh` passes them to every job as `--qos` /
  `--nodes` / `--ntasks` / `--hint` / `--account` / `--mail-type` /
  `--mail-user` / `--chdir` (see
  [§6](#6-submission-scripts-scripts-folder)). Leave one empty (`""`) to
  not pass that flag. A line missing from `env.site.sh` altogether uses
  the default: `nf`, `1`, `1`, `nomultithread`, no account, `ALL`, no
  mail user, no chdir.

`env.site.sh` is gitignored — it never gets committed. Lines an older
`env.site.sh` may still have for per-experiment settings (`run`,
`DOMAIN_ID`, `OUTPUT_DIR`, `OUTPUT_WRF`, `CP_RUN_DIR`, `ECFS_BASE`,
`REMOTE_BASE`, `HEADER_INI_DIR`) are ignored — the experiment folder's
values are used instead.

## 5. Variable Sets (`config/varsets.sh`)

It's the single place that defines every variable group ("varset"), what Fortran program(s) process it, how
long to schedule it for, and how it chains to other varsets. You will
rarely need to touch anything else once this is set up.

**[`config/README.md`](config/README.md) covers this file in full**,
including the current stream layout, the basis of every time limit, how
to turn chaining off, and how to cut it down to only the variables you
need. Variable names follow the
[CORDEX-CMIP6 data request](https://github.com/WCRP-CORDEX/data-request-table),
and the Fortran programs referenced in each entry correspond to
[CORDEX-WRF-community/WRF-CMORizer](https://github.com/CORDEX-WRF-community/WRF-CMORizer/tree/main) —
see `config/README.md` before adding a variable this repo doesn't have a
program for yet.

**FPS-URB-RCC urban variables (`urban` varset).** The 13 hourly urban variables of the
[FPS-URB-RCC data request](https://github.com/impetus4change/T32-CPRCM/blob/main/data-request-fpsurbrcc.csv)
come from the BEP+BEM output of WRF (`sf_urban_physics = 3`). `RCM_sfc_urban.f90`
writes the urban temperatures `tasroof`, `taspav`, `tasgree`, `tascan`, `tsroof`,
`tspav` and `tsgree` (the WRF field is `wrfvar` of the header);
`RCM_sfc_hurscan.f90`, `RCM_sfc_husscan.f90` and `RCM_sfc_sfcWindcan.f90` the
canyon humidities and wind; `RCM_sfc_urb.f90` writes `tasblue` and `tsblue` over
water cells (`LANDMASK = 0`), and `tsskin` everywhere. Urban cells are those where WRF
runs the urban scheme (`urban_cell` in `shared_subs_v2.f90`): `FRC_URB2D > 0` and
`LU_INDEX` an urban category of the land-use table of the geo_em file (`MMINLU`):
13 or the LCZ classes 51–61 for MODIS, 1 or 31–41 for USGS. All are
instantaneous (`time: point`), as in the T32 CMOR tables. Only the fpsurb run has
these fields, so `urban` is not in `ORDER`; run it on its own, e.g.
`./run.sh fpsurb 2000 2010 urban`. Its daily and monthly means are in
`tools/aggregation_table.txt`. The field capacity `mrsofc` (fx) is written by
the `soil` varset (`RCM_sfc_mrsofc.f90`), from the dominant soil category of the
geo_em file and the STAS field capacities of `SOILPARM.TBL`.

**Noah-MP land-surface variables (`lsm` varset) and land cover (`fx`).**
`RCM_sfc_lsmflx.f90` writes the hourly means `evspsblsoi`, `evspsblveg` and
`tran` (kg m-2 s-1): the mean of the instantaneous rates `EDIR`, `ECAN` and
`ETRAN` (mm s-1) at the start and end of each hour. `RCM_sfc_lsm.f90` writes the instantaneous `lai`
(`LAI`), `vegFrac` (`FVEG` in %) and `alb` (`ALBEDO`). Sea points are missing,
except for `alb`. These fields must be in the wrfout files (Noah-MP output, as in
LUCAS), so `lsm` is not in `ORDER`; run it on its own, e.g.
`./run.sh lucas 2000 2010 lsm`. The `fx` varset now also writes, with
`RCM_fx_landuse.f90`, `treeFrac`, `shrubFrac`, `grassFrac`, `cropFrac`,
`baresoilFrac`, `urbanFrac` and `cnc` (their vegetated sum, % of the grid cell),
from `LANDUSEF` of the first wrfout file of the job year, and with
`RCM_fx_lcvr.f90` the dominant land-cover class `lcvr` (`LU_INDEX` of the geo_em
file, the LUCAS name). The grouping of the land-use categories (MODIS/IGBP and
USGS weight tables, with the LCZ urban classes) is in `landuse_field`
(`shared_subs_v2.f90`); edit it there. Like the other fx files, an existing file
is kept, so the fx fractions are those of the first year processed.

**Hourly land cover for land-use change runs (`landuse` varset).** For LUCAS,
where the land-use maps change during the run, `RCM_sfc_landuse.f90` writes the
seven fractions and `lcvr` every hour (instantaneous, `time: point`), from `LANDUSEF` /
`LU_INDEX` of each wrfout file, so they follow the maps whenever they change and
can be used as a mask at any time step. It is not in `ORDER`; run it with
`./run.sh lucas 2000 2010 landuse`. Daily and monthly means of the fractions are in
`tools/aggregation_table.txt`.

### Fortran program naming

Each varset maps to one or more variable "groups", each with its own
program pattern:

```
[out1]="RCM_sfc_VAR:tas,ts,th,..."                # RCM_sfc_tas.f90, RCM_sfc_ts.f90, ...
[cloud1]="RCM_sfc_cloud:clh,clm"                  # always RCM_sfc_cloud.f90
[plev_ta]="RCM_plev_ta:ta1000,ta925,...,ta30"      # always RCM_plev_ta.f90, all 16 levels
[zlev_uava0]="RCM_zlev_uava:va50m,va100m,va150m"   # always RCM_zlev_uava.f90
```

`VAR` in a program pattern gets substituted with the current variable; a
pattern without `VAR` is used as-is for every variable in that group:

- **sfc**: mostly per-variable (`RCM_sfc_<var>`) — `out1`, `out2`, `soil`,
  `snw`, `wpth*`. But `cloud*` → always `RCM_sfc_cloud`, `wxtrm` → always
  `RCM_sfc_xtrm`, and `rad` → always `RCM_sfc_rad`.
- **plev** / **zlev**: one fixed program per family (`RCM_plev_ta.f90`
  handles `ta1000` ... `ta30`).

Either way, `run_out_generic.sh` runs the program **once per variable (or
level)**, and each run is an independent pass over the year's WRF files.
So any varset can be split between variables or levels — a single
variable or level is the smallest unit.

The one name that matters: the varset that runs `RCM_sfc_xtrm` must be
called **`wxtrm`** (or `testex`) — `run_out_generic.sh` reads the
`wrfxtrm` files instead of `wrfout` only for those names.

`plev_uava` and `zlev_uava0`/`zlev_uava1` list only `va*` variables, but
their programs (`RCM_plev_uava` / `RCM_zlev_uava`) write both `ua` and `va`
— see §7 for how the `ua` files are archived.

The fixed (time-independent) fields are the **`fx`** varset,
`[fx]="RCM_fx_VAR:orog,sftlaf,sftlf,sfturf,sftgif"` (one `RCM_fx_<var>`
program each). It isn't in `ORDER` or any stream: submit it once on its
own, as in §0 "Extracting a single variable/varset".

### Scheduling and chaining

Alongside `VARSETS[]`, the same file holds:

* **`TIME[]`** — walltime to request for each varset's processing job.
* **`MEM[]`** / **`DEFAULT_MEM`** — memory for each varset's processing
  job (8G unless listed).
* **`CP_TIME[]`** / **`DEFAULT_CP_TIME`** — walltime for each varset's
  archive job.
* **`ORDER`** — the varsets `run_analysis.sh` submits directly (see
  [§0](#0-job-submission-instructions)).
* **`NEXT[]`** and **`ADVANCE_YEAR[]`** — see
  [§8, Chaining behaviour](#8-chaining-behaviour).
* **`CP_EXTRA[]`** — see [§7, Archiving](#7-archiving).

See [§10, Adding/changing a variable set](#10-addingchanging-a-variable-set)
for how to extend this file.

## 6. Submission Scripts (`scripts` folder)

Only 3 job scripts now, each replacing what used to be a whole family of
per-variable files. Every job is submitted through `submit.sh` (in the repo
root), and the two job scripts that need the experiment load it with
`scripts/load_experiment.sh`.

| Script | Replaces | Role |
|---|---|---|
| `run_out_generic.sh` | all `run_out_*.sh` | processes one varset for a year range, then submits the archive job and (if configured) the next varset in the chain |
| `run_cp_generic.sh` | all `run_cp_*.sh` | archives one varset's output to ECFS + remote |
| `run_analysis.sh` | itself (orchestrator; `--time` from `ANALYSIS_TIME` in `config/varsets.sh`, 45 min) | submits every varset in `ORDER`, 120s apart |

**Slurm settings:** all set once in `env.site.sh` (`JOB_QOS`,
`JOB_NODES`, `JOB_NTASKS`, `JOB_HINT`, `JOB_ACCOUNT`, `JOB_MAIL_TYPE`,
`JOB_MAIL_USER`, `JOB_CHDIR` — §4); the scripts have no `#SBATCH` lines.
`#SBATCH` lines are read by `sbatch` before a script starts, so a script
can't load them from a file itself; instead every job is submitted through
`submit.sh`, which reads these values from `env.site.sh` and passes them
on the `sbatch` command line. That includes the jobs the scripts submit
for each other, so **submit your first job through `submit.sh` too**
(§0) — a job started with plain `sbatch` won't get these settings.
Per-job settings come from `config/varsets.sh`, also through
`submit.sh` (step 5 below).

The 3 scripts are fully generic — you should not need to edit them.

**What `submit.sh` does**, for every job:

1. Works out `ROOT_DIR` from its own location (symlinks resolved).
2. Splits its arguments into `sbatch` options (anything starting with
   `-`) and the script name plus that script's arguments.
3. Reads `env.site.sh` in a subshell and keeps only the `JOB_*` values
   and `EXPERIMENT` — so the modules and compiler settings in
   `env.site.sh` don't leak into the job's environment.
4. Checks the experiment folder exists, then passes `ROOT_DIR`, the
   experiment (as `CMOR_EXPERIMENT`, §2) and the varset file (as
   `CMOR_VARSETS`, default `varsets.sh`, a file in `config/`) to the job.
5. For `run_out_generic.sh` and `run_cp_generic.sh`, looks up the varset
   (their 4th argument) in that varset file and adds its per-job flags:

   | Flag | Processing job (`run_out_generic.sh`) | Archive job (`run_cp_generic.sh`) |
   |---|---|---|
   | `--job-name` | `wrf-<varset>` | `cp-<varset>` |
   | `--time` | `TIME[<varset>]` | `CP_TIME[<varset>]`, else `DEFAULT_CP_TIME` |
   | `--mem` | `MEM[<varset>]`, else `DEFAULT_MEM` | — |
   | `--output`, `--error` | `wrf-<varset>.%j.out` | `cp-<varset>.%j.out` |

   An unknown varset stops with an error.
6. Calls `sbatch` with these flags first and your own flags after,
   skipping any flag you already gave, so your flags win. Write your
   flags as `--option=value` (a value after a space would be read as the
   script name).

**What a processing job (`run_out_generic.sh`) does:**

1. Loads `env.site.sh`, the experiment (`scripts/load_experiment.sh`,
   which also checks it — §2) and `config/varsets.sh`.
2. For each year, then each grid, then each group and variable of the
   varset: builds the namelist (the grid's ini file with its placeholders
   filled in, plus `header/header_<var>`), compiles the program and runs it
   in `${ROOT_RUN_DIR}/<varset>`. **If a compile or a program run fails,
   the job stops there** with an error naming the program, variable, grid
   and year: no archive job and no next job are submitted, and the job
   shows as FAILED, so a broken stream stops instead of carrying on with
   missing output.
   **With `REPACK="on"`** (the default) each program's new files are then
   repacked in place with `tools/ncrepack-cordex` — a copy of
   [ncrepack-cordex](https://github.com/WCRP-CORDEX/ncrepack-cordex)
   v0.2 (BSD 3-Clause, `tools/ncrepack-cordex.LICENSE`): `time` and
   `time_bnds` in one chunk, the data variable rechunked (6 time steps for
   `1hr`/`mon`, 4 for `6hr`), shuffle + deflate 1 + Fletcher32, and the
   internal metadata collated at the start of the file. The values and
   attributes are not changed. Only the files written by that run are
   repacked (other jobs write into the same folder at the same time); a
   failed repack stops the job like a failed program, and leaves the file
   as written. The archive job therefore copies repacked files. Check them
   with `ncrepack-cordex-check` (Python; `pip install pyfive packaging`, or
   the conda install in the ncrepack-cordex README).
3. If `ARCHIVE="on"`, submits the archive job (§7), and a second one for
   its `CP_EXTRA[]` companion.
4. Submits the next varset of its stream (§8).

**Arguments:** `run_out_generic.sh` and `run_cp_generic.sh` take
`<datebeg> <dateend> <year_lim> <varset>`; `run_analysis.sh` takes
`<datebeg> <dateend> <year_lim>` and submits every `ORDER` entry, 120 s
apart.

## 7. Archiving

**Archiving is optional.** It copies the CMORised files to ECMWF's tape
archive (ECFS, with `emkdir`/`ecp`) and to a remote server (`scp`) — the
setup used at IDL-FCUL, which other sites may not have. Turn it on or off
with `ARCHIVE` in `env.site.sh` (§4): `"on"` or `"off"` (the template's
default is `"off"`; an `env.site.sh` without the line keeps it on). With it
off, the output simply stays in each grid's `OUTPUT_DIR`, and chaining
(§8) is unaffected.

With `ARCHIVE="on"`, after processing each varset `run_out_generic.sh`
submits `run_cp_generic.sh` for the same varset. It reads the same
`VARSETS[<varset>]` entry, flattens every group into one plain variable
list, and archives **that job's years** of each variable (files
`<var>_..._<yyyy>...`, from `datebeg`/`dateend`; plus time-independent
`<var>_..._fx.nc` files) to ECFS and a remote server — earlier years
aren't sent again. There's nothing varset-specific to write — adding a
new varset to `config/varsets.sh` automatically gets archiving for free.

**Archived files are never deleted** — they stay in `OUTPUT_DIR`, since a
copy can fail or be incomplete. If a variable has no files for those
years, or an `ecp`/`scp` fails, the job reports it, carries on with the
other variables, and ends as FAILED so you can see it and resubmit:

```bash
./submit.sh run_cp_generic.sh <datebeg> <dateend> <year_lim> <varset>
```

The `scp` to `REMOTE_HOST` is retried: up to `COPY_ATTEMPTS` times per
variable (default 3), `COPY_WAIT` seconds apart (default 300), both set in
`env.site.sh`. Only a variable that fails every attempt counts as failed.
If the server is down, each variable can wait
`(COPY_ATTEMPTS-1) × COPY_WAIT` seconds before giving up, so for varsets
with many variables keep `CP_TIME[]` long enough (or lower the two values).

`plev_uava`, `zlev_uava0` and `zlev_uava1` list only their `va*`
variables, but their programs also write the matching `ua*` files, so
their archive step needs two jobs. `CP_EXTRA[]` in `config/varsets.sh`
names the companion varset that lists the `ua*` variables (`plev_ua`,
`zlev_ua0`, `zlev_ua1` respectively). Those are archive-only entries:
never processed, not in `ORDER` or `NEXT[]`. When `CP_EXTRA[$VARSET]` is
set, `run_out_generic.sh` submits a second `run_cp_generic.sh` job for
that companion.

The archive step's modules and remote host (which differ from the
compile/run environment) live in `env.site.sh`: `CP_MODULES`,
`REMOTE_HOST`. The output directory and the ECFS/remote archive paths are
per grid, in the experiment file (`OUTPUT_DIR[]`, `ECFS_BASE[]`,
`REMOTE_BASE[]` — §2): each grid is archived from its own output directory
to its own paths.

## 8. Chaining behaviour

Each varset's year loop resubmits another varset when it finishes (`NEXT[]`
in `config/varsets.sh`). The varsets are arranged in 10 parallel
"streams", balanced on measured run times so each takes about the same
time per model year (~21h) — [`config/README.md`](config/README.md)
has the full table:

- **2-hop chains**: `plev_uava→wxtrm`, `cloud1→wpth1`, `cloud2→wpth3`,
  `plev_zg→snw`, `plev_ta→wpth2`, `rad→out1`
- **3-hop chains**: `plev_wa→zlev_hus→zlev_ta`, `plev_hus→soil→out2`
- **Self-loops** (resubmits itself each year): `zlev_uava0`, `zlev_uava1`

`ORDER` holds the first link of each stream. Exactly one link per stream
advances `yeari`/`yearf` (`ADVANCE_YEAR[]`) — the last one before the
chain returns to its first link — so each stream advances one year per
full round-trip, not per hop.

`year_lim` decides when a stream stops:

- the **advancing** link only resubmits if the last year it processed
  (`yearf`, from `dateend`) is before `year_lim`, so it runs `year_lim`
  once and then stops instead of starting `year_lim + 1`. It resubmits for
  the next block of the same length (one year for normal jobs), cut off at
  `year_lim`;
- the **other** links resubmit while their first year (`yeari`, from
  `datebeg`) is `<= year_lim`, with the same dates, so they always run
  `year_lim` too — the advancing link is the one that ends the stream.

To rebalance (e.g. after run times change), run `report_walltimes.sh` and
move variables between varsets: every program runs once per variable or
level, so any varset can be split.

## 9. Where the code lives (`ROOT_DIR`)

This repo can live anywhere (e.g. `$HPCPERM/CORDEX/scenarios/Analysis`)
— it does **not** need to be checked out into your submission/scratch
directory. There's nothing to export: `submit.sh` works out `ROOT_DIR`
from its own location and passes it to every job it submits (and the
scripts submit their follow-up jobs through it too).

To submit from another directory (e.g. `$SCRATCH/Analysis`), call
`submit.sh` by its path, or put a symlink to it there:

```bash
cd $SCRATCH/Analysis
ln -s $HPCPERM/CORDEX/scenarios/Analysis/submit.sh .
./submit.sh run_analysis.sh 20010101 20011231 2005
```

The symlink is resolved, so `ROOT_DIR` still points at the repo. (The
scripts themselves can't find the repo from `$0`, because Slurm runs a
spooled copy of them — which is why they must be submitted through
`submit.sh` rather than plain `sbatch`.)

This is completely independent of:
- **where you submit from** — anywhere, e.g. `$SCRATCH/Analysis` (set
  `JOB_CHDIR` in `env.site.sh` if you want job logs to land there)
- **`ROOT_RUN_DIR`** (experiment file) — scratch working directory used
  while processing (e.g. `$SCRATCH/ssp370`)
- **`OUTPUT_DIR[]`** (experiment file) — where each grid's finished output
  files land before archiving (e.g. `$SCRATCH/ssp370/output`)

## 10. Adding/changing a variable set

Edit `config/varsets.sh` — and make the same change in
`config/varsets_chain.sh` and `config/varsets_single.sh`, so switching
layouts (§0) doesn't lose it:

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

Add it to `ORDER` if it should be submitted directly by `run_analysis.sh`,
to `NEXT[]` if some varset should chain into (or from) it, and to
`ADVANCE_YEAR[]=1` if it should advance the year before resubmitting.
If its jobs need more than the default 8G of memory, add a `MEM[]` entry
(e.g. `[my_new_set]="16G"`); otherwise it uses `DEFAULT_MEM`.

## 11. Helper scripts

All in `tools/`; run them from the repository folder (`bash tools/<script>`)
or through a symlink.

### `report_walltimes.sh` — longest run per varset

Pulls real run times from Slurm's accounting (`sacct`) for the jobs this
pipeline has submitted (`wrf-<varset>` / `cp-<varset>`), so you can check
the limits in `config/varsets.sh` against real runs. It only reports; it
never edits anything.

Run it **directly on an HPC login node, not through `sbatch`** (it can be
a symlink, e.g. in `$SCRATCH` — the config is found next to the real file):

```bash
bash tools/report_walltimes.sh --since 2026-08-01
```

| Option | Meaning | Default |
|---|---|---|
| `--since` | `sacct` start time, e.g. `2026-08-01` or `now-30days` | `now-30days` |
| `--margin` | percent added to the longest run for the suggestion | `25` |
| `--clusters` | `sacct -M` value, e.g. `ac` or `ac,ad` | `all` |

It searches **all** clusters by default: ECMWF's Atos HPC is split into
several clusters (aa/ab/ac/ad), and `sacct` otherwise only sees the login
node's own. It uses top-level jobs only (`sacct -X`).

Per job name it prints the number of completed runs, the longest one
(`MaxElapsed`), a suggested limit (longest + margin), the limit set in
`config/varsets.sh` (`TIME[]` for `wrf-*`, `CP_TIME[]`/`DEFAULT_CP_TIME`
for `cp-*`) and the clusters used. Notes flag **LIMIT TOO SHORT** (the
longest run already exceeded the limit), **tight** (less than the margin
to spare), and jobs that only timed out, ran out of memory, failed or were
cancelled. A job that hit its time limit needed *more* than its limit, so
it is flagged rather than measured.

### `lint_varsets.sh` — check `config/varsets.sh`

A quick consistency check, no Slurm or compiler needed:

```bash
bash tools/lint_varsets.sh     # exit status 1 if any error
```

It reports an **error** if:

1. a processed varset (in `ORDER` or a `NEXT[]` target) has no `TIME[]`
   entry — archive-only entries are exempt;
2. a `NEXT[]` entry names, or belongs to, a varset that doesn't exist;
3. a `CP_EXTRA[]` entry names a varset that doesn't exist;
4. an `ADVANCE_YEAR[]`, `CP_TIME[]` or `MEM[]` key isn't a varset (typo);
5. an `ORDER` entry isn't a varset;
6. a program has no `f90_src/<program>.f90`, or a variable has no
   `header/header_<var>`;

and a **warning** for every varset without its own `CP_TIME[]` (it uses
`DEFAULT_CP_TIME`).

### `check_and_found_var.sh` — which variables were extracted, per year

Checks the output folders for every variable in `variables.txt` (the 172
CORDEX variables, fixed fields excluded; one per line, `#` comments
allowed), without reading the extraction logs. Run it **directly on a
login node** (it only lists files); it can be a symlink, e.g. in `$SCRATCH`
— `variables.txt` is found next to the real file, and the repository
(`env.site.sh`, `config/`, `scripts/`) in the folder above `tools/`:

```bash
ln -s $HPCPERM/CORDEX_Cmor/tools/check_and_found_var.sh $SCRATCH/
cd $SCRATCH
./check_and_found_var.sh 2015 2020                    # experiment from env.site.sh
EXPERIMENT=lucas ./check_and_found_var.sh 2015 2020   # another experiment
```

The output folders come from the experiment: `OUTPUT_DIR` of every grid in
`run[]` (`experiments/<name>/<name>.sh`), each checked on its own. A
variable counts as extracted for a year if any of its files covers that
year — old and new file names, one or several years per file (the old
daily names ending on 1 January of the next year count for their own year
only); fx files are not checked.

Per grid it writes to `${ROOT_RUN_DIR}/check_<grid>/`:

| File | Content |
|---|---|
| `found_<year>.txt` | variables extracted for that year |
| `missing_<year>.txt` | `<varset> <variable>` for every variable not extracted — the varset to resubmit, from `config/varsets.sh` (the running varsets, `ORDER` and their `NEXT` links, are preferred; several are comma-separated) |
| `missing_summary.txt` | each missing variable with the years it is missing |

| Option | Meaning |
|---|---|
| `-v <file>` | another variable list (default: `tools/variables.txt`) |
| `-o <dir>` | another folder for the reports |
| `-r <dir>` | the repository folder, if the script is kept elsewhere |

### `check_archive.sh` — were the files archived correctly?

Checks, per year, that every variable in `variables.txt` reached the
archive intact: the remote server (`REMOTE_HOST:REMOTE_BASE/<var>/raw`,
default) and/or ECFS (`ECFS_BASE/<var>`). Like `check_and_found_var.sh`,
it takes everything from the experiment and `env.site.sh` (grids,
`OUTPUT_DIR`, `REMOTE_BASE`, `ECFS_BASE`, `REMOTE_HOST`), can be a symlink,
and runs on a login node:

```bash
ln -s $HPCPERM/CORDEX_Cmor/tools/check_archive.sh $SCRATCH/
cd $SCRATCH
./check_archive.sh 2015 2020              # remote server
./check_archive.sh -d both 2015 2020      # remote server and ECFS
EXPERIMENT=lucas ./check_archive.sh 2015 2020
```

The remote folder is listed with one `ssh` (as for `scp`, a key must let
you in without a password); ECFS with `els`. A copy is correct when it has
the same size as the original in `OUTPUT_DIR` (never deleted by the
archive job). If the original is gone (e.g. purged from `$SCRATCH`), the
copy must not be empty and must be within `-t` percent (default 5) of the
previous year's copy.

Per grid and archive it writes to `${ROOT_RUN_DIR}/check_archive_<grid>/<remote|ecfs>/`:

| File | Content |
|---|---|
| `found_<year>.txt` | variables archived correctly |
| `missing_<year>.txt` | `<varset> <variable>` with no archived file for that year |
| `size_mismatch_<year>.txt` | `<varset> <variable>  # <file>: <sizes>` — empty, truncated or suspicious copies |
| `problems_summary.txt` | every year with problems, and its missing and wrong-size lines |
| `found_<year>.sh`, `missing_<year>.sh`, `size_mismatch_<year>.sh` | the same three lists as bash arrays, ready to `source`: `declare -a var=("hfls" "pr" )` |

To redo a varset's copy, resubmit its archive job:
`./submit.sh run_cp_generic.sh <datebeg> <dateend> <year_lim> <varset>`.
The script exits with status 1 if anything is missing or wrong.

| Option | Meaning |
|---|---|
| `-d remote\|ecfs\|both` | archive(s) to check (default `remote`) |
| `-t <pct>` | size tolerance against the previous year when the original is gone (default 5) |
| `-v <file>`, `-o <dir>`, `-r <dir>` | as for `check_and_found_var.sh` |

### `tools/aggregate.sh` — daily and monthly files

Makes the **daily** files from the sub-daily ones (1hr, 3hr or 6hr) and the
**monthly** files from the daily values, for every variable of the CORDEX-CMIP6
`day` and `mon` tables. It writes them next to the other files of each grid
(`OUTPUT_DIR`). Run it as a job:

```bash
./run.sh -a fpsurb 2015 2020                    # every variable that has files
./run.sh -a fpsurb 2015 2020 tas pr             # only these variables
./submit.sh --ntasks=8 --mem=32G run_aggregate.sh 2015 2020   # 8 variables at a time
```

or directly on a login node for a few variables:
`tools/aggregate.sh [-f day|mon|both] [-j <n>] [-n] <first year> [<last year>] [<variable> ...]`
(`-n`: dry run, shows the sources and files).

* **How:** with NCO (`ncra`), which keeps the file exactly as the programs
  write it (grid mapping, cell corners, axis bounds, `type`, global
  attributes). The method of each variable is taken from the CMOR tables
  (`tools/aggregation_table.txt`):
  * **Daily:** the mean, maximum, minimum or sum of the 24 (1hr), 8 (3hr) or 4
    (6hr) values of each day. `prhmax` is the daily maximum of the hourly `pr`.
    Variables already written as daily files (e.g. `tasmax`, `tasmin`,
    `sfcWindmax` from `wrfxtrm`) are taken from those files; `-s` recomputes
    them from the sub-daily files instead.
  * **Monthly:** the mean of the daily values. A plain `time: minimum` /
    `maximum` in the `mon` table means the minimum / maximum of the days.
    Incomplete months (e.g. the last days missing) are left out.
* **Time:** set to the archive specifications, whatever the time stamps of the
  input (instantaneous at 00:00, or interval data at hh:30). Daily values are at
  12:00, with `time_bnds` from 00:00 to 00:00. Monthly values are in the middle
  of the month (e.g. 16 Jan 12:00, 15 Feb 00:00), with bounds at 00:00 of the
  first day of the month and of the next month.
* **Files:** daily files hold **5 years** (years ending in 1–5 and 6–0), and
  monthly files **10 years** (1–0); the first and last files are shorter. The
  file covering a year asked for is (re)built whole, from every year of that
  period that has data. The daily or monthly files it replaces (e.g. the yearly
  `tasmax` files) are moved to `<OUTPUT_DIR>/superseded/`, never deleted.
* **Metadata:** `frequency`, `cell_methods` and `long_name` from the `day`/`mon`
  table, new `tracking_id` and `creation_date`, and a new first `history` line
  (`...found in table CORDEX-CMIP6_day.`) above the lines of the input. Files
  are NetCDF-4 classic, deflate 1 with shuffle, repacked with
  `tools/ncrepack-cordex` (unless `REPACK="off"`).
* **Job settings:** `AGGREGATE_TIME` in `config/varsets.sh` (24 h). NCO comes
  from `MODULES`, else `AGG_MODULES` in `env.site.sh` (default `nco`).
  Temporary files go to the node's `$TMPDIR`. A year of hourly EUR-12 data takes
  about 2 minutes per variable, with little memory.
* The daily and monthly files are not archived automatically: resubmit the
  archive jobs (`run_cp_generic.sh`) of the varsets afterwards. The archive
  job picks files by their **first** year, so include the first year of each
  5- or 10-year file (e.g. 2011 for `..._day_20110101-20151231.nc`).

### `tools/ncrepack-cordex` — repack existing files

The jobs repack new files themselves (§6). For files written before that, or
by `merge_soil_monthly.sh`, repack them in place (needs the HDF5 tools):

```bash
module load hdf5            # or the hdf5-parallel module of MODULES
tools/ncrepack-cordex -o $SCRATCH/output_d01/*.nc
```

Without `-o` a new `<file>_ncrepack` is written next to each file instead.

### `merge_soil_monthly.sh` — monthly soil files to one file per year

The soil programs (`RCM_sfc_tsl`, `RCM_sfc_mrsol`, `RCM_sfc_mrsfl`) now write
one 6hr file per year, as CORDEX-CMIP6 wants. The old monthly versions are
kept as `RCM_sfc_<var>_monthly.f90` (use `RCM_sfc_VAR_monthly` as the
program pattern in a varset to run them). This script joins monthly files
that were already produced into yearly ones:

```bash
module load nco
bash tools/merge_soil_monthly.sh -g experiments/cordex/cordex_global_EUR-12_d01.ini \
     -r $SCRATCH/output_d01/orog_<...>_fx.nc \
     -o $SCRATCH/soil_yearly  $SCRATCH/output_d01
```

For each variable and year it needs all 12 monthly files
(`<var>_..._6hr_YYYYMM0100-YYYYMMDDhh.nc`), joins them in time order with
`ncrcat`, and writes `<var>_..._6hr_YYYY01010000-YYYY12311800.nc`. By
default it also brings the metadata up to the current write routines
(values from the global ini given with `-g`): global attributes,
`tracking_id`, `history`, the `rotated_latitude_longitude` grid mapping,
time in days with `calendar = "proleptic_gregorian"` and `units_metadata`
(and no `time_bnds`, as these are instantaneous variables), the soil
coordinate `depth`/`depth_bnds` at the layer middles, NetCDF-4 classic
with deflate level 1. The cell corners (`vertices_lon`/`vertices_lat`)
and axis bounds can't be rebuilt from the monthly files, so they are
copied, with `lon`/`lat`, from a reference file given with `-r`: any file
of the same grid written by the current code, e.g. the orog fx file. The
result is the same as running the new yearly program.

| Option | Meaning |
|---|---|
| `-g <ini>` | experiment global ini (needed unless `-m`) |
| `-r <file>` | reference file of the same grid from the current code (needed unless `-m`) |
| `-o <dir>` | output folder (default: the input folder) |
| `-v "tsl mrsol mrsfl"` | variables to merge |
| `-y "2015 2016"` | only these years |
| `-m` | merge only, metadata kept as in the monthly files |
| `-p` | merge a year with fewer than 12 months |
| `-f` | overwrite an existing yearly file |

The monthly files are never changed or deleted; check the yearly files
and remove the monthly ones yourself.

## Notes / things to double check before first real run

- The compile step (Fortran module + subs + program) still runs once per
  variable, per year, exactly as in the original — including recompiling
  the same fixed program (e.g. `RCM_sfc_rad.f90`, `RCM_plev_ta.f90`)
  repeatedly for each variable/level in its group. Harmless, just matches
  the original's per-variable compile pattern.
- Scripts use `#!/bin/bash` explicitly (not `#!/bin/sh`) since they rely on
  bash associative arrays.
- Several `TIME[]` values are estimates (out1, out2, zlev_uava0/1 and the
  split varsets — see [`config/README.md`](config/README.md)). Run
  `report_walltimes.sh` after the first full year and adjust.
- `CP_TIME[]`: the longest archive job measured is `cp-out1` at 1h31;
  every varset currently uses 20h.
- `plev_ua`, `zlev_ua0`, `zlev_ua1` are archive-only `VARSETS[]` entries
  (§7); `cloud`, `tau`, `zlev_va0`, `zlev_va1` are kept for manual runs
  only.

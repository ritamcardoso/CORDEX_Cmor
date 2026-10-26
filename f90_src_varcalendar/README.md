# f90_src_varcalendar — programs for any simulation period

The programs of `f90_src` process whole calendar years: months `imonth`..`nmonths`, every day, every hour. They need every wrfout file of the year, and the accumulated fields (pr, fluxes, radiation …) also need the first file of the next year. The programs here process only the time steps inside the **simulation period** set in the grid ini:

```
sim_start = '2015-01-01_00'      ! the first wrfout file (UTC)
sim_end   = '2100-12-31_18'      ! the last wrfout file
```

The period can start and end at any hour, and last from a few hours to many years. Both keys must be set explicitly. When they are, `run_out_generic.sh` builds the programs from this folder (see below).

## What the programs write

Each year `yeari`..`yearf` of a job is one **chunk**: the part of that year inside the simulation period. It is written to one file per variable, as before. The dates in the file name are the first and the last time of the chunk, e.g. `…_1hr_210001010000-210012311800.nc`.

| Kind of variable | Time steps of a chunk |
|---|---|
| Instantaneous (tas, ps …) | every file from `sim_start` (or 1 Jan 00 UTC) to `sim_end` (or 31 Dec 23 UTC) |
| Read every `ostep` hours (pressure levels, soil layers) | the multiples of `ostep` hours (from 00 UTC) inside the period |
| Interval values from two files (accumulated fields, interval means) | the intervals [t, t+1 h] that start in the year; the last one ends at `sim_end` (the next year's first file is read only if it is inside the period) |
| Resampled to 3hr, 6hr or day (`outstep` > 1 with a mean or sum) | only **complete** windows: a day or 6 hours with a missing time step at the start or the end of the period is not written |
| Daily statistics (`RCM_sfc_xtrm`, `RCM_sfc_wsgsmax`) | only days whose 24 hours are inside the period |

The daily and monthly files of `tools/aggregate.sh` follow the same rule: incomplete days and months are left out.

A year outside the period writes nothing. So does a chunk with no complete window, e.g. a daily variable of a 5-hour run (the log says so). `run_out_generic.sh` also limits the years of a job, and of the chain (`year_lim`), to the years of `sim_start`..`sim_end`.

`imonth`, `iday`, `ihour` and `nmonths` of the ini are not used by these programs.

## Which programs are here

- **Made by `tools/make_varcalendar.py`** from the programs of `f90_src` (and `parallel/` from those of `f90_src_parallel`). The conversion is mechanical: the year/month/day/hour loops become one loop over the files of the chunk, and the rest of each program is unchanged:

  ```fortran
  do vc_year = yeari, yearf
    if (.not. time_chunk(vc_year, <step>, <interval>)) cycle   ! the part of the year in sim_start..sim_end
    year = vc_year
    ...                                    ! allocations with ntime, as before
    loop_h: do vc_ifl = 1, vc_nfiles
      call set_time_step(vc_ifl)           ! year, month, day, hour, ayear ... ahour, infile
      ...                                  ! the body of the hour loop of f90_src
    enddo loop_h
    call write_output                      ! one file per year (chunk)
  enddo
  ```

  `time_chunk`, `set_time_step` and `sim_period` are in `f90_src/shared_io_subs.f90`, and their variables are in `f90_src/datvar_s.f90`. Both modules are shared with `f90_src`; the programs there are unchanged.
- **By hand:** `RCM_sfc_xtrm.f90` (monthly wrfxtrm files, one record a day) and `RCM_sfc_wsgsmax.f90` (one value a day from 24 hourly files).
- **Not here:**
  - programs without a time loop (`RCM_fx_*`, `RCM_sfc_mrsofc`), which are built from `f90_src`;
  - the reference copies that no varset runs (`RCM_sfc_*_monthly`, `RCM_sfc_xtrm_daily`).

The OpenMP copies are in `parallel/`. With `OMP_FLAG` set, `run_out_generic.sh` builds a program from there when it has a copy, as it does with `f90_src_parallel`.

## Keeping them in step with f90_src

Change the program in `f90_src` (and in `f90_src_parallel`), not here, then regenerate and check:

```bash
tools/make_varcalendar.py           # rewrites f90_src_varcalendar (not the two programs by hand)
tools/make_varcalendar.py --check   # exit 1 if a program here is out of step with f90_src
```

A program that no longer follows the loop template of `f90_src` is reported and left out. Convert it by hand and add it to `HAND` in the script. A change to `RCM_sfc_xtrm` or `RCM_sfc_wsgsmax` must be made in both copies.

## Checks done

On test data (10×10 points, 2015), 98 program/variable cases covering every kind of variable. Cases outside a varset were included too: clh, clt and plev_va.

- **Whole year:** with `sim_start = '2015-01-01_00'` and `sim_end = '2016-01-01_00'`, the output is bit-for-bit the same as from `f90_src`: data, time, bounds, attributes and file names.
- **Partial periods:**

  | Period | Shows |
  |---|---|
  | 2015-11-20_00 to 2015-12-31_18 | ends at 18 UTC |
  | 2015-03-15_07 to 2015-04-02_13 | starts mid-month at 07 UTC |
  | 2015-06-10_00 to 2015-06-12_00 | 2 days |
  | 2015-06-10_03 to 2015-06-10_08 | 5 hours: no 6-hourly or daily window is complete, so those 17 variables write no file |
  | 2015-12-25_00 to 2016-01-01_00, `yearf = 2016` | a 2-year job: the 2016 chunk holds only the 00 UTC value of the instantaneous variables |

  In all of them:
  - every value written is identical to the same time step of the whole-year run, with the same bounds;
  - the time steps written are exactly those inside the period;
  - only incomplete windows are left out.
- **`tools/aggregate.sh`** on hourly tas and pr ending 31 Dec 18 UTC: daily files from 20 Nov to 30 Dec, equal to the mean of the 24 hours. The incomplete 31 Dec, November and December are left out. Starting at 07 UTC, the first day is the next one.

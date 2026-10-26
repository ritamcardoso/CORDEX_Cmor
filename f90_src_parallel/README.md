# f90_src_parallel — OpenMP versions (optional)

These programs are the same as in `f90_src`, with only OpenMP directives added, so that the columns of the grid are shared out among several cores:

| Program | Parallel part | Varsets |
|---|---|---|
| `RCM_sfc_cape.f90` | `calc_cape` (rows `iy`; the per-column work variables of `datvar_s` are private) | `cape` |
| `RCM_sfc_cloud.f90` | `calc_clt`, `calc_clh`, `calc_clm`, `calc_cll` | `cloud1`, `cloud2`, `cloud` |
| `RCM_sfc_clouds.f90` | the same four routines, all in one run | `clouds` |
| `RCM_sfc_wpth.f90` | `calc_wpth` | `wpth` |
| `RCM_sfc_clivi.f90`, `RCM_sfc_prw.f90`, `RCM_sfc_clwvi.f90`, `RCM_sfc_clgvi.f90`, `RCM_sfc_clhvi.f90` | `calc_prw` | `wpth1` … `wpth4` |

Compiled without the OpenMP flag, the directives are comments and each program is the serial program of `f90_src`. The modules (`datvar_s.f90`, `humidity_subs.f90`, `shared_subs_v2.f90`) are the ones in `f90_src`. Every variable is still declared there.

## Use

OpenMP is off by default.

1. In `env.site.sh`, set `OMP_FLAG` to `-qopenmp` (ifort/ifx) or `-fopenmp` (gfortran).
2. `config/varsets.sh` → `CPUS[varset]` sets the number of threads. With `OMP_FLAG` set:
   - `submit.sh` asks Slurm for `--cpus-per-task=CPUS[varset]`;
   - `run_out_generic.sh` builds the programs above from this folder with `OMP_FLAG`, and runs them with `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`. The job log says so (`OpenMP: … thread(s)`).

   Other programs, and varsets without `CPUS`, are unchanged.
3. Check that the QoS allows the number of cores you ask for (for example `nf` on Atos), and remember that cores are charged to the account.

## What to expect

On the test data, the results are bit-for-bit the same as the serial programs, with 1 and 2 threads. Only the calculation runs in parallel. Reading the wrfout files and writing the output stay serial, so the gain is limited by what share of the run is calculation:

| Program | Calculation share of the run (test data) | Gain |
|---|---|---|
| cape | ~50 % | up to ~2× faster (11.4 s → 8.9 s with 2 threads) |
| cloud | ~20–25 % | ≤ 25 % |
| clouds (four in one run) | larger (one reading, four calculations) | more than cloud |
| water paths | ~0 % (reading only) | none |

For the water paths, and partly for the clouds, it would be faster to read the wrfout files once for several variables (as `RCM_sfc_cape` does for cin, li and lcl) than to add threads.

The variable-calendar versions of these programs (simulation period `sim_start`..`sim_end` in the grid ini) are in `f90_src_varcalendar/parallel`, made by `tools/make_varcalendar.py`.

## Keeping them in step

After changing one of these programs in `f90_src`, make the same change here and run:

    tools/check_parallel_sync.sh

It prints any difference other than the OpenMP lines. Then run `tools/make_varcalendar.py`, which remakes the variable-calendar versions, in `f90_src_varcalendar` and `f90_src_varcalendar/parallel`.

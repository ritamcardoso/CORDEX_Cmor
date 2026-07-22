Here is a revised, polished version of your documentation. I’ve fixed the typos (like "characterisitcs," "cemorised," and "submited"), improved the formatting for readability using Markdown, and restructured the instructions so they are much easier for a user to scan and follow.

---

# Guide to CMORising WRF Output

These Fortran programs and accompanying scripts extract and convert WRF output into CMOR-compliant format on a yearly basis.

## 1. Directory Setup

Place all files and subfolders into a single root directory, ensuring you maintain the provided folder structure.

## 2. Configuration (`header_ini`)

Update the grid characteristics in the `header_ini` file to match your specific simulation:

* **Directories:** Update `dir` to point to the location of your raw `wrfout` files, and `dir2` to the destination folder for the CMORised output.
* **Domain & Geography:** Update the domain of the `wrfout` file (ensure you also update the `geog` name to match).
* **Naming Conventions:** Change the general domain and model names used for the CMORised variables.
* **Global Properties:** Edit `global_EUR-11_d01.ini`. This file contains the global characteristics of the variables and must be tailored to your specific experiment.

## 3. Headers (`header` folder)

The `header` folder contains the specific headers for each variable. Under normal circumstances, you do not need to modify these files.

## 4. Submission Scripts (`scripts` folder)

The `scripts` folder contains all job submission scripts. The primary script is `run_Analysis_v2.sh`, which sequentially calls individual variable scripts (e.g., `RCM_run*.sh`).

### Script Configuration

Before running, open the scripts and update the variables in the **"To Change"** sections:

* **Environment & Paths:** Update the environment variables to match your system. If you kept the default structure, simply set `ROOT_DIR` to your main folder path. The scripts expect programs in `PROG_DIR=$ROOT_DIR/f90_src`, headers in `HEADER_DIR=$ROOT_DIR/header`, and configs in `HEADER_INI_DIR=$ROOT_DIR/header_ini`.
* **Run Directory:** Update `RUN_DIR` to your execution folder (and ensure the `mkdir` command matches this path). Each script generates a generic namelist for its variables and creates its own folder—**do not change this behavior**.
* **Domains:** Update the `run=("d01")` array with the number of domains in your simulation. You can add as many as you need, provided you have a corresponding `header_ini` file for each.
* **Variables:** Define the specific variables you want to extract. (Refer to `summary_list.txt` for a full list of variables and the scripts that process them).
* **Slurm Options:** Update `slurm_common.opts` with your HPC account details, email address, and execution paths.

---

## Job Submission Instructions

You can submit all scripts using the main controller, `run_Analysis_v2.sh`. This script manages the dependencies, submitting some extraction tasks in parallel and queuing others to start once the initial batch finishes.

**Standard Submission:**
The `year_lim` parameter acts as a failsafe, stopping the extraction loop at a specific year so an error doesn't run indefinitely.

# Syntax
sbatch --file=slurm_common.opts run_Analysis_v2.sh ${datebeg} ${dateend} ${year_lim}

# Example: Run sequentially until the end of 2005
sbatch --file=slurm_common.opts run_Analysis_v2.sh 2001 2001 2005


**Alternative Execution Methods:**

* **Extracting a single variable:** Check `summary_list.txt` to find the specific script that handles your target variable. Modify that individual script and submit it directly.
* **Extracting multiple years in a single submission:** Set your start date, end date, and year limit to encompass the whole period:

sbatch --file=slurm_common.opts run_Analysis_v2.sh 2001 2005 2005

*Note: If you do this, you **must** comment out all lines below `# Call loop batch to advance time and call the next run script` in all `run_out*.sh` files to prevent the script from looping over itself.*

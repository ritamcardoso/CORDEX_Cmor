Fortran programs to cmorise WRF output, and their running scripts

How to run:
1) Put all the files and sub folders into a folder using the same structure;

2) In header_ini change the grid characterisitcs acording to your simulation.
  2.1) Change the location of your wrfout files in "dir" and the location of the cemorised output in "dir2".     2.2) Change the domain of the wrfout file (don't forget to change the "geog" name as well"
  2.3) Change the general name of the cemorised variables
  2.4) global_EUR-11_d01.ini is a file with the global characteristics of the variables. Should be changed according to the experiment

3) The header folder contains the headers of each variable. There shouldn't be a need to change

4) The scripts folder contains the submission scripts. There are 2 typs of scripts, a main script called RCM_run.... wher all of the environment, and the variables ara declareded, and a loop script were the previous script is resubmited and the variales are stored.
  4.1) The environment variables and paths should be updated according to the users configuration
  4.2) The section "To Change" has the paths to the folders were the programs (PROG_DIR); to the headers (HEADER_DIR and HEADER_INI_DIR) are and the location were the fortran executable and datvars.mod are.
  4.4) The section "To Change" has the number of domains (run=("d01")) chang ccording to the number of doamis in yuor run.
   4.5) The section "To Change" also has the name of the variables that are going to extract. A full list of variables and the scripts which run the is in the summarry_list.txt
   4.6) The scripts are submitted by adding the initial year of the variable extration, the final year and the final year of the loop
   Submit as;
   sbatch run_out_plev_hus.f90 2000 2001 2002

5) THe fortran programs extract each variable on an yearly basis:
   

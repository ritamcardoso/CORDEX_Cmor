Fortran programs to cmorise WRF output, and their running scripts
The fortran programs extract each variable on an yearly basis

How to run:
1) Put all the files and sub folders into a folder using the same structure;

2) In header_ini change the grid characterisitcs acording to your simulation.
  2.1) Change the location of your wrfout files in "dir" and the location of the cemorised output in "dir2".     
  2.2) Change the domain of the wrfout file (don't forget to change the "geog" name as well)
  2.3) Change the general name of the domain and model of the cemorised variables
  2.4) global_EUR-11_d01.ini is a file with the global characteristics of the variables. Should be changed according to the experiment

3) The header folder contains the headers of each variable. There shouldn't be a need to change

4) The scripts folder contains the submission scripts. There are is a main script called RCM_run.... where all of the environment, and the variables ara declared, see the sequence in run_Analysis_v2.sh.
  4.1) The environment variables and paths should be updated according to the users configuration
  4.2) The section "To Change" has the paths to the folders, if you have the same structure you only need to change ROOT_DIR to the path of the folder where you placed the programs. The fortran programs should be (PROG_DIR=ROOT_dir/f90_src); the headers (HEADER_DIR==ROOT_dir/header and HEADER_INI_DIR==ROOT_dir/header_ini). 
  4.3) The program is run in RUN_DIR, change to your run folder (don't forget to change the mkdir dir line to the same folder). Each script has each own folder, keep this since the script builds a namelist with a generic name for each variable.  
  4.4) The section "To Change" has the number of domains (run=("d01")) change according to the number of domains in your run. You can add as many as you like, you just need to have the header_ini files for each domain
   4.5) The section "To Change" also has the name of the variables that are going to extract. A full list of variables and the scripts which run the is in the summary_list.txt
   4.6) All scripts can submitted using run_Analysis_v2.sh. It submits some of the scripts sequentially, so that variables are extracted in parallel. The scripts which weren't submited initially will be submited after the end of the first. The year_limit is used to loop the the extraction scripts until that year  
   Submit as;
    sbatch --file=slurm_common.opts run_Analysis_v2.sh ${datebeg} ${dateend} ${year_lim}

    e.g.  sbatch --file=slurm_common.opts run_Analysis_v2.sh 2001 2001 2005
    
    The scripts will be submitted sequentially until the end of 2005. The fortran programs extract each variable on an yearly basis
   
    If you need to extract just one variable look at the summary_list.txt to see which script submits that variable, change it accordingly and submit it

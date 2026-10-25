program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_mrsol.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_mrsol.f90 and rerun tools/make_varcalendar.py rather than this file.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use netcdf
!implicit none


! --- Read configuration using shared_subs subroutine

call init_cordex_environment
if (ostep < 1) ostep = wp_step       ! output step: outstep of the header (0 or missing: wp_step of the grid ini)

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

! --- Initialising grid and time counters
nz = 10
nzt = nz + 1
nhours = 24
!
!  Compute depth bounds
!
sdepth_bounds(1,1)=0.0
do is=1,nsoil-1
 sdepth_bounds(1,is+1)=sdepth_bounds(1,is)+sdepth(is)
enddo

sdepth_bounds(2,1)=0.1
do is=2,nsoil
 sdepth_bounds(2,is)=sdepth_bounds(2,is-1)+sdepth(is)
enddo


! --- Main Processing Loops ---
allocate(outvar_h(nlon, nlat, nsoil))
allocate(wrfv3D(nlon, nlat, nsoil))

it = 0
do vc_year = yeari, yearf
  ! the part of the year inside sim_start..sim_end (nothing to do if none)
  if (.not. time_chunk(vc_year, ostep, .false.)) cycle
  year = vc_year

  write(ayear, '(i4)') year

  ! Compute time length and allocate time sensitive variables
  if (mod(year, 4) == 0 .and. year /= 2100) then
      days = days2
      mydays = 366
  else
      days = days1
      mydays = 365
  endif
  ! One file per year: 4 records (6-hourly) per day, from imonth to nmonths
  issh=0
  allocate(ttime(ntime))
  allocate(bdtime(2, ntime))
  allocate(outvar_h_4d(nlon, nlat, nsoil, ntime))

!  ntime = mydays * nhours

!  if (ihour > 0) then
!    nhours=nhours-ihour+1
!    ntime = ntime - ihour + 1
!  endif

  ! Loop over months
  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        ! Read wrf var
        status = nf90_inq_varid(ncid, wrfvar, varid)
        call ncerror(status,'getting var id '//trim(wrfvar)//' in '//trim(infile))
        
        status=nf90_get_var(ncid,varid,wrfv3D,(/xoffset,yoffset,1/),(/nlon,nlat,nsoil/),(/1,1,1/))
        call ncerror(status,'reading '//trim(wrfvar)//' from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
! Compute variable
!
        call calc_mrsol

        issh = issh + 1

        bdtime(1, issh) = hours_since_ini(year, month, day, hour)

        bdtime(2, issh) = bdtime(1, issh) + ostep

        ttime(issh) = float(bdtime(1, issh))

        outvar_h_4d(:,:,:,issh)=outvar_h(:,:,:)

      enddo loop_h    ! end of the files of the chunk

  ! Write yearly output using shared subroutine
  write(ayearf, '(i4)') year
  write(ayeari, '(i4)') year

  call write_output
enddo

contains
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_mrsol
use datvar_s
!
do ix=1,nlon
  do iy=1,nlat
    if(landmask(ix,iy)>0.)then
      do is=1,nsoil
        outvar_h(ix,iy,is)=(sdepth(is)*wrfv3D(ix,iy,is))*1000.
      enddo
    else
      outvar_h(ix,iy,:)=huge_val
    endif
  enddo
enddo
!
end subroutine calc_mrsol
!
!----------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_subs
use netcdf

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)
ahourf = pad_int(hour-1, 2)

write(freq,'(i0,a)') ostep, 'hr'
frequency=trim(adjustl(freq))

! Create output filename based on metadata
outfile=trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
fnameout=trim(adjustl(outfile))

if (factor /= 0.) outvar_h_4d = outvar_h_4d * factor

call date_and_time(date,times,zone,values)
!
!Values    1    2    3      4       5     6      7       8
!Meaning Year Month Day Time_zone  Hour Minute Second  Millisecond
!                       offset(min)
!
write(yyyy,'(i4)')values(1)
mm = pad_int(values(2), 2)
dd = pad_int(values(3), 2)
hh = pad_int(values(5), 2)
mn = pad_int(values(6), 2)
ss = pad_int(values(7), 2)

cdate=yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
creationdate=cdate(1:len_trim(cdate))
!
! Call the shared NetCDF writer from shared_subs
!
call write_netcdf_rtime_soil(outvar_h_4d, ntime, ttime, bdtime)

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h_4d)

end subroutine write_output


end program read_wrfout

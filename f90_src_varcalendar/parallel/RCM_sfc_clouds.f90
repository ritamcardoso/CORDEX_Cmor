program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_clouds.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_clouds.f90 and rerun tools/make_varcalendar.py rather than this file.
!
! OpenMP version (f90_src_parallel): the columns of calc_clt, calc_clh, calc_clm and calc_cll run in parallel.
! Compile with the OpenMP flag (ifort -qopenmp, gfortran -fopenmp) and set OMP_NUM_THREADS;
! without the flag the directives are comments and it is the serial program of f90_src.
!
!
! RCM_sfc_clouds — the four cloud covers of one run (1hr, mean of consecutive hours), from
! one reading of CLDFRA, P, PB and PSFC per wrfout file:
!
!   clt  Total Cloud Cover Percentage   (vaid = clt in the header)
!   clh  High Level Cloud Fraction      p <= 440 hPa         (companion)
!   clm  Mid Level Cloud Fraction       440 < p <= 680 hPa   (companion)
!   cll  Low Level Cloud Fraction       p > 680 hPa          (companion)
!
! The same routines as RCM_sfc_cloud (random/maximum overlap, Sundqvist et al. 1989), so the
! results are identical to four runs of RCM_sfc_cloud. clt is written at the outstep of its
! header (1 hour); clh, clm and cll as 6-hour means (CORDEX-CMIP6 6hr; outstep = 6 in their
! headers), as RCM_sfc_cloud with their headers. clh, clm and cll are archived through
! the companion varset (CP_EXTRA); their metadata is set in write_output. The header's
! factor (100: fraction -> %) is applied to all four.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_io_subs
use netcdf
!implicit none


! --- Read configuration using shared_io_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

! --- Initialising grid and time counters
nzt = nz + 1
nhours = 24
ncomb = 4                       ! clt, clh, clm, cll


! --- Main Processing Loops ---
allocate(outvar_n(nlon, nlat, ncomb), outvar_n_i(nlon, nlat, ncomb))
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(wrfv3D(nlon, nlat, nz))
allocate(psf(nlon, nlat))

it = 0
!
do vc_year = yeari, yearf
  ! the part of the year inside sim_start..sim_end (nothing to do if none)
  if (.not. time_chunk(vc_year, 1, .true.)) cycle
  year = vc_year

  write(ayear, '(i4)') year
  !
!
  if(it == 0)then
    write(ayeari,'(i4)')year
    issh=0

    ! Compute time length and allocate time sensitive variables
    if (mod(year, 4) == 0 .and. year /= 2100) then
      days = days2
      mydays = 366
    else
      days = days1
      mydays = 365
    endif


    allocate(ttime(ntime))
    allocate(bdtime(2, ntime))
    allocate(outvar_h_4d(nlon, nlat, ntime, ncomb))
!    
  endif
  ! Loop over months
  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        ! Read Pressure and Target Variable

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status,'getting var id P in '//trim(infile))

        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading P from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status,'getting var id PB in '//trim(infile))

        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading PB from '//trim(infile))

        press = p + pb
!
        status=nf90_inq_varid(ncid,'PSFC',varid)
        call ncerror(status,'getting var id PSFC in '//trim(infile))

        status=nf90_get_var(ncid,varid,psf,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading PSFC from '//trim(infile))

        ! Read wrf var
        status = nf90_inq_varid(ncid, wrfvar, varid)
        call ncerror(status,'getting var id '//trim(wrfvar)//' in '//trim(infile))

        status = nf90_get_var(ncid, varid, wrfv3D, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading '//trim(wrfvar)//' from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
        press = p + pb
!
! Compute the four cloud fractions
!
        call calc_clt
        call calc_clh
        call calc_clm
        call calc_cll
!
        if(it == 0)then
          it=it+1
!
          outvar_n_i=outvar_n

          cycle loop_h
        endif

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 0.5
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h_4d(:,:,issh,:)=(outvar_n(:,:,:)+outvar_n_i(:,:,:))/2.
!
        outvar_n_i=outvar_n

      enddo loop_h    ! end of the files of the chunk

  write(ayearf, '(i4)') year

  call write_output              ! one file per year (chunk)
enddo

contains
!
!----------------------------------------------------------------------------------------------------------------------
!
subroutine calc_clt
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
!
! Output:
! outvar_n     : maximum cloud fraction - Total Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
!$omp parallel do private(iy, k, i, j, b, bb, bf) schedule(dynamic, 4)
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    bf=0.
!
    loop_k: do k=1,nz
      b(k)=wrfv3D(ix,iy,k)
      if(b(1) == 1.)then
        bf(k)=1.
        exit loop_k
      else
        do j=1,k
          if(b(j-1) /= 1)then
            bb(k)=bb(k)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
          else
            bf(k)=1.
            exit loop_k
          endif
        enddo
        bf(k)=1.-bb(k)
      endif
    enddo loop_k
!
    outvar_n(ix,iy,1)=maxval(bf)
!
  enddo
enddo
!$omp end parallel do
!
end subroutine calc_clt
!
!------------------------------------------------------------------------------------------------
!
subroutine calc_clh
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
! press     : pressure at model levels P + PB
!
! Output:
! outvar_n     : maximum cloud fraction - Total High Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
!$omp parallel do private(iy, k, i, j, b, bb, bf) schedule(dynamic, 4)
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    i=0
    bf=0.
!
    loop_k: do k=1,nz
      if(press(ix,iy,k) <= 44000.)then
        i=i+1
        b(i)=wrfv3D(ix,iy,k)
        if(b(1) == 1.)then
          bf(i)=1.
          exit loop_k
        else
          do j=1,i
            if(b(j-1) /= 1)then
              bb(i)=bb(i)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
            else
              bf(i)=1.
              exit loop_k
            endif
          enddo
          bf(i)=1.-bb(i)
        endif
      endif
    enddo loop_k
!
    outvar_n(ix,iy,2)=maxval(bf)
!
  enddo
enddo
!$omp end parallel do
!
end subroutine calc_clh
!
!-------------------------------------------------------------------------------------------------
!
subroutine calc_clm
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
! press     : pressure at model levels P + PB
!
! Output:
! outvar_n     : maximum cloud fraction - Total Medium Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!$omp parallel do private(iy, k, i, j, b, bb, bf) schedule(dynamic, 4)
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    i=0
    bf=0.
!
    loop_k: do k=1,nz
      if( 44000. < press(ix,iy,k) .and. press(ix,iy,k) <= 68000.)then
        i=i+1
        b(i)=wrfv3D(ix,iy,k)
        if(b(1) == 1.)then
          bf(i)=1.
          exit loop_k
        else
          do j=1,i
            if(b(j-1) /= 1)then
              bb(i)=bb(i)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
            else
              bf(i)=1.
              exit loop_k
            endif
          enddo
          bf(i)=1.-bb(i)
        endif
      elseif(press(ix,iy,k) <= 44000)then
        exit loop_k
      endif
    enddo loop_k
!
    outvar_n(ix,iy,3)=maxval(bf)
!
  enddo
enddo
!$omp end parallel do
!
end subroutine calc_clm
!
!------------------------------------------------------------------------------------------------
!
subroutine calc_cll
!
! Calculates cloud fraction using the assumption of random/maximum overlapping cloud cover in a grid column.
!
! Reference:
! Sundqvist et al.(1989) Condensation and Cloud Parameterization Studies with a Mesoscale Numerical
!                         Weather Prediction Model. MWR, 117, 1641-1657
!
! Input:
! wrfv3D    : cloud fraction  CLDFRA
! press     : pressure at model levels P + PB
!
! Output:
! outvar_n     : maximum cloud fraction - Total low Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
!$omp parallel do private(iy, k, i, j, b, bb, bf) schedule(dynamic, 4)
do ix=1,nlon
  do iy=1,nlat
!
    b(0)=0.
    bb=1.
    i=0
    bf=0.
!
    loop_k: do k=1,nz
      if(press(ix,iy,k) > 68000.)then
        i=i+1
        b(i)=wrfv3D(ix,iy,k)
        if(b(1) == 1.)then
          bf(i)=1.
          exit loop_k
        else
          do j=1,i
            if(b(j-1) /= 1)then
              bb(i)=bb(i)*((1.-max(b(j-1),b(j)))/(1.-b(j-1)))
            else
              bf(i)=1.
              exit loop_k
            endif
          enddo
          bf(i)=1.-bb(i)
        endif
      elseif(press(ix,iy,k) <= 68000.)then
        exit loop_k
      endif
    enddo loop_k
!
    outvar_n(ix,iy,4)=maxval(bf)
!
  enddo
enddo
!$omp end parallel do
!
end subroutine calc_cll
!
!-------------------------------------------------------------------------------------------------
!
subroutine write_output
! Logic to prepare filenames and call NetCDF writer
use datvar_s
use shared_io_subs
use netcdf

amonthf = pad_int(month-1, 2)
adayf = pad_int(day-1, 2)
ahourf = pad_int(hour-1, 2)

freq='1hr'
frequency=trim(adjustl(freq))

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
! Call the shared NetCDF writer from shared_io_subs, once per variable
!
do nv = 1, ncomb
  select case (nv)
    case (1)      ! clt: metadata of the header
      varname = trim(adjustl(vaid)); vunits = trim(adjustl(vunts)); longname = trim(adjustl(lname))
      standardname = trim(adjustl(stname)); cellmethods = trim(adjustl(cmethods))
    case (2)
      varname = 'clh'; vunits = '%'; longname = 'High Level Cloud Fraction'
      standardname = 'cloud_area_fraction_in_atmosphere_layer'; cellmethods = 'area: time: mean'
    case (3)
      varname = 'clm'; vunits = '%'; longname = 'Mid Level Cloud Fraction'
      standardname = 'cloud_area_fraction_in_atmosphere_layer'; cellmethods = 'area: time: mean'
    case (4)
      varname = 'cll'; vunits = '%'; longname = 'Low Level Cloud Fraction'
      standardname = 'cloud_area_fraction_in_atmosphere_layer'; cellmethods = 'area: time: mean'
  end select
  ! output step: clt that of its header (ostep), clh, clm and cll 6 hours (their headers:
  ! outstep = 6, the CORDEX-CMIP6 6hr means)
  if (nv == 1) then
    vo_i = ostep
  else
    vo_i = 6
  endif
  if (vo_i > 1) then
    call resample_time(outvar_h_4d(:,:,1:issh,nv), ttime(1:issh), bdtime(:,1:issh), vo_i, cellmethods, outvar_r, ttime_r, bdtime_r, nt_r)
    if (vo_i == 24) then
      freq = 'day'
    else
      write(freq,'(i0,a)') vo_i, 'hr'
    endif
    frequency=trim(adjustl(freq))
    outfile=trim(dir_out)//trim(varname)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime_r,nt_r))//'.nc'
    fnameout=trim(adjustl(outfile))
    call write_netcdf_rtime_3d(outvar_r, nt_r, ttime_r, bdtime_r)
    deallocate(outvar_r, ttime_r, bdtime_r)
  else
    freq='1hr'
    frequency=trim(adjustl(freq))
    outfile=trim(dir_out)//trim(varname)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
    fnameout=trim(adjustl(outfile))
    call write_netcdf_rtime_3d(outvar_h_4d(:,:,:,nv), ntime, ttime, bdtime)
  endif
enddo

! back to the header's variable
varname = trim(adjustl(vaid)); vunits = trim(adjustl(vunts)); longname = trim(adjustl(lname))
standardname = trim(adjustl(stname)); cellmethods = trim(adjustl(cmethods))

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h_4d)

end subroutine write_output


end program read_wrfout

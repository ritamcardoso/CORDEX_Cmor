program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_cloud.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_cloud.f90 and rerun tools/make_varcalendar.py rather than this file.
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


! --- Main Processing Loops ---
allocate(outvar(nlon, nlat), outvar_i(nlon,nlat))
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
    allocate(outvar_h(nlon, nlat, ntime))
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
! Compute cloud fraction
!
        select case(trim(varname))
          case('clt')
            call calc_clt
          case('clh')
            call calc_clh
          case('clm')
            call calc_clm
          case('cll')
            call calc_cll
        end select
!
        if(it == 0)then
          it=it+1
!
          outvar_i=outvar

          cycle loop_h
        endif

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 0.5
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h(:,:,issh)=(outvar(:,:)+outvar_i(:,:))/2.
!
        outvar_i=outvar

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
! outvar       : maximum cloud fraction - Total Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
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
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
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
! outvar       : maximum cloud fraction - Total High Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
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
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
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
! outvar       : maximum cloud fraction - Total Medium Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
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
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
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
! outvar       : maximum cloud fraction - Total low Cloud Cover
!
use datvar_s
!
real, dimension(0:nz) :: b
real, dimension(nz) :: bb,bf
!
!
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
    outvar(ix,iy)=maxval(bf)
!
  enddo
enddo
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
call resample_output        ! output step: outstep of the header (hours; 0 = wp_step of the grid ini)
frequency=trim(adjustl(freq))

! Create output filename based on metadata
outfile=trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
fnameout=trim(adjustl(outfile))

if (factor /= 0.) outvar_h = outvar_h * factor

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
! Call the shared NetCDF writer from shared_io_subs
!
call write_netcdf_rtime_3d(outvar_h, ntime, ttime, bdtime)

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h)

end subroutine write_output


end program read_wrfout

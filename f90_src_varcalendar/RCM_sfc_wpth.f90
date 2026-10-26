program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_wpth.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_wpth.f90 and rerun tools/make_varcalendar.py rather than this file.
!
!
! RCM_sfc_wpth — the three water paths of one run (1hr, instantaneous), from one reading
! of each wrfout file (P, PB, PSFC, QVAPOR, QCLOUD, QICE, QRAIN, QSNOW):
!
!   prw    Water Vapor Path        QVAPOR                       (vaid = prw in the header)
!   clivi  Ice Water Path          QICE + QSNOW                 (companion)
!   clwvi  Condensed Water Path    QCLOUD + QICE + QRAIN + QSNOW (companion)
!
! The same formulas as RCM_sfc_prw, RCM_sfc_clivi and RCM_sfc_clwvi (identical results):
! sum over the model levels of q/(1+q) dp / g, with the layer interfaces halfway between
! the mass levels, PSFC at the bottom and p_top at the top. clivi and clwvi are archived
! through the companion varset (CP_EXTRA); their metadata is set in write_output.
! Graupel and hail (clgvi, clhvi) stay in RCM_sfc_clgvi / RCM_sfc_clhvi (wpth4): not every
! microphysics scheme has QGRAUP and QHAIL.
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
ncomb = 3                       ! prw, clivi, clwvi


! --- Main Processing Loops ---
allocate(outvar_n(nlon, nlat, ncomb))
allocate(p(nlon, nlat, nz), pb(nlon, nlat, nz), press(nlon, nlat, nz))
allocate(p_iface(nlon, nlat, nzt))
allocate(qv(nlon, nlat, nz), qc(nlon, nlat, nz), qi(nlon, nlat, nz), qr(nlon, nlat, nz), qs(nlon, nlat, nz))
allocate(psf(nlon, nlat))

it = 0
do vc_year = yeari, yearf
  ! the part of the year inside sim_start..sim_end (nothing to do if none)
  if (.not. time_chunk(vc_year, 1, .false.)) cycle
  year = vc_year

  write(ayear, '(i4)') year
  issh = 0

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

  ! Loop over months
  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        ! Read Pressure and the moisture fields

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status,'getting var id P in '//trim(infile))

        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading P from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status,'getting var id PB in '//trim(infile))

        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status,'reading PB from '//trim(infile))
!
        press=p+pb
!
        status=nf90_inq_varid(ncid,'PSFC',varid)
        call ncerror(status,'getting var id PSFC in '//trim(infile))

        status=nf90_get_var(ncid,varid,psf,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
        call ncerror(status,'reading PSFC from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'QVAPOR',varid)
        call ncerror(status,'getting var id QVAPOR in '//trim(infile))
!
        status=nf90_get_var(ncid,varid,qv,(/xoffset,yoffset,1/),(/nlon,nlat,nz/),(/1,1/))
        call ncerror(status,'reading QVAPOR from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'QCLOUD',varid)
        call ncerror(status,'getting var id QCLOUD in '//trim(infile))
!
        status=nf90_get_var(ncid,varid,qc,(/xoffset,yoffset,1/),(/nlon,nlat,nz/),(/1,1/))
        call ncerror(status,'reading QCLOUD from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'QICE',varid)
        call ncerror(status,'getting var id QICE in '//trim(infile))
!
        status=nf90_get_var(ncid,varid,qi,(/xoffset,yoffset,1/),(/nlon,nlat,nz/),(/1,1/))
        call ncerror(status,'reading QICE from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'QRAIN',varid)
        call ncerror(status,'getting var id QRAIN in '//trim(infile))
!
        status=nf90_get_var(ncid,varid,qr,(/xoffset,yoffset,1/),(/nlon,nlat,nz/),(/1,1/))
        call ncerror(status,'reading QRAIN from '//trim(infile))
!
        status=nf90_inq_varid(ncid,'QSNOW',varid)
        call ncerror(status,'getting var id QSNOW in '//trim(infile))
!
        status=nf90_get_var(ncid,varid,qs,(/xoffset,yoffset,1/),(/nlon,nlat,nz/),(/1,1/))
        call ncerror(status,'reading QSNOW from '//trim(infile))
!
        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
! Compute the three water paths
!
        call calc_wpth
!
        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h_4d(:, :, issh, :) = outvar_n(:, :, :)

      enddo loop_h    ! end of the files of the chunk

  ! Write annual output using shared subroutine
  write(ayearf, '(i4)') year
  write(ayeari, '(i4)') year

  call write_output

enddo

contains
!
!----------------------------------------------------------------------------------------------------
!
subroutine calc_wpth
! prw, clivi and clwvi of every column: sum of q/(q+1) dp over the model levels, / g
use datvar_s
!
p_iface(:,:,1)    = psf(:,:)
p_iface(:,:,nz+1) = p_top

do ix=1,nlon
  do iy=1,nlat
!
     wp_v=0.
     wp_i=0.
     wp_c=0.
!
     do k=1,nz
       if(k < nz) p_iface(ix,iy,k+1) = 0.5 * (press(ix,iy,k) + press(ix,iy,k+1))
       dpk = p_iface(ix,iy,k)-p_iface(ix,iy,k+1)

       wp_v=wp_v+(qv(ix,iy,k)/(qv(ix,iy,k)+1))*dpk
       wp_i=wp_i+((qi(ix,iy,k)+qs(ix,iy,k))/((qi(ix,iy,k)+qs(ix,iy,k))+1))*dpk
       wp_c=wp_c+((qc(ix,iy,k)+qi(ix,iy,k)+qr(ix,iy,k)+qs(ix,iy,k))/ &
                  ((qc(ix,iy,k)+qi(ix,iy,k)+qr(ix,iy,k)+qs(ix,iy,k))+1))*dpk
     enddo
     outvar_n(ix,iy,1)=wp_v/g
     outvar_n(ix,iy,2)=wp_i/g
     outvar_n(ix,iy,3)=wp_c/g
!
  enddo
enddo
!
end subroutine calc_wpth
!
!-------------------------------------------------------------------------------------------------
!
subroutine write_output
! one hourly file per variable and year: prw (the header), clivi, clwvi
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
    case (1)      ! prw: metadata of the header
      varname = trim(adjustl(vaid)); vunits = trim(adjustl(vunts)); longname = trim(adjustl(lname))
      standardname = trim(adjustl(stname)); cellmethods = trim(adjustl(cmethods))
    case (2)
      varname = 'clivi'; vunits = 'kg m-2'; longname = 'Ice Water Path'
      standardname = 'atmosphere_mass_content_of_cloud_ice'; cellmethods = 'area: mean time: point'
    case (3)
      varname = 'clwvi'; vunits = 'kg m-2'; longname = 'Condensed Water Path'
      standardname = 'atmosphere_mass_content_of_cloud_condensed_water'; cellmethods = 'area: mean time: point'
  end select
  outfile=trim(dir_out)//trim(varname)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
  fnameout=trim(adjustl(outfile))
  call write_netcdf_rtime_3d(outvar_h_4d(:,:,:,nv), ntime, ttime, bdtime)
enddo

! back to the header's variable for the next year
varname = trim(adjustl(vaid)); vunits = trim(adjustl(vunts)); longname = trim(adjustl(lname))
standardname = trim(adjustl(stname)); cellmethods = trim(adjustl(cmethods))

deallocate(ttime)
deallocate(bdtime)
deallocate(outvar_h_4d)

end subroutine write_output


end program read_wrfout

program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_zlev_va.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_zlev_va.f90 and rerun tools/make_varcalendar.py rather than this file.
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
nz = 15
nzt = nz + 1
nlon_u=nlon+1
nlat_v=nlat+1
nhours = 24


! --- Main Processing Loops ---
allocate(outvar(nlon, nlat))
allocate(zhgt(nlon, nlat, nz), hgt(nlon, nlat))
allocate(cosalp(nlon,nlat), sinalp(nlon,nlat))
allocate(u(nlon,nlat,nz), v(nlon,nlat,nz))

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
  allocate(outvar_h(nlon, nlat, ntime))

  ! Loop over months
  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        ! Read Terrain Height once
        if (it == 0) then
            it = it + 1
!
          status=nf90_inq_varid(ncid,'COSALPHA',varid)
          call ncerror(status,'getting var id COSALPHA in '//trim(infile))

          status=nf90_get_var(ncid,varid,cosalp,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
          call ncerror(status,'reading COSALPHA from '//trim(infile))
!
          status=nf90_inq_varid(ncid,'SINALPHA',varid)
          call ncerror(status,'getting var id SINALPHA in '//trim(infile))

          status=nf90_get_var(ncid,varid,sinalp,(/xoffset,yoffset/),(/nlon,nlat/),(/1,1/))
          call ncerror(status,'reading SINALPHA from '//trim(infile))

            status = nf90_inq_varid(ncid, 'HGT', varid)
            call ncerror(status,'getting var id HGT in '//trim(infile))

            status = nf90_get_var(ncid, varid, hgt, (/xoffset, yoffset/), (/nlon, nlat/),(/1,1/))
            call ncerror(status,'reading HGT from '//trim(infile))
        endif

        ! Read Geopotential for Height Calculation

        allocate(ph(nlon, nlat, nzt), phb(nlon, nlat, nzt), phi(nlon, nlat, nzt))

        status = nf90_inq_varid(ncid, 'PH', varid)
        call ncerror(status,'getting var id PH in '//trim(infile))

        status = nf90_get_var(ncid, varid, ph, (/xoffset, yoffset, 1/), (/nlon, nlat, nzt/))
        call ncerror(status,'reading PH from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PHB', varid)
        call ncerror(status,'getting var id PHB in '//trim(infile))

        status = nf90_get_var(ncid, varid, phb, (/xoffset, yoffset, 1/), (/nlon, nlat, nzt/))
        call ncerror(status,'reading PHB from '//trim(infile))

        phi = (ph + phb) / g

        ! Calculate height above the surface

        do iz = 1, nz
            zhgt(:, :, iz) = ((phi(:, :, iz) + phi(:, :, iz+1)) / 2.) - hgt(:, :)
        enddo
        deallocate(ph, phb, phi)

        ! Read wrf var

        allocate(ua(nlon_u,nlat,nz), va(nlon,nlat_v,nz))
        !
        status=nf90_inq_varid(ncid,'U',varid)
        call ncerror(status,'getting var id U in '//trim(infile))

        status=nf90_get_var(ncid,varid,ua,(/xoffset,yoffset,1/),(/nlon_u,nlat,nz/),(/1,1,1/))
        call ncerror(status,'reading U from '//trim(infile))

        status=nf90_inq_varid(ncid,'V',varid)
        call ncerror(status,'getting var id V in '//trim(infile))

        status=nf90_get_var(ncid,varid,va,(/xoffset,yoffset,1/),(/nlon,nlat_v,nz/),(/1,1,1/))
        call ncerror(status,'reading V from '//trim(infile))
!
        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))
!
! Compute variable
!
        do ix=1,nlon
          do iy=1,nlat
            u(ix,iy,:)=(ua(ix,iy,:)+ua(ix+1,iy,:))/2.0
            v(ix,iy,:)=(va(ix,iy,:)+va(ix,iy+1,:))/2.0
          enddo
        enddo
!
        deallocate(ua, va)

        ! Interpolate to specific height 'heightl'

        call calc_zlev_uv

        ish = ish + 1
        issh = issh + 1
        ttime(issh) = float(ish) - 1
        bdtime(1, issh) = ish - 1
        bdtime(2, issh) = ish

        outvar_h(:, :, issh) = outvar(:, :)

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
subroutine calc_zlev_uv
use datvar_s        
!
real :: alphau,alphav,u1,u2,v1,v2,u_int,v_int,logz1,logz2,norm_z
!real, parameter :: min_val = 1.0e-7, huge_val = 1.0e20
!
outvar=huge_val
!
do isy=1,nlat
  do isx=1,nlon
    z_loop: do iz=1,nz-1

      if(zhgt(isx,isy,iz) > heightl)exit z_loop      !skip if above target height. Shouldn't happen!

      if(zhgt(isx,isy,iz+1) >= heightl .and. zhgt(isx,isy,iz) < heightl)then    ! Search in the vertical
!
!       Ensure no zero or negative values for logs
!
        u1=max(abs(u(isx,isy,iz)),min_val)
        u2=max(abs(u(isx,isy,iz+1)),min_val)
        v1=max(abs(v(isx,isy,iz)),min_val)
        v2=max(abs(v(isx,isy,iz+1)),min_val)
!
!       Pre-calculate vertical logs for code speed
!
        logz1=log(zhgt(isx,isy,iz))
        logz2=log(zhgt(isx,isy,iz+1))
        norm_z=heightl/zhgt(isx,isy,iz)
!
!       Calculate exponent
!
        alphau=(log(u2)-log(u1))/(logz2-logz1)
        alphav=(log(v2)-log(v1))/(logz2-logz1)
!
!       Calculate u and v in the model frame
!
        u_int=sign(u1,u(isx,isy,iz))*(norm_z)**alphau
        v_int=sign(v1,v(isx,isy,iz))*(norm_z)**alphav
!
!       Rotate to Earth related frame
!
!        outvar(isx,isy)=u_int*cosalp(isx,isy)-v_int*sinalp(isx,isy)
        outvar(isx,isy)=v_int*cosalp(isx,isy)+u_int*sinalp(isx,isy)

        exit z_loop
      endif
    enddo z_loop
!
  enddo
enddo
!
end subroutine calc_zlev_uv
!
!----------------------------------------------------------------------------------------------------
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

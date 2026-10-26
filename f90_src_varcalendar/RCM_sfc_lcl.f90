program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_lcl.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_lcl.f90 and rerun tools/make_varcalendar.py rather than this file.
!
!
! RCM_sfc_lcl — lcl, height of the lifting condensation level above ground (1hr,
! instantaneous, m) of the parcel of the lowest model level, as in RCM_sfc_cape:
!
!   p = P + PB, T = (theta' + 300) (p / 1e5)**rcp, r = QVAPOR of the lowest mass level;
!   LCL above the parcel: exact solution of Romps (2017, J. Atmos. Sci. 74, 3891)
!   (romps_lcl in humidity_subs.f90); lcl = that height + height of the lowest mass
!   level above the ground (from PH + PHB, HGT).
!
! lcl is not a CORDEX-CMIP6 variable (no standard_name). Only the lowest mass level of
! P, PB, T, QVAPOR and the two lowest w levels of PH, PHB are read every hour; HGT once.
! All arrays and scalars are those of datvar_s.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_io_subs
use humidity_subs
use netcdf
!implicit none

! --- Read configuration using shared_io_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog

allocate(p(nlon,nlat,1), pb(nlon,nlat,1), press(nlon,nlat,1), t(nlon,nlat,1), qv(nlon,nlat,1))
allocate(ph(nlon,nlat,2), phb(nlon,nlat,2), hgt(nlon,nlat))

it = 0

do vc_year = yeari, yearf
  ! the part of the year inside sim_start..sim_end (nothing to do if none)
  if (.not. time_chunk(vc_year, 1, .false.)) cycle
  year = vc_year
  write(ayear, '(i4)') year
  if (mod(year, 4) == 0 .and. year /= 2100) then
    days = days2
  else
    days = days1
  endif

  allocate(ttime(ntime), bdtime(2, ntime))
  allocate(outvar_h(nlon,nlat,ntime))
  issh = 0

  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status, 'getting var id P in '//trim(infile))
        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, 1/))
        call ncerror(status, 'reading P from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status, 'getting var id PB in '//trim(infile))
        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, 1/))
        call ncerror(status, 'reading PB from '//trim(infile))

        status = nf90_inq_varid(ncid, 'T', varid)
        call ncerror(status, 'getting var id T in '//trim(infile))
        status = nf90_get_var(ncid, varid, t, (/xoffset, yoffset, 1/), (/nlon, nlat, 1/))
        call ncerror(status, 'reading T from '//trim(infile))

        status = nf90_inq_varid(ncid, 'QVAPOR', varid)
        call ncerror(status, 'getting var id QVAPOR in '//trim(infile))
        status = nf90_get_var(ncid, varid, qv, (/xoffset, yoffset, 1/), (/nlon, nlat, 1/))
        call ncerror(status, 'reading QVAPOR from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PH', varid)
        call ncerror(status, 'getting var id PH in '//trim(infile))
        status = nf90_get_var(ncid, varid, ph, (/xoffset, yoffset, 1/), (/nlon, nlat, 2/))
        call ncerror(status, 'reading PH from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PHB', varid)
        call ncerror(status, 'getting var id PHB in '//trim(infile))
        status = nf90_get_var(ncid, varid, phb, (/xoffset, yoffset, 1/), (/nlon, nlat, 2/))
        call ncerror(status, 'reading PHB from '//trim(infile))

        if (it == 0) then                                      ! terrain height: once
          status = nf90_inq_varid(ncid, 'HGT', varid)
          call ncerror(status, 'getting var id HGT in '//trim(infile))
          status = nf90_get_var(ncid, varid, hgt, (/xoffset, yoffset/), (/nlon, nlat/))
          call ncerror(status, 'reading HGT from '//trim(infile))
          it = 1
        endif

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))

        press = p + pb                                          ! pressure (Pa)
        t = (t + 300.) * (press / pconst)**rcp                  ! temperature (K)
        qv = max(qv, 0.)

        issh = issh + 1
        bdtime(1, issh) = hours_since_ini(year, month, day, hour)
        bdtime(2, issh) = bdtime(1, issh) + 1
        ttime(issh) = float(bdtime(1, issh))

        call calc_lcl
      enddo loop_h    ! end of the files of the chunk

  write(ayeari, '(i4)') year
  write(ayearf, '(i4)') year
  call write_output
enddo

contains
!
!-----------------------------------------------------------------------
!
subroutine calc_lcl
! LCL height above ground of every column for the time step issh
!
do iy = 1, nlat
  do ix = 1, nlon
    p_par = press(ix,iy,1)
    t_par = t(ix,iy,1)
    r_par = max(real(qv(ix,iy,1), 8), 1.d-12)
    call romps_lcl(p_par, t_par, r_par, z_lcl, t_lcl, p_lcl)
    ! + height of the lowest mass level above the ground (mean of the two lowest w levels)
    !   (in single precision, as zhgt of the earlier RCM_sfc_cape)
    outvar_h(ix,iy,issh) = real(z_lcl + 0.5 * ((ph(ix,iy,1) + phb(ix,iy,1)) / g + (ph(ix,iy,2) + phb(ix,iy,2)) / g) &
                                - hgt(ix,iy))
  enddo
enddo
!
end subroutine calc_lcl
!
!-----------------------------------------------------------------------
!
subroutine write_output
! one hourly file per year, with the metadata of the header

freq = '1hr'
frequency = trim(adjustl(freq))

call date_and_time(date,times,zone,values)
write(yyyy,'(i4)') values(1)
mm = pad_int(values(2), 2)
dd = pad_int(values(3), 2)
hh = pad_int(values(5), 2)
mn = pad_int(values(6), 2)
ss = pad_int(values(7), 2)
cdate = yyyy//'-'//mm//'-'//dd//'-T'//hh//':'//mn//':'//ss//'Z'
creationdate = cdate(1:len_trim(cdate))

fnameout = trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
call write_netcdf_rtime_3d(outvar_h, ntime, ttime, bdtime)

deallocate(ttime, bdtime, outvar_h)

end subroutine write_output

end program read_wrfout

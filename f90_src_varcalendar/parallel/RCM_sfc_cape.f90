program read_wrfout
!
! Variable-calendar version (f90_src_varcalendar) of f90_src/RCM_sfc_cape.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/RCM_sfc_cape.f90 and rerun tools/make_varcalendar.py rather than this file.
!
! OpenMP version (f90_src_parallel): the columns of calc_cape run in parallel (rows iy shared out; the
! per-column work variables of datvar_s, including buoy_c, zrel_c and ben_c, are private).
! Compile with the OpenMP flag (ifort -qopenmp, gfortran -fopenmp) and set OMP_NUM_THREADS;
! without the flag the directives are comments and it is the serial program of f90_src.
!
!
! RCM_sfc_cape — convective diagnostics of the surface parcel (1hr, instantaneous), all
! three written by one run (vaid = cape in the header; cin and li are companions,
! archived through cape_x):
!
!   cape  Convective Available Potential Energy (J kg-1)
!   cin   Convective Inhibition (J kg-1, positive)
!   li    Lifted Index at 500 hPa (K): T_environment - T_parcel
!
! The lifting condensation level (lcl, not a CORDEX variable) is written by RCM_sfc_lcl;
! the earlier version of this program, which also wrote it, is in f90_src/deprecated.
!
! Parcel: the lowest model level (p = P + PB, T from theta = T + 300, r = QVAPOR).
!  - LCL: exact solution of Romps (2017, J. Atmos. Sci. 74, 3891) for its height,
!    temperature T_L and pressure (romps_lcl in humidity_subs.f90).
!  - Below the LCL the parcel follows the dry adiabat (theta and r conserved); above
!    it, a pseudo-adiabat of constant theta_e (Bolton 1980, eq. 43, with the Romps T_L),
!    inverted for T at every level (Newton; saturation mixing ratio of RCM_sfc_hurs).
!    Davies-Jones (2009, MWR 137, 3137) finds Bolton's formula accurate to 0.02 K.
!  - With cape_ice = 1 in the grid ini, the parcel above the LCL follows instead a pseudo-adiabat
!    with ice (t_pseudo_ice in humidity_subs.f90): the condensate freezes progressively from
!    0 degC (all liquid) to -40 degC (all ice), with saturation over the mixture (ice: Ambaum
!    2020, QJRMS 146, 4252, eq. 20) and the latent heat of the mixture. The default, 0, is the
!    liquid-only parcel of RIP / NCL / wrf-python.
!  - Buoyancy B = g (Tv_parcel - Tv_env) / Tv_env (virtual temperatures), on the model
!    levels plus two inserted ones: the LCL and every zero crossing of B.
!  - As RIP / NCL / wrf-python: the accumulated energy E(z) = int_0^z B dz (trapezoids);
!    EL = highest level at or above the LCL with B >= 0; LFC = level between the LCL and
!    the EL where E is minimum; CAPE = E(EL) - E(LFC), CIN = -E(LFC) (both >= 0).
!    No EL (B < 0 everywhere above the LCL): CAPE = CIN = 0. The parcel is lifted to
!    the model top (every model level), as RIP / NCL / wrf-python.
!  - LI: parcel at 500 hPa (dry adiabat if the LCL is above 500 hPa, else the theta_e
!    pseudo-adiabat), environment T log(p)-interpolated; missing where the surface is
!    above 500 hPa.
! Fields from wrfout: P, PB, T, QVAPOR, PH, PHB.
! All arrays and scalars are those of datvar_s.
!
! Use external modules for variables and shared subroutines
use datvar_s
use shared_subs
use humidity_subs
use netcdf
!implicit none

! --- Read configuration using shared_subs subroutine

call init_cordex_environment

! --- Read Grid Information (Latitude, Longitude) ---

call read_geog
if (cape_ice == 1) then
  write(*,*) 'cape, cin, li: parcel with ice above the LCL (cape_ice = 1)'
else
  write(*,*) 'cape, cin, li: liquid-only parcel above the LCL (cape_ice = 0)'
endif

allocate(p(nlon,nlat,nz), pb(nlon,nlat,nz), press(nlon,nlat,nz), t(nlon,nlat,nz), qv(nlon,nlat,nz))
allocate(ph(nlon,nlat,nz+1), phb(nlon,nlat,nz+1), phi(nlon,nlat,nz+1), zhgt(nlon,nlat,nz))
allocate(buoy_c(2*nz+4), zrel_c(2*nz+4), ben_c(2*nz+4))


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
  allocate(outvar_h(nlon,nlat,ntime), cin_h(nlon,nlat,ntime), li_h(nlon,nlat,ntime))
  issh = 0

  ! Loop over the files of the chunk: set_time_step sets year, month, day, hour,
  ! ayear, amonth, aday, ahour and infile
  loop_h: do vc_ifl = 1, vc_nfiles
    call set_time_step(vc_ifl)

        status = nf90_open(infile, nf90_nowrite, ncid)
        call ncerror(status,'opening '//trim(infile))

        status = nf90_inq_varid(ncid, 'P', varid)
        call ncerror(status, 'getting var id P in '//trim(infile))
        status = nf90_get_var(ncid, varid, p, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status, 'reading P from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PB', varid)
        call ncerror(status, 'getting var id PB in '//trim(infile))
        status = nf90_get_var(ncid, varid, pb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status, 'reading PB from '//trim(infile))

        status = nf90_inq_varid(ncid, 'T', varid)
        call ncerror(status, 'getting var id T in '//trim(infile))
        status = nf90_get_var(ncid, varid, t, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status, 'reading T from '//trim(infile))

        status = nf90_inq_varid(ncid, 'QVAPOR', varid)
        call ncerror(status, 'getting var id QVAPOR in '//trim(infile))
        status = nf90_get_var(ncid, varid, qv, (/xoffset, yoffset, 1/), (/nlon, nlat, nz/))
        call ncerror(status, 'reading QVAPOR from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PH', varid)
        call ncerror(status, 'getting var id PH in '//trim(infile))
        status = nf90_get_var(ncid, varid, ph, (/xoffset, yoffset, 1/), (/nlon, nlat, nz+1/))
        call ncerror(status, 'reading PH from '//trim(infile))

        status = nf90_inq_varid(ncid, 'PHB', varid)
        call ncerror(status, 'getting var id PHB in '//trim(infile))
        status = nf90_get_var(ncid, varid, phb, (/xoffset, yoffset, 1/), (/nlon, nlat, nz+1/))
        call ncerror(status, 'reading PHB from '//trim(infile))

        status = nf90_close(ncid)
        call ncerror(status,'closing '//trim(infile))

        press = p + pb                                          ! pressure (Pa)
        t = (t + 300.) * (press / pconst)**rcp                  ! temperature (K)
        qv = max(qv, 0.)
        phi = (ph + phb) / g                                    ! height of the w levels (m)
        zhgt = 0.5 * (phi(:,:,1:nz) + phi(:,:,2:nz+1))          ! ... of the mass levels

        issh = issh + 1
        bdtime(1, issh) = hours_since_ini(year, month, day, hour)
        bdtime(2, issh) = bdtime(1, issh) + 1
        ttime(issh) = float(bdtime(1, issh))

        call calc_cape
      enddo loop_h    ! end of the files of the chunk

  write(ayeari, '(i4)') year
  write(ayearf, '(i4)') year
  call write_output
enddo

contains
!
!-----------------------------------------------------------------------
!
subroutine calc_cape
! cape, cin, li and lcl of every column for the time step issh
!
!$omp parallel do schedule(dynamic, 1) &
!$omp   private(ix, k, kk, klcl, kel, klfc, kmax, lcl_in, found_el, &
!$omp           p_par, t_par, r_par, th_par, the_par, z_lcl, t_lcl, p_lcl, &
!$omp           t_lift, q_lift, z_lift, tv_lift, t_env, q_env, tv_env, fac1, fac2, fden, &
!$omp           ben_min, t500, te500, t_ice, p_ice, buoy_c, zrel_c, ben_c)
do iy = 1, nlat
  do ix = 1, nlon

    ! 1) surface parcel and its exact LCL (Romps 2017)
    p_par  = press(ix,iy,1)
    t_par  = t(ix,iy,1)
    r_par  = max(real(qv(ix,iy,1), 8), 1.d-12)
    th_par = t_par * (pconst / p_par)**rcp
    call romps_lcl(p_par, t_par, r_par, z_lcl, t_lcl, p_lcl)
    the_par = theta_e_bolton(t_par, p_par, r_par, t_lcl)

    ! 2) lift the parcel: buoyancy on the model levels, with the LCL and the zero
    !    crossings inserted (heights relative to the parcel level)
    kk = 0
    lcl_in = .false.
    klcl = 0
    t_lift = t_par
    level_loop: do k = 1, nz
      insert_loop: do
        kk = kk + 1
        if (zhgt(ix,iy,k) - zhgt(ix,iy,1) < z_lcl) then
          ! below the LCL: dry adiabat
          t_lift  = th_par * (press(ix,iy,k) / pconst)**rcp
          q_lift  = r_par
          z_lift  = zhgt(ix,iy,k) - zhgt(ix,iy,1)
          tv_env  = tvirt(real(t(ix,iy,k), 8), real(qv(ix,iy,k), 8))
        else if (.not. lcl_in) then
          ! the LCL itself, between levels k-1 and k
          t_lift  = t_lcl
          q_lift  = r_par
          z_lift  = z_lcl
          fden    = zhgt(ix,iy,k) - zhgt(ix,iy,max(k-1,1))
          if (abs(fden) < 1.d-6) fden = 1.d0
          fac1    = (z_lcl + zhgt(ix,iy,1) - zhgt(ix,iy,max(k-1,1))) / fden
          fac1    = max(0.d0, min(1.d0, fac1))
          fac2    = 1.d0 - fac1
          t_env   = t(ix,iy,max(k-1,1)) * fac2 + t(ix,iy,k) * fac1
          q_env   = qv(ix,iy,max(k-1,1)) * fac2 + qv(ix,iy,k) * fac1
          tv_env  = tvirt(t_env, q_env)
          t_ice   = t_lcl                                   ! start of the pseudo-adiabat with ice
          p_ice   = p_lcl
        else if (cape_ice == 1) then
          ! above the LCL: pseudo-adiabat with ice, from the level below
          t_lift  = t_pseudo_ice(t_ice, p_ice, real(press(ix,iy,k), 8))
          q_lift  = qvs_mixed(t_lift, real(press(ix,iy,k), 8))
          t_ice   = t_lift
          p_ice   = press(ix,iy,k)
          z_lift  = zhgt(ix,iy,k) - zhgt(ix,iy,1)
          tv_env  = tvirt(real(t(ix,iy,k), 8), real(qv(ix,iy,k), 8))
        else
          ! above the LCL: pseudo-adiabat of constant theta_e
          t_lift  = t_from_theta_e(the_par, real(press(ix,iy,k), 8), t_lift)
          q_lift  = qvs_wexler(t_lift, real(press(ix,iy,k), 8))
          z_lift  = zhgt(ix,iy,k) - zhgt(ix,iy,1)
          tv_env  = tvirt(real(t(ix,iy,k), 8), real(qv(ix,iy,k), 8))
        endif
        tv_lift = tvirt(t_lift, q_lift)
        buoy_c(kk) = g * (tv_lift - tv_env) / tv_env
        zrel_c(kk) = z_lift

        ! zero crossing of the buoyancy: insert a level where it is 0
        if (kk > 1) then
          if (buoy_c(kk) * buoy_c(kk-1) < 0.d0) then
            kk = kk + 1
            buoy_c(kk)   = buoy_c(kk-1)
            zrel_c(kk)   = zrel_c(kk-1)
            buoy_c(kk-1) = 0.d0
            zrel_c(kk-1) = zrel_c(kk-2) + buoy_c(kk-2) / (buoy_c(kk-2) - buoy_c(kk)) * (zrel_c(kk) - zrel_c(kk-2))
          endif
        endif

        if (.not. lcl_in .and. zhgt(ix,iy,k) - zhgt(ix,iy,1) >= z_lcl) then
          klcl = kk
          lcl_in = .true.
          cycle insert_loop                                 ! now the model level k itself
        endif
        exit insert_loop
      enddo insert_loop
    enddo level_loop
    kmax = kk
    if (.not. lcl_in) klcl = kmax                           ! LCL above the model top

    ! 3) accumulated buoyant energy (trapezoids)
    ben_c(1) = 0.d0
    do k = 2, kmax
      ben_c(k) = ben_c(k-1) + 0.5d0 * (zrel_c(k) - zrel_c(k-1)) * (buoy_c(k-1) + buoy_c(k))
    enddo

    ! 4) EL: highest level at or above the LCL with B >= 0; LFC: minimum of E between
    !    the LCL and the EL; CAPE and CIN
    found_el = .false.
    kel = klcl
    do k = kmax, klcl, -1
      if (buoy_c(k) >= 0.d0) then
        kel = k
        found_el = .true.
        exit
      endif
    enddo
    if (found_el) then
      ben_min = huge(1.d0)
      klfc = klcl
      do k = klcl, kel
        if (ben_c(k) < ben_min) then
          ben_min = ben_c(k)
          klfc = k
        endif
      enddo
      outvar_h(ix,iy,issh) = real(max(ben_c(kel) - ben_min, 0.d0))
      cin_h(ix,iy,issh)    = real(max(-ben_min, 0.d0))
    else
      outvar_h(ix,iy,issh) = 0.
      cin_h(ix,iy,issh)    = 0.
    endif

    ! 5) lifted index at 500 hPa
    li_h(ix,iy,issh) = huge_val
    if (p_par > 5.d4) then
      if (p_lcl <= 5.d4) then
        t500 = th_par * (5.d4 / pconst)**rcp                  ! still dry at 500 hPa
      else if (cape_ice == 1) then
        t500 = t_pseudo_ice(t_lcl, p_lcl, 5.d4)
      else
        t500 = t_from_theta_e(the_par, 5.d4, t_lcl)
      endif
      do k = 1, nz-1
        if (press(ix,iy,k) >= 5.e4 .and. press(ix,iy,k+1) < 5.e4) then
          fac1 = (log(real(press(ix,iy,k), 8)) - log(5.d4)) / &
                 (log(real(press(ix,iy,k), 8)) - log(real(press(ix,iy,k+1), 8)))
          te500 = t(ix,iy,k) + fac1 * (t(ix,iy,k+1) - t(ix,iy,k))
          li_h(ix,iy,issh) = real(te500 - t500)
          exit
        endif
      enddo
    endif

  enddo
enddo
!$omp end parallel do
!
end subroutine calc_cape
!
!-----------------------------------------------------------------------
!
subroutine write_output
! one hourly file per variable and year: cape (the header), cin, li

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

! cape: metadata of the header
fnameout = trim(dir_out)//trim(vaid)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
call write_netcdf_rtime_3d(outvar_h, ntime, ttime, bdtime)

! companions
varname = 'cin'; vunits = 'J kg-1'; longname = 'Convective Inhibition'
standardname = 'atmosphere_convective_inhibition_wrt_surface'; cellmethods = 'area: mean time: point'
fnameout = trim(dir_out)//trim(varname)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
call write_netcdf_rtime_3d(cin_h, ntime, ttime, bdtime)

varname = 'li'; vunits = 'K'; longname = 'Lifted Index'
standardname = 'temperature_difference_between_ambient_air_and_air_lifted_adiabatically_from_the_surface'
cellmethods = 'area: mean time: point'
fnameout = trim(dir_out)//trim(varname)//trim(outdom)//trim(freq)//'_'//trim(time_range(ttime,ntime))//'.nc'
call write_netcdf_rtime_3d(li_h, ntime, ttime, bdtime)

! back to the header's variable for the next year
varname = trim(adjustl(vaid)); vunits = trim(adjustl(vunts)); longname = trim(adjustl(lname))
standardname = trim(adjustl(stname)); cellmethods = trim(adjustl(cmethods))

deallocate(ttime, bdtime, outvar_h, cin_h, li_h)

end subroutine write_output
!
!-----------------------------------------------------------------------
!
end program read_wrfout

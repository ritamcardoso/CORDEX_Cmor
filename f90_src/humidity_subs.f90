module humidity_subs
!
! Moist thermodynamics shared by the programs: saturation vapour pressure and mixing ratio
! (Wexler / ITS-90 with the enhancement factor of moist air; mixture of liquid and ice), virtual
! temperature, exact LCL (Romps 2017), pseudo-equivalent potential temperature (Bolton 1980) and
! its inversion, and the pseudo-adiabat with ice. Used by RCM_sfc_hurs, RCM_sfc_hurscan,
! RCM_sfc_evspsblpot, RCM_sfc_cape and RCM_sfc_lcl (use humidity_subs). Compiled after datvar_s
! and before shared_subs_v2 (scripts/run_out_generic.sh). Double precision.
!
use datvar_s, only: epsilon
implicit none
!
contains
!
! ---------------------------------------------------------------------------------------
! Moist thermodynamics of a lifted parcel (RCM_sfc_cape): saturation mixing ratio,
! virtual temperature, exact LCL (Romps 2017), pseudo-equivalent potential temperature
! (Bolton 1980, eq. 43) and its inversion. Double precision.
! ---------------------------------------------------------------------------------------
!
pure function qvs_wexler(tk, pa) result(qs)
! saturation mixing ratio (kg kg-1) over water at tk (K) and pa (Pa): ITS-90 / Wexler
! saturation vapour pressure with the enhancement factor of Hardy (1998) (es_wexler_dt),
! as RCM_sfc_hurs and RCM_sfc_hurscan
real(kind=8), intent(in) :: tk, pa
real(kind=8) :: qs, dqs
call qvs_wexler_dt(tk, pa, qs, dqs)
end function qvs_wexler
!
!-----------------------------------------------------------------------
!
pure subroutine es_wexler_dt(tk, pa, es, des)
! saturation vapour pressure es (Pa) over water at tk (K) in moist air at pa (Pa) and its
! exact derivative des = d es / d tk (Pa K-1): ITS-90 formula of Wexler (1976) for water,
! times the enhancement factor of moist air (Greenspan 1976, ITS-90 coefficients of Hardy
! 1998: water 0 to 100 degC, and supercooled water -50 to 0 degC below 0 degC)
!   f = exp[ fa (1 - ew/pa) + exp(fb) (pa/ew - 1) ],  fa, fb cubics in t (degC)
! (f ~ 1.004 at 20 degC and 1000 hPa). Used by RCM_sfc_hurs, RCM_sfc_hurscan,
! qvs_wexler_dt (CAPE) and RCM_sfc_evspsblpot (Penman-Monteith es and its slope).
real(kind=8), intent(in) :: tk, pa
real(kind=8), intent(out) :: es, des
real(kind=8) :: dlnes, tc, fa, dfa, fb, dfb, eb, fact, dlnf, ew
real(kind=8), parameter :: a1=-2.8365744d3, a2=-6.028076559d3, a3=19.54263612d0, a4=-2.737830188d-2, &
                           a5=1.6261698d-5, a6=7.0229056d-10, a7=-1.8680009d-13, a8=2.7150305d0
real(kind=8), parameter :: fi1=3.62183d-4, fi2=2.6061244d-5, fi3=3.8667770d-7, fi4=3.8268958d-9, &
                           fi5=-10.7604d0, fi6=6.3987441d-2, fi7=-2.6351566d-4, fi8=1.6725084d-6
real(kind=8), parameter :: fw1=3.536240d-4, fw2=2.932836d-5, fw3=2.616898d-7, fw4=8.581361d-9, &
                           fw5=-10.75880d0, fw6=6.326813d-2, fw7=-2.536893d-4, fw8=6.340529d-7
tc = tk - 273.15d0
! Wexler / ITS-90 saturation vapour pressure and d ln(es) / dT
ew = exp(a1/tk**2 + a2/tk + a3 + a4*tk + a5*tk**2 + a6*tk**3 + a7*tk**4 + a8*log(tk))
dlnes = -2.d0*a1/tk**3 - a2/tk**2 + a4 + 2.d0*a5*tk + 3.d0*a6*tk**2 + 4.d0*a7*tk**3 + a8/tk
! enhancement factor: ln f = fa (1 - ew/pa) + exp(fb) (pa/ew - 1), fa and fb cubics in tc
if (tc < 0.d0) then                      ! supercooled water (Hardy 1998, -50 to 0 degC)
  fa  = fi1 + fi2*tc + fi3*tc**2 + fi4*tc**3
  dfa = fi2 + 2.d0*fi3*tc + 3.d0*fi4*tc**2
  fb  = fi5 + fi6*tc + fi7*tc**2 + fi8*tc**3
  dfb = fi6 + 2.d0*fi7*tc + 3.d0*fi8*tc**2
else
  fa  = fw1 + fw2*tc + fw3*tc**2 + fw4*tc**3
  dfa = fw2 + 2.d0*fw3*tc + 3.d0*fw4*tc**2
  fb  = fw5 + fw6*tc + fw7*tc**2 + fw8*tc**3
  dfb = fw6 + 2.d0*fw7*tc + 3.d0*fw8*tc**2
endif
eb   = exp(fb)
fact = exp(fa*(1.d0 - ew/pa) + eb*(pa/ew - 1.d0))
! d ln f / dT, with d ew / dT = ew dlnes
dlnf = dfa*(1.d0 - ew/pa) + eb*dfb*(pa/ew - 1.d0) - fa*ew*dlnes/pa - eb*(pa/ew)*dlnes
es  = ew*fact
des = es*(dlnes + dlnf)
end subroutine es_wexler_dt
!
!-----------------------------------------------------------------------
!
pure subroutine qvs_wexler_dt(tk, pa, qs, dqs)
! qvs_wexler and its exact derivative dqs = d qs / d tk (kg kg-1 K-1), for Newton
! iterations (t_from_theta_e); es and its derivative from es_wexler_dt
real(kind=8), intent(in) :: tk, pa
real(kind=8), intent(out) :: qs, dqs
real(kind=8) :: es, des
call es_wexler_dt(tk, pa, es, des)
if (es > 0.5d0*pa) then                  ! capped (very hot or low pressure): flat
  es = 0.5d0*pa; des = 0.d0
endif
qs  = epsilon*es/(pa - es)
dqs = epsilon*pa*des/(pa - es)**2
end subroutine qvs_wexler_dt
!
!-----------------------------------------------------------------------
!
pure function tvirt(tk, r) result(tv)
! virtual temperature (K) from the temperature and the mixing ratio r (kg kg-1)
real(kind=8), intent(in) :: tk, r
real(kind=8) :: tv
tv = tk*(1.d0 + r/epsilon)/(1.d0 + r)
end function tvirt
!
!-----------------------------------------------------------------------
!
pure function lambertw_m1(x) result(w)
! real Lambert W function, lower branch W_-1, for -1/e <= x < 0 (Halley iterations)
real(kind=8), intent(in) :: x
real(kind=8) :: w, ew, f, q, l1, l2
integer :: it
if (x <= -exp(-1.d0)) then
  w = -1.d0
  return
endif
if (x < -0.25d0) then
  q = -sqrt(2.d0*(1.d0 + exp(1.d0)*x))
  w = -1.d0 + q - q**2/3.d0 + 11.d0/72.d0*q**3
else
  l1 = log(-x); l2 = log(-l1)
  w = l1 - l2 + l2/l1
endif
do it = 1, 20
  ew = exp(w)
  f = w*ew - x
  q = w*ew + ew - (w + 2.d0)*f/(2.d0*w + 2.d0)
  if (abs(q) < 1.d-300) exit
  w = w - f/q
  if (abs(f) < 1.d-14*abs(x)) exit
enddo
end function lambertw_m1
!
!-----------------------------------------------------------------------
!
pure subroutine romps_lcl(pa, tk, r, zl, tl, pl)
! Exact lifting condensation level of a parcel (pressure pa, temperature tk, mixing
! ratio r), Romps (2017, J. Atmos. Sci. 74, 3891), liquid water:
!   zl: height of the LCL above the parcel (m), tl: its temperature (K), pl: pressure (Pa).
! A saturated (or supersaturated) parcel has its LCL at the parcel level.
! The saturation vapour pressure (pvs) is Romps' own (Rankine-Kirchhoff, pure water vapour),
! kept on purpose: the exact solution through the Lambert W function needs it. It differs
! from es_wexler_dt (Wexler x Hardy enhancement factor, used by hurs and the moist ascent in
! CAPE) by +0.35 to +0.6 % at 1000 hPa (-40 to 40 degC; 0.2-0.3 % at 500 hPa), mostly the
! enhancement factor. With the RH of es_wexler_dt the LCL would be ~6-8 m higher (~0.05 K).
real(kind=8), intent(in) :: pa, tk, r
real(kind=8), intent(out) :: zl, tl, pl
real(kind=8), parameter :: ttrip=273.16d0, ptrip=611.65d0, e0v=2.3740d6, ggr=9.81d0
real(kind=8), parameter :: rgasa=287.04d0, rgasv=461.d0, cva=719.d0, cvv=1418.d0, cvl=4119.d0
real(kind=8), parameter :: cpa=cva+rgasa, cpv=cvv+rgasv
real(kind=8) :: pv, qv, rgasm, cpm, al, bl, cl, pvs, arg, rh
pv = r*pa/(rgasa/rgasv + r)
qv = rgasa*pv/(rgasv*pa + (rgasa - rgasv)*pv)
rgasm = (1.d0 - qv)*rgasa + qv*rgasv
cpm = (1.d0 - qv)*cpa + qv*cpv
pvs = ptrip*(tk/ttrip)**((cpv - cvl)/rgasv)*exp((e0v - (cvv - cvl)*ttrip)/rgasv*(1.d0/ttrip - 1.d0/tk))
rh = pv/pvs
if (r <= 0.d0) then
  tl = 0.d0; zl = cpm*tk/ggr; pl = 0.d0
  return
endif
if (rh >= 1.d0) then
  zl = 0.d0; tl = tk; pl = pa
  return
endif
al = -(cpv - cvl)/rgasv + cpm/rgasm
bl = -(e0v - (cvv - cvl)*ttrip)/(rgasv*tk)
cl = bl/al
arg = rh**(1.d0/al)*cl*exp(cl)
tl = cl/lambertw_m1(arg)*tk
zl = cpm/ggr*(tk - tl)
pl = pa*(tl/tk)**(cpm/rgasm)
end subroutine romps_lcl
!
!-----------------------------------------------------------------------
!
pure function theta_e_bolton(tk, pa, r, tl) result(the)
! pseudo-equivalent potential temperature (K), Bolton (1980) eq. 43: tk, pa, r (kg kg-1)
! of the parcel and tl, its temperature at the LCL
real(kind=8), intent(in) :: tk, pa, r, tl
real(kind=8) :: the, rg
rg = 1000.d0*r
the = tk*(1.d5/pa)**(0.2854d0*(1.d0 - 0.28d-3*rg))*exp((3.376d0/tl - 0.00254d0)*rg*(1.d0 + 0.81d-3*rg))
end function theta_e_bolton
!
!-----------------------------------------------------------------------
!
pure function t_from_theta_e(the, pa, tguess) result(tk)
! temperature (K) of a saturated parcel at pa (Pa) with pseudo-equivalent potential
! temperature the: Newton iterations on ln theta_e_bolton(T, pa, qvs(T, pa), T) = ln the,
! starting from tguess (the parcel temperature at the level below). The derivative is
! exact (qvs_wexler_dt), so each iteration needs one saturation evaluation.
!   ln theta_e = ln T + kap ln(p0/p) + (3.376/T - 0.00254) rg (1 + 0.81e-3 rg)
!   kap = 0.2854 (1 - 0.28e-3 rg), rg = 1000 qs(T, p) (g kg-1)
real(kind=8), intent(in) :: the, pa, tguess
real(kind=8) :: tk, qs, dqs, rg, drg, lnp, aa, f0, f1, dt
integer :: it
tk = tguess
lnp = log(1.d5/pa)
do it = 1, 30
  call qvs_wexler_dt(tk, pa, qs, dqs)
  rg  = 1000.d0*qs
  drg = 1000.d0*dqs
  aa  = 3.376d0/tk - 0.00254d0
  f0  = log(tk) + 0.2854d0*(1.d0 - 0.28d-3*rg)*lnp + aa*rg*(1.d0 + 0.81d-3*rg) - log(the)
  f1  = 1.d0/tk - 0.2854d0*0.28d-3*lnp*drg - 3.376d0/tk**2*rg*(1.d0 + 0.81d-3*rg) &
        + aa*(1.d0 + 1.62d-3*rg)*drg
  if (f1 <= 0.d0) exit
  dt = -f0/f1
  dt = max(-20.d0, min(20.d0, dt))
  tk = tk + dt
  if (abs(dt) < 1.d-3) exit
enddo
end function t_from_theta_e
!
!-----------------------------------------------------------------------
!
! Parcel with ice (RCM_sfc_cape, cape_ice = 1): saturation over a mixture of liquid and ice,
! and the pseudo-adiabat (condensate removed as it forms) integrated in steps.
!
!   Ice fraction of the new condensate: fi = 0 at 0 degC and above, 1 at -40 degC and below,
!   linear in between.
!   e_i = e_w / S, S the water/ice saturation ratio of Ambaum (2020, QJRMS 146, 4252, eq. 20,
!   triple-point constants), e_w = es_wexler_dt (Wexler x Hardy enhancement factor):
!     S = (T0/T)**((cpl - cpi)/Rv) exp(Lm/(Rv T) - Lm0/(Rv T0)),  Lm = Lm0 + (cpl - cpi)(T - T0)
!   (the exponent as printed in the paper has the opposite sign: with it S would be 2.9 at
!   -40 degC instead of the 1.47 the paper gives). e_i is within 5e-4 of Murphy and Koop
!   (2005) from -40 to 0 degC. Mixture: e = (1 - fi) e_w + fi e_i.
!   Latent heats (Ambaum eqs. 15 and 18, triple-point heat capacities):
!     Lv = Lv0 - (cpl - cpv)(T - T0),  Ls = Lv0 + Lm0 - (cpi - cpv)(T - T0),  L = (1 - fi) Lv + fi Ls
!
! The step from (t1, p1) to p2 (first law for the dry air and the vapour, per kg of dry air,
! with the vapour that condenses removed at the parcel temperature; trapezoidal averages):
!   (cpd + r cpv)(T2 - T1) - Rd T ln(pd2/pd1) - r Rv T ln(e2/e1) + L (r2 - r1) = 0
! r = eps e/(p - e), pd = p - e. With fi = 0 this is the liquid pseudo-adiabat: within 0.08 K of
! Bolton's theta_e at 500 hPa, and 1-2 % more CAPE on Weisman-Klemp soundings. Steps of 0.1 in
! ln p (one step per model layer in most of the troposphere) and a tolerance of 1e-3 K differ
! from steps of 0.002 by less than 0.31 J kg-1 in CAPE and 0.004 K in LI.
!
pure subroutine es_mixed_dt(tk, pa, es, des, fi)
! saturation vapour pressure (Pa) of the parcel with ice, its derivative d es / d tk
! (Pa K-1) and the ice fraction fi of the condensate
real(kind=8), intent(in) :: tk, pa
real(kind=8), intent(out) :: es, des, fi
real(kind=8), parameter :: t0=273.16d0, tw=273.15d0, ti=233.15d0, rv=461.52d0, &
                           cpl=4220.d0, cpi=2097.d0, lm0=0.3334d6
real(kind=8) :: ew, dew, ei, dei, sr, lm, dfi
call es_wexler_dt(tk, pa, ew, dew)
if (tk >= tw) then
  es = ew; des = dew; fi = 0.d0
  return
endif
lm  = lm0 + (cpl - cpi)*(tk - t0)
sr  = (t0/tk)**((cpl - cpi)/rv)*exp(lm/(rv*tk) - lm0/(rv*t0))
ei  = ew/sr
dei = ei*(dew/ew + lm/(rv*tk**2))                ! d ln S / dT = -Lm / (Rv T**2)
if (tk <= ti) then
  fi = 1.d0; dfi = 0.d0
else
  fi = (tw - tk)/(tw - ti); dfi = -1.d0/(tw - ti)
endif
es  = (1.d0 - fi)*ew + fi*ei
des = (1.d0 - fi)*dew + fi*dei + dfi*(ei - ew)
end subroutine es_mixed_dt
!
!-----------------------------------------------------------------------
!
pure function qvs_mixed(tk, pa) result(qs)
! saturation mixing ratio (kg kg-1) of the parcel with ice (es_mixed_dt)
real(kind=8), intent(in) :: tk, pa
real(kind=8) :: qs, es, des, fi
call es_mixed_dt(tk, pa, es, des, fi)
es = min(es, 0.5d0*pa)
qs = epsilon*es/(pa - es)
end function qvs_mixed
!
!-----------------------------------------------------------------------
!
pure function t_pseudo_ice(t1, p1, p2) result(t2)
! temperature (K) at p2 (Pa) of the saturated parcel at (t1, p1) lifted along the pseudo-adiabat
! with ice (see above), in steps of at most 0.1 in ln p (95 hPa at 1000 hPa, 19 hPa at 200 hPa)
real(kind=8), intent(in) :: t1, p1, p2
real(kind=8) :: t2, ta, pa, pb, dlnp
integer :: n, is
dlnp = log(p1/p2)
n = max(1, ceiling(abs(dlnp)/0.1d0))
ta = t1; pa = p1
do is = 1, n
  pb = p1*exp(-dlnp*dble(is)/dble(n))
  ta = ice_step(ta, pa, pb)
  pa = pb
enddo
t2 = ta
end function t_pseudo_ice
!
!-----------------------------------------------------------------------
!
pure function ice_step(t1, p1, p2) result(t2)
! one step of t_pseudo_ice: the first-law equation solved for T2 (secant iterations)
real(kind=8), intent(in) :: t1, p1, p2
real(kind=8) :: t2, e1, r1, pd1, l1, fi1, des, xa, xb, fa, fb, xn, gam
real(kind=8), parameter :: rd=287.04d0, cpd=1005.7d0, cpv=1888.d0, t0=273.16d0, &
                           lv0=2.501d6, lm0=0.3334d6, cpl=4220.d0, cpi=2097.d0
real(kind=8) :: rv
integer :: it
rv = rd/epsilon
call es_mixed_dt(t1, p1, e1, des, fi1)
e1 = min(e1, 0.5d0*p1)
r1 = epsilon*e1/(p1 - e1); pd1 = p1 - e1
l1 = (1.d0 - fi1)*(lv0 - (cpl - cpv)*(t1 - t0)) + fi1*(lv0 + lm0 - (cpi - cpv)*(t1 - t0))
! first guess: moist-adiabatic lapse rate in ln p at (t1, p1)
gam = (rd*t1 + l1*r1)/(cpd + l1**2*r1/(rv*t1**2))
xb = t1 + gam*log(p2/p1)
xa = xb + 0.5d0
fa = resid(xa); fb = resid(xb)
do it = 1, 30
  if (abs(fb - fa) < 1.d-30) exit
  xn = xb - fb*(xb - xa)/(fb - fa)
  xa = xb; fa = fb
  xb = xn; fb = resid(xb)
  if (abs(xb - xa) < 1.d-3) exit
enddo
t2 = xb
contains
  pure function resid(tt) result(f)
  real(kind=8), intent(in) :: tt
  real(kind=8) :: f, e2, r2, pd2, l2, fi2, d2
  call es_mixed_dt(tt, p2, e2, d2, fi2)
  e2 = min(e2, 0.5d0*p2)
  r2 = epsilon*e2/(p2 - e2); pd2 = p2 - e2
  l2 = (1.d0 - fi2)*(lv0 - (cpl - cpv)*(tt - t0)) + fi2*(lv0 + lm0 - (cpi - cpv)*(tt - t0))
  f = (cpd + 0.5d0*(r1 + r2)*cpv)*(tt - t1) - rd*0.5d0*(t1 + tt)*log(pd2/pd1) &
      - 0.5d0*(r1 + r2)*rv*0.5d0*(t1 + tt)*log(e2/e1) + 0.5d0*(l1 + l2)*(r2 - r1)
  end function resid
end function ice_step
!
!-----------------------------------------------------------------------
!
end module humidity_subs

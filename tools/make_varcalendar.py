#!/usr/bin/env python3
"""
tools/make_varcalendar.py — build the variable-calendar programs of f90_src_varcalendar
from those of f90_src (and f90_src_varcalendar/parallel from f90_src_parallel).

The programs of f90_src loop over whole calendar years (months imonth..nmonths, days 1..31,
hours ihour..23). The variable-calendar programs process, for each year yeari..yearf, only
the part of the year inside the simulation period sim_start..sim_end of the grid ini
(time_chunk and set_time_step in f90_src/shared_io_subs.f90):

    do vc_year = yeari, yearf
      if (.not. time_chunk(vc_year, <step>, <interval>)) cycle
      year = vc_year
      ...
      loop_h: do vc_ifl = 1, vc_nfiles
        call set_time_step(vc_ifl)
        ... (the body of the hour loop of f90_src, unchanged) ...
      enddo loop_h
      call write_output            ! one file per year (chunk)
    enddo

The conversion is mechanical: the year/month/day/hour loops of the f90_src template are
replaced as above, everything else is kept. A program that does not follow the template is
reported and left out (convert it by hand: HAND below lists the ones that are).

Usage:
  tools/make_varcalendar.py            write f90_src_varcalendar (and its parallel/)
  tools/make_varcalendar.py --check    exit 1 if f90_src_varcalendar differs from what
                                       the conversion of f90_src gives (after a change
                                       in f90_src, run it without --check)
"""
import os, re, sys, difflib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC, PAR = os.path.join(ROOT, 'f90_src'), os.path.join(ROOT, 'f90_src_parallel')
OUT = os.path.join(ROOT, 'f90_src_varcalendar')
OUTPAR = os.path.join(OUT, 'parallel')

# no time loop: built from f90_src (run_out_generic.sh falls back to it)
NO_TIME = ('RCM_fx_', 'RCM_sfc_mrsofc')
# kept for reference only in f90_src, not used by any varset: not converted
NOT_USED = {'RCM_sfc_mrsfl_monthly', 'RCM_sfc_mrsol_monthly', 'RCM_sfc_tsl_monthly',
            'RCM_sfc_xtrm_daily', 'RCM_sfc_xtrm_monthly'}
# converted by hand in f90_src_varcalendar (not regenerated, not checked)
HAND = {'RCM_sfc_xtrm', 'RCM_sfc_wsgsmax'}

NOTE = """!
! Variable-calendar version (f90_src_varcalendar) of f90_src/{name}.f90, made by
! tools/make_varcalendar.py: for each year yeari..yearf, only the time steps inside the
! simulation period sim_start..sim_end of the grid ini (time_chunk, set_time_step).
! Change f90_src/{name}.f90 and rerun tools/make_varcalendar.py rather than this file.
!
"""


class Skip(Exception):
    pass


def find(lines, pat, start=0, stop=None):
    r = re.compile(pat)
    for i in range(start, len(lines) if stop is None else stop):
        if r.search(lines[i]):
            return i
    return -1


def only(lines, allowed, what):
    """every line must be blank, a comment, or match one of the patterns"""
    for l in lines:
        s = l.strip()
        if not s or s.startswith('!'):
            continue
        if not any(re.fullmatch(a, s, re.I) for a in allowed):
            raise Skip(f'{what}: unexpected line "{s}"')


def convert(name, text):
    L = text.split('\n')

    # --- interval programs (accumulated fields, interval means): they read the next file
    i = find(L, r'^\s*yearf\s*=\s*yeari\s*\+\s*1\s*$')
    interval = i >= 0
    if interval:
        del L[i]

    # --- the ish offset (hours since iniyear) is set by time_chunk
    i = find(L, r'^! Determine starting hour offset')
    if i >= 0:
        j = find(L, r'^endif\s*$', i)
        if j < 0 or j - i > 20:
            raise Skip('ish block not found')
        del L[i:j + 1]
        i = find(L, r'^\s*if \(ihour > 0\) ish = ish \+ ihour - 1')
        if i < 0:
            raise Skip('no "if (ihour > 0) ish" line')
        del L[i]
    # a file read before the time loop (e.g. grid information): the first file of the
    # simulation instead of the first one of yeari
    i = find(L, r'^\s*amonth = pad_int\(imonth, 2\)\s*$')
    if i >= 0:
        blk = [l.strip() for l in L[i:i + 4]]
        if blk != ['amonth = pad_int(imonth, 2)', 'aday = pad_int(iday, 2)', 'ahour = pad_int(ihour, 2)',
                   "write(ayear, '(i4)') yeari"]:
            raise Skip('first-file date before the loops not in the expected form')
        L[i:i + 4] = ['call sim_period                 ! the first wrfout file of the simulation (sim_start)',
                      'ayear = sim_start(1:4); amonth = sim_start(6:7); aday = sim_start(9:10); ahour = sim_start(12:13)']
    # the start date strings of the f90_src template (not used)
    for v in ('amonthi', 'adayi', 'ahouri'):
        i = find(L, r'^\s*' + v + r'\s*=\s*pad_int\(i(month|day|hour), 2\)\s*$')
        if i >= 0:
            del L[i]
    i = find(L, r'^! Initial padding for start dates\s*$')
    if i >= 0 and not L[i + 1].strip():
        del L[i:i + 2]
    elif i >= 0:
        del L[i]

    # --- year loop
    iy = find(L, r'^do year = yeari, yearf\s*(,\s*1)?\s*$')
    if iy < 0:
        raise Skip('no "do year = yeari, yearf" loop')

    # --- hour loop: the step between the files
    ih = find(L, r'^\s*(loop_h:\s*)?do hour = ihour, ', iy)
    if ih < 0:
        raise Skip('no "loop_h: do hour" loop')
    hl = re.sub(r'^loop_h:\s*', '', L[ih].strip())
    if re.fullmatch(r'do hour = ihour, nhours-1,1', hl) or re.fullmatch(r'do hour = ihour, 23', hl):
        step = '1'
    elif re.fullmatch(r'do hour = ihour, 23, ostep', hl):
        step = 'ostep'
    else:
        raise Skip(f'hour loop "{hl}"')
    if interval and step != '1':
        raise Skip('interval values with a step other than 1 hour')

    L[iy] = 'do vc_year = yeari, yearf'
    L[iy + 1:iy + 1] = [
        '  ! the part of the year inside sim_start..sim_end (nothing to do if none)',
        f"  if (.not. time_chunk(vc_year, {step}, .{'true' if interval else 'false'}.)) cycle",
        '  year = vc_year']

    # --- between the year loop and the hour loop: drop the per-run time bookkeeping of
    #     the f90_src template, keep the rest (allocations ...)
    ih = find(L, r'^\s*(loop_h:\s*)?do hour = ihour, ', iy)
    im = find(L, r'^\s*do month = imonth, nmonths', iy, ih)
    if im < 0:
        raise Skip('no month loop')
    seg = L[iy + 4:im]
    out, k = [], 0
    while k < len(seg):
        s = seg[k].strip()
        # if(year == yearf)then / nmonths=1 / endif
        if re.fullmatch(r'if\s*\(year == yearf\)\s*then', s):
            e = k + 1
            while seg[e].strip().lower() != 'endif':
                e += 1
            only(seg[k + 1:e], [r'nmonths\s*=\s*1'], 'year == yearf block')
            k = e + 1
            continue
        if re.fullmatch(r'ntime\s*=\s*mydays\s*\*\s*nhours', s) or re.fullmatch(r'ntime\s*=\s*n_time_steps\(year, imonth, nmonths, ihour, (ostep|1)\)', s):
            k += 1
            continue
        if re.fullmatch(r'if \(ihour > 0\) then', s):
            e = k + 1
            while seg[e].strip().lower() != 'endif':
                e += 1
            only(seg[k + 1:e], [r'nhours\s*=\s*nhours-ihour\+1', r'ntime\s*=\s*ntime - ihour \+ 1'], 'ihour block')
            k = e + 1
            continue
        if not s.startswith('!') and (re.search(r'\bntime\s*=', s) or re.search(r'\b(nmonths|imonth|ihour)\b', s)):
            raise Skip(f'time line before the loops: "{s}"')
        out.append(seg[k])
        k += 1
    L[iy + 4:im] = out

    # --- month/day/hour loop headers -> one loop over the files of the chunk
    im = find(L, r'^\s*do month = imonth, nmonths', iy)
    ih = find(L, r'^\s*(loop_h:\s*)?do hour = ihour, ', im)
    ii = find(L, r'^\s*infile\s*=\s*trim\((filename\)|dir_in\).*)\s*$', ih)
    if ii < 0 or ii - ih > 8:
        raise Skip('no "infile = ..." after the hour loop')
    # end of the hour loop (before the headers are replaced)
    depth, ie = 0, -1
    for k in range(ih, len(L)):
        s = L[k].split('!')[0].strip()
        if re.match(r'(\w+\s*:\s*)?do\b(?!\s*=)', s, re.I):
            depth += 1
        elif re.match(r'end\s*do\b', s, re.I):
            depth -= 1
            if depth == 0:
                ie = k
                break
    if ie < 0:
        raise Skip('end of the hour loop not found')
    hdr = L[im:ii + 1]
    # the year == yearf block of the interval programs (ndays=1, nhours=1)
    hdr2, k = [], 0
    while k < len(hdr):
        s = hdr[k].strip()
        if re.fullmatch(r'if\s*\(year == yearf\)\s*then', s):
            e = k + 1
            while hdr[e].strip().lower() != 'endif':
                e += 1
            only(hdr[k + 1:e], [r'ndays\s*=\s*1', r'nhours\s*=\s*1'], 'year == yearf block')
            k = e + 1
            continue
        hdr2.append(hdr[k])
        k += 1
    only(hdr2, [r'do month = imonth, nmonths\s*(,\s*1)?', r'ndays\s*=\s*days\(month\)',
                r'amonth\s*=\s*pad_int\(month, 2\)', r'write\(\*,\*\)\s*year,\s*month',
                r"write\(\*,\*\) 'Processing Year: ', year, ' Month: ', month",
                r'do day = 1, (ndays|days\(month\))', r'aday(_pad)?\s*=\s*pad_int\(day, 2\)',
                r'(loop_h:\s*)?do hour = .*', r'ahour\s*=\s*pad_int\(hour, 2\)',
                r"(filename|infile) = trim\(dir_in\)//trim\(wrfile\)//'_d0'//trim\(dom\)//'_'//ayear//'-'//amonth//'-'//aday(_pad)?//'_'//ahour//'_00_00'",
                r'infile\s*=\s*trim\(filename\)'], 'loop headers')
    ind = re.match(r'\s*', L[im]).group(0)
    # loop ends: the hour loop, then (ihour=0, nhours=24) the day and month loops
    n = 0
    k = ie + 1
    while n < 2:
        s = L[k].split('!')[0].strip()
        if re.fullmatch(r'end\s*do\b.*', s, re.I):
            n += 1
        elif s and not re.fullmatch(r'ihour\s*=\s*0|nhours\s*=\s*24', s):
            raise Skip(f'after the end of the hour loop: "{s}"')
        k += 1
    L[ie] = re.match(r'\s*', L[ie]).group(0) + 'enddo loop_h    ! end of the files of the chunk'
    del L[ie + 1:k]
    L[im:ii + 1] = [
        ind + '! Loop over the files of the chunk: set_time_step sets year, month, day, hour,',
        ind + '! ayear, amonth, aday, ahour and infile',
        ind + 'loop_h: do vc_ifl = 1, vc_nfiles',
        ind + '  call set_time_step(vc_ifl)']

    ie = find(L, r'^\s*enddo loop_h    ! end of the files of the chunk', im)

    # --- interval programs: write each year (chunk) inside the year loop
    iyend = find(L, r'^enddo\s*(!.*)?$', ie)
    if iyend < 0:
        raise Skip('end of the year loop not found')
    if interval:
        iw = find(L, r'^call write_\w*output\s*$', iyend)
        ic = find(L, r'^contains\s*$', iyend)
        if iw < 0 or (0 <= ic < iw):
            raise Skip('interval program without "call write_output" after the year loop')
        if find(L, r'^\s*call write_\w*output', ie, iyend) >= 0:
            raise Skip('interval program that also writes inside the year loop')
        only(L[iyend + 1:iw], [], 'between the year loop and call write_output')
        wcall = L[iw].strip()
        del L[iyend + 1:iw + 1]
        L[iyend:iyend] = ['  ' + wcall + '              ! one file per year (chunk)']
    else:
        if find(L, r'^\s*call write_\w*output', ie, iyend) < 0:
            raise Skip('no "call write_output" in the year loop')

    # --- interval programs: it = 0 again at each chunk (time_chunk), so arrays allocated
    #     once under "if (it == 0)" (e.g. cosalp) are allocated only if they are not yet
    if interval:
        k = 0
        while k < len(L):
            if re.match(r'\s*if\s*\(\s*it\s*==\s*0\s*\)\s*then', L[k]):
                d, j = 1, k + 1
                while d > 0:
                    s = L[j].split('!')[0].strip().lower()
                    if re.match(r'if\s*\(.*\)\s*then$', s):
                        d += 1
                    elif re.match(r'end\s*if$', s):
                        d -= 1
                    m = re.match(r'(\s*)allocate\((\w+)\(', L[j])
                    if m and m.group(2) not in ('ttime', 'bdtime') and not m.group(2).startswith('outvar_h'):
                        L[j] = f'{m.group(1)}if (.not. allocated({m.group(2)})) {L[j].strip()}'
                    j += 1
                k = j
            else:
                k += 1

    # --- file names: no time step left (e.g. daily output of a run shorter than a day)
    t = '\n'.join(L)
    t = re.sub(r'time_label\(\s*(\w+)\(1\)\s*,\s*\1\(\s*(\w+)\s*\)\s*\)', r'time_range(\1,\2)', t)

    # --- nothing of the old loops may be left
    main = t[:t.find('\ncontains')] if '\ncontains' in t else t
    for w in ['nmonths', 'imonth', 'ihour', r'do month', r'do day', 'n_time_steps']:
        m = re.search(r'^(?!\s*!).*\b' + w + r'\b.*$', main, re.M)
        if m:
            raise Skip(f'left after the conversion: "{m.group(0).strip()}"')

    # --- note at the top (after the program line)
    a = t.index('\n') + 1
    t = t[:a] + NOTE.format(name=name).lstrip('\n') + t[a:]
    return t


def targets():
    out = []
    for d, o in [(SRC, OUT), (PAR, OUTPAR)]:
        for f in sorted(os.listdir(d)):
            if not (f.startswith('RCM_') and f.endswith('.f90')):
                continue
            name = f[:-4]
            if name.startswith(NO_TIME) or name in NOT_USED or name in HAND:
                continue
            out.append((name, os.path.join(d, f), os.path.join(o, f)))
    return out


def main():
    check = '--check' in sys.argv
    bad, diff, n = [], [], 0
    for name, src, dst in targets():
        try:
            new = convert(name, open(src).read())
        except Skip as e:
            bad.append(f'{os.path.relpath(src, ROOT)}: {e}')
            continue
        n += 1
        if check:
            old = open(dst).read() if os.path.exists(dst) else ''
            if old != new:
                diff.append(os.path.relpath(dst, ROOT))
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            open(dst, 'w').write(new)
    for b in bad:
        print('not converted:', b)
    if check:
        for d in diff:
            print('out of step with f90_src:', d)
        if not diff and not bad:
            print(f'f90_src_varcalendar: in step with f90_src ({n} programs; by hand: {", ".join(sorted(HAND))}).')
        sys.exit(1 if diff or bad else 0)
    print(f'{n} programs written to f90_src_varcalendar' + (f', {len(bad)} not converted' if bad else ''))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()

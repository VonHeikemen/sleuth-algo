" sleuth.vim - Heuristically set buffer options
" Maintainer:   Tim Pope <http://tpo.pe/>
" Version:      2.0
" GetLatestVimScripts: 4375 1 :AutoInstall: sleuth.vim

if exists("g:loaded_sleuth") || v:version < 700 || &cp
  finish
endif

let g:loaded_sleuth = 1
lockvar g:loaded_sleuth

function! DetectIndent()
  if &buftype ==# 'help' || bufname('%') ==# ''
    echo ''
    return
  endif

  let detected = {}
  let detected.filetype = &filetype
  let detected.tabstop = &tabstop

  let lines = getline(1, 1024)
  let result = s:Guess(detected, lines)

  for [opt, val] in items(result.buf_options)
    if val == -1
      continue
    endif

    call setbufvar('', '&' . opt, val)
  endfor
endfunction

function! s:Guess(detected, lines) abort
  let has_heredocs = a:detected.filetype =~# '^\%(perl\|php\|ruby\|[cz]\=sh\|bash\)$'
  let options = {}
  let heuristics = {'spaces': 0, 'hard': 0, 'soft': 0, 'checked': 0, 'indents': {}}
  let tabstop = a:detected.tabstop
  let softtab = repeat(' ', tabstop)
  let waiting_on = ''
  let prev_indent = -1
  let prev_line = ''

  for line in a:lines
    if len(waiting_on)
      if line =~# waiting_on
        let waiting_on = ''
        let prev_indent = -1
        let prev_line = ''
      endif
      continue
    elseif line =~# '^\s*$'
      continue
    elseif a:detected.filetype ==# 'python' && prev_line[-1:-1] =~# '[[\({]'
      let prev_indent = -1
      let prev_line = ''
      continue
    elseif line =~# '^=\w' && line !~# '^=\%(end\|cut\)\>'
      let waiting_on = '^=\%(end\|cut\)\>'
    elseif line =~# '^@@\+ -\d\+,\d\+ '
      let waiting_on = '^$'
    elseif line !~# '[/<"`]'
      " No need to do other checks
    elseif line =~# '^\s*/\*' && line !~# '\*/'
      let waiting_on = '\*/'
    elseif line =~# '^\s*<\!--' && line !~# '-->'
      let waiting_on = '-->'
    elseif line =~# '^[^"]*"""'
      let waiting_on = '^[^"]*"""'
    elseif a:detected.filetype ==# 'go' && line =~# '^[^`]*`[^`]*$'
      let waiting_on = '^[^`]*`[^`]*$'
    elseif has_heredocs
      let waiting_on = matchstr(line, '<<\s*\([''"]\=\)\zs\w\+\ze\1[^''"`<>]*$')
      if len(waiting_on)
        let waiting_on = '^' . waiting_on . '$'
      endif
    endif

    let indent = len(matchstr(substitute(line, '\t', softtab, 'g'), '^ *'))
    if line =~# '^\t'
      let heuristics.hard += 1
    elseif line =~# '^' . softtab
      let heuristics.soft += 1
    endif
    if line =~# '^  '
      let heuristics.spaces += 1
    endif
    let increment = prev_indent < 0 ? 0 : indent - prev_indent
    let prev_indent = indent
    let prev_line = line
    if increment > 1 && (increment < 4 || increment % 4 == 0)
      if has_key(heuristics.indents, increment)
        let heuristics.indents[increment] += 1
      else
        let heuristics.indents[increment] = 1
      endif
      let heuristics.checked += 1
    endif
    if heuristics.checked >= 32 && (heuristics.hard > 3 || heuristics.soft > 3) && get(heuristics.indents, increment) * 2 > heuristics.checked
      if heuristics.spaces
        break
      elseif !exists('no_space_indent')
        let no_space_indent = stridx("\n" . join(a:lines, "\n"), "\n  ") < 0
        if no_space_indent
          break
        endif
      endif
      break
    endif
  endfor

  let max_frequency = 0
  for [shiftwidth, frequency] in items(heuristics.indents)
    if frequency > max_frequency || frequency == max_frequency && +shiftwidth < get(options, 'shiftwidth')
      let options.shiftwidth = +shiftwidth
      let max_frequency = frequency
    endif
  endfor

  if heuristics.hard && !heuristics.spaces
    let options = {'expandtab': 0, 'shiftwidth': 0}
  elseif heuristics.hard > heuristics.soft
    let options.expandtab = 0
    let options.tabstop = tabstop
  else
    if heuristics.soft
      let options.expandtab = 1
    endif

    if heuristics.hard 
      let options.tabstop = tabstop
    elseif !&g:shiftwidth && has_key(options, 'shiftwidth')
      let options.tabstop = options.shiftwidth
      let options.shiftwidth = 0
    endif
  endif

  return {'buf_options': options}
endfunction

command! Sleuth call DetectIndent()


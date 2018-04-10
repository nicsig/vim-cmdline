if exists('g:autoloaded_cmdline')
    finish
endif
let g:autoloaded_cmdline = 1

" TODO:{{{
" If we change the first command in the cycle `C-g v`, it should be changed here
" too. Otherwise:
"
"     :
"
"     C-g
"         → vim //gj ~/.vim/**/*.vim ~/.vim/**/vim.snippets ~/.vim/vimrc
"         ✔
"
"     C-g
"         → vim //gj ~/.vim/**/*.vim ~/.vim/**/vim.snippets ~/.vim/vimrc
"         ✘
"         we should have the next command in the cycle
"
" Find a way to define `s:DEFAULT_CMD` as whatever first command is in the cycle
" `C-g v`, at any given time.
"}}}
let s:DEFAULT_CMD = { 'cmd' : 'noa vim //gj ~/.vim/**/*.vim ~/.vim/**/vim.snippets ~/.vim/vimrc \| cw', 'pos' : 10 }

fu! cmdline#auto_uppercase() abort "{{{1

" We define abbreviations in command-line mode to automatically replace
" a custom command name written in lowercase with uppercase characters.

    let commands = getcompletion('[A-Z]?*', 'command')

    for cmd in commands
        let lcmd  = tolower(cmd)
        exe printf('cnorea <expr> %s
        \               getcmdtype() is# '':'' && getcmdline() =~# ''\v^%(%(tab<Bar>vert%[ical])\s+)?%s$''
        \               ?     %s
        \               :     %s
        \          ', lcmd, lcmd, string(cmd), string(tolower(cmd))
        \         )
    endfor
endfu

fu! s:capture_subpatterns() abort "{{{1
    " If  we're on  the Ex  command-line (:),  we try  and guess  whether it
    " contains a substitution command.
    let cmdline   = getcmdline()
    let range     = matchstr(cmdline, '[%*]\|[^,]*,[^,]*\zes')
    let cmdline   = substitute(cmdline, '^\V'.escape(range, '\').'\vs.\zs\\v', '', '')
    let separator = cmdline =~# 's/' ? '/' : 's:' ? ':' : ''

    " If there's no substitution command we don't modify the command-line.
    if empty(separator)
        return ''
    endif

    " If there's one, we extract the pattern.
    let pat = split(cmdline, separator)[1]

    " If  the pattern  contains  word  boundaries (\<,  \>),  we remove  the
    " backslash,  because we're  going to  enable the  very magic  mode.  We
    " could have  word boundaries when  we hit * on  a word in  normal mode,
    " then insert the search register in the pattern field.
    if pat =~# '^\\<\|\\>'
        let pat = substitute(pat, '^\\<', '<', 'g')
        let pat = substitute(pat, '\\>', '>', 'g')
    endif

    " Then,  we  extract  from  the pattern  words  between  underscores  or
    " uppercase letters; e.g.:
    "
    "         'OneTwoThree'   → ['One', 'Two', 'Three']
    "         'one_two_three' → ['one', 'two', 'three']
    let subpatterns = split(pat, pat =~# '_' ? '_' : '\ze\u')

    " Finally we return the keys to type.
    "
    "         join(map(subpatterns, '…'), '…')
    "
    " … evaluates to  the original pattern,  with the addition  of parentheses
    " around the subpatterns:
    "
    "            (One)(Two)(Three)
    "      or    (one)_(two)_(three)
    let new_cmdline = range.'s/\v'.join(map(subpatterns, { i,v -> '('.v.')' }), pat =~# '_' ? '_' : '') . '//g'

    " Before returning the  keys, we position the cursor between  the last 2
    " slashes.
    return "\<c-e>\<c-u>".new_cmdline
    \     ."\<c-b>".repeat("\<right>", strchars(new_cmdline, 1)-2)
endfu

fu! cmdline#chain() abort "{{{1
    " Do NOT write empty lines in this function (gQ → E501, E749).
    let cmdline = getcmdline()
    let pat2cmd = {
    \              '(g|v).*(#@<!#|nu%[mber])' : [ ''         , 0 ],
    \              '(ls|files|buffers)!?'     : [ 'b '       , 0 ],
    \              'chi%[story]'              : [ 'sil col ' , 1 ],
    \              'lhi%[story]'              : [ 'sil lol ' , 1 ],
    \              'marks'                    : [ 'norm! `'  , 1 ],
    \              'old%[files]'              : [ 'e #<'     , 1 ],
    \              'undol%[ist]'              : [ 'u '       , 1 ],
    \              'changes'                  : [ "norm! g;\<s-left>"     , 1 ],
    \              'ju%[mps]'                 : [ "norm! \<c-o>\<s-left>" , 1 ],
    \             }
    for [pat, cmd ] in items(pat2cmd)
        let [ keys, nomore ] = cmd
        if cmdline =~# '\v\C^'.pat.'$'
            if nomore
                let more_save = &more
                " when  I execute  `:[cl]chi`, don't  populate the  command-line
                " with `:sil [cl]ol`  if the qf stack doesn't have  at least two
                " qf lists
                if   (pat is# 'chi%[story]' || pat is# 'lhi%[story]')
                \  && get(getqflist({'nr': '$'}), 'nr', 0) <= 1
                    return
                endif
                " allow Vim's pager to display the full contents of any command,
                " even if it takes more than one screen; don't stop after the first
                " screen to display the message:    -- More --
                set nomore
                call timer_start(0, {-> execute('set '.(more_save ? '' : 'no').'more')})
            endif
            return feedkeys(':'.keys, 'in')
        endif
    endfor
    if cmdline =~# '\v\C^(dli|il)%[ist]\s+'
        call feedkeys(':'.cmdline[0].'j  '.split(cmdline, ' ')[1]."\<s-left>\<left>", 'in')
    elseif cmdline =~# '\v\C^(cli|lli)'
        call feedkeys(':sil '.repeat(cmdline[0], 2).' ', 'in')
    endif
endfu

fu! cmdline#cycle(is_fwd) abort "{{{1
    let cmdline = getcmdline()

    if getcmdtype() isnot# ':'
        return cmdline
    endif

    " try to find the cycle to which the current command line belongs
    let i = 1
    while i <= s:nb_cycles
        if has_key(s:cycle_{i}, cmdline)
            break
        endif
        let i += 1
    endwhile
    " now `i` stores, either:
    "
    "     • the index of the cycle to which the command line belong
    " OR
    "     • a number greater than the number of installed cycles
    "
    "       if this  is the case,  since there's no  cycle to use,  we'll simply
    "       return the default command stored in `s:DEFAULT_CMD`

    if a:is_fwd
        call setcmdpos(
                    \   i <= s:nb_cycles
                    \ ?      s:cycle_{i}[cmdline].pos
                    \ :      s:DEFAULT_CMD.pos
                    \ )
        return i <= s:nb_cycles
           \ ?     s:cycle_{i}[cmdline].new_cmd
           \ :     s:DEFAULT_CMD.cmd
    else
        if i <= s:nb_cycles
            " get the previous command in the cycle,
            " and the position of the cursor on the latter
            let prev_cmd =   keys(filter(deepcopy(s:cycle_{i}), { k,v -> v.new_cmd is# cmdline }))[0]
            let prev_pos = values(filter(deepcopy(s:cycle_{i}), { k,v -> v.new_cmd is# prev_cmd }))[0].pos
            call setcmdpos(prev_pos)
            return prev_cmd
        else
            call setcmdpos(s:DEFAULT_CMD.pos)
            return s:DEFAULT_CMD.cmd
        endif
    endif
endfu

fu! cmdline#cycle_install(cmds) abort "{{{1
    let s:nb_cycles = get(s:, 'nb_cycles', 0) + 1
    " It's important to make a copy of the arguments, otherwise{{{
    " we   would   get   a   weird    result   in   the   next   invocation   of
    " `map()`. Specifically, in the  last item of the  transformed list. This is
    " probably  because the  same list  (a:cmds) would  be mentioned  in the  1st
    " argument of `map()`, but also in the 2nd one.
    "}}}
    let cmds = deepcopy(a:cmds)

    " Goal:{{{
    " Produce a dictionary whose keys are the commands in a cycle (a:cmds),
    " and whose values are sub-dictionaries.
    " Each one of the latter contains 2 keys:
    "
    "         • new_cmd: the new command which should replace the current one
    "         • pos:     the position on the latter
    "
    " The final dictionary should be stored in a variable such as `s:cycle_42`,
    " where 42 is the number of cycles installed so far.
    "}}}
    " Why do it?{{{
    " This dictionary will be used as a FSM to transit from the current command
    " to a new one.
    "}}}
    " How do we achieve it?{{{
    " 2 steps:
    "
    "     1. transform the list of commands into a list of sub-dictionaries
    "        (with the keys `new_cmd` and `pos`) through an invocation of
    "        `map()`
    "
    "     2. progressively build the dictionary `s:cycle_42` with a `for`
    "        loop, using the previous sub-dictionaries as values, and the
    "        original commands as keys
    "}}}
    " Alternative:{{{
    " (a little slower)
    "
    "         let s:cycle_{s:nb_cycles} = {}
    "         let i = 0
    "         for cmd in cmds
    "             let key      = substitute(cmd, '@', '', '')
    "             let next_cmd = a:cmds[(i+1)%len(a:cmds)]
    "             let pos      = stridx(next_cmd, '@')+1
    "             let value    = {'cmd': substitute(next_cmd, '@', '', ''), 'pos': pos}
    "             call extend(s:cycle_{s:nb_cycles}, {key : value})
    "             let i += 1
    "         endfor
    "}}}

    call map(cmds, { i,v -> { substitute(v, '@', '', '') :
    \                             { 'new_cmd' : substitute(a:cmds[(i+1)%len(a:cmds)], '@', '', ''),
    \                               'pos'     :      stridx(a:cmds[(i+1)%len(a:cmds)], '@')+1},
    \                             }
    \              })

    let s:cycle_{s:nb_cycles} = {}
    for dict in cmds
        call extend(s:cycle_{s:nb_cycles}, dict)
    endfor
endfu

fu! s:emit_cmdline_transformation_pre() abort "{{{1
    " We want to be able to undo the transformation.
    " We emit  a custom event, so  that we can  add the current line  to our
    " undo list in `vim-readline`.
    if exists('#User#CmdlineTransformationPre')
        doautocmd <nomodeline> User CmdlineTransformationPre
    endif
endfu

fu! cmdline#fix_typo(label) abort "{{{1
    let cmdline = getcmdline()
    let keys = {
             \   'cr': "\<bs>\<cr>",
             \   'z' : "\<bs>\<bs>()\<cr>",
             \ }[a:label]
    "                                    ┌─ do NOT replace this with `getcmdline()`:
    "                                    │
    "                                    │      when the callback will be processed,
    "                                    │      the old command line will be lost
    "                                    │
    call timer_start(0, {-> feedkeys(':'.cmdline.keys, 'in')})
    "    │
    "    └─ we can't send the keys right now, because the command hasn't been
    "       executed yet; from `:h CmdWinLeave`:
    "
    "               “Before leaving the command line.“
    "
    "       But it seems we can't modify the command either. Maybe it's locked.
    "       So, we'll reexecute a new fixed command with the timer.
endfu

fu! cmdline#pass_and_install_cycles(cycles) abort "{{{1
    for cycle in a:cycles
        call cmdline#cycle_install(cycle)
    endfor
endfu

fu! cmdline#remember(list) abort "{{{1
    augroup remember_overlooked_commands
        au!
        for cmd in a:list
            exe printf('
            \            au CmdlineLeave :
            \            if getcmdline() %s %s
            \|               call timer_start(0, {-> execute("echohl WarningMsg | echo %s | echohl NONE", "")})
            \|           endif
            \          ',     cmd.regex ? '=~#' : 'is#',
            \                 string(cmd.regex ? '^'.cmd.old.'$' : cmd.old),
            \                 string('['.cmd.new .'] was equivalent')
            \         )
        endfor
    augroup END
endfu

fu! s:replace_with_equiv_class() abort "{{{1
    return substitute(get(s:, 'orig_cmdline', ''), '\a', '[[=\0=]]', 'g')
endfu

fu! cmdline#reset_did_transform() abort "{{{1
    " called by `readline#undo()`
    " necessary to re-perform a transformation we've undone
    " by mistake
    unlet! s:did_transform
endfu

fu! s:search_outside_comments() abort "{{{1
    " we should probably save `cmdline` in  a script-local variable if we want
    " to cycle between several transformations
    if empty(&l:cms)
        return get(s:, 'orig_cmdline', '')
    endif
    let cml = '\V'.escape(matchstr(split(&l:cms, '%')[0], '\S*'), '\').'\v'
    return '\v%(^%(\s*'.cml.')@!.*)@<=\m'.get(s:, 'orig_cmdline', '')
endfu

fu! cmdline#toggle_editing_commands(enable) abort "{{{1
    try
        if a:enable
            call lg#map#restore(get(s:, 'my_editing_commands', []))
        else
            let lhs_list = map(split(execute('cno'), '\n'), { i,v -> matchstr(v, '\vc\s+\zs\S+') })
            call filter(lhs_list, { i,v -> !empty(v) })
            let s:my_editing_commands = lg#map#save('c', 0, lhs_list)

            for lhs in lhs_list
                exe 'cunmap '.lhs
            endfor
        endif
    catch
        return lg#catch_error()
    endtry
endfu

fu! cmdline#transform() abort "{{{1
    "     ┌─ number of times we've transformed the command line
    "     │
    let s:did_transform = get(s:, 'did_transform', -1) + 1
    augroup reset_did_tweak
        au!
        " TODO:
        " If we  empty the command line  without leaving it, the  counter is not
        " reset.  So,  once we've invoked this  function once, it can't  be used
        " anymore until we  leave the command line. Maybe we  should inspect the
        " command line instead.
        au CmdlineLeave  /,\?,:  unlet! s:did_transform s:orig_cmdline
        \|                       exe 'au! reset_did_tweak' | aug! reset_did_tweak
    augroup END

    let cmdtype = getcmdtype()
    let cmdline = getcmdline()
    if s:did_transform >= 1 && cmdtype is# ':'
        " If  we  invoke this  function  twice  on  the  same Ex  command  line,
        " it  shouldn't  do  anything  the  2nd  time.   Because  we  only  have
        " one transformation  atm (s:capture_subpatterns()), and  re-applying it
        " doesn't make sense.
        return ''
    endif

    if cmdtype =~# '[/?]'
        if get(s:, 'did_transform', 0) ==# 0
            let s:orig_cmdline = cmdline
        endif
        call s:emit_cmdline_transformation_pre()
        return "\<c-e>\<c-u>"
        \     .(s:did_transform % 2 ? s:replace_with_equiv_class() : s:search_outside_comments())

    elseif cmdtype =~# ':'
        call s:emit_cmdline_transformation_pre()
        return s:capture_subpatterns()
    else
        return ''
    endif
endfu


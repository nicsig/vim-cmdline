" Interface {{{1
fu! cmdline#cycle#substitute#install() abort "{{{2
    " What's this `let list = ...`?{{{
    "
    " Suppose you have this text:
    "
    "     pat1
    "     text
    "     pat2
    "     text
    "     pat3
    "     text
    "
    "     foo
    "     bar
    "     baz
    "
    " And you want to move `foo`, `bar` and `baz` after `pat1`, `pat2` and `pat3`.
    "
    "    1. yank the `foo`, `bar`, `baz` block
    "
    "    2. visually select the `pat1`, `pat2`, `pat3` block,
    "       then leave to get back to normal mode
    "
    "    3. invoke the substitution command after writing the pattern `pat\d`
    "}}}
    " If you think you can merge the two backticks substitutions, try your solution against these texts:{{{
    "
    "     example, ‘du --exclude='*.o'’ excludes files whose names end in
    "
    "     A block size  specification preceded by ‘'’ causes output  sizes to be displayed
    "}}}
    call cmdline#cycle#main#set('s',
        \ '<c-r>='.s:snr().'filetype_specific_substitute()<cr>§',
        \ '%s/`\(.\{-}\)''/`\1`/gce <bar> %s/‘\(.\{-}\)’/`\1`/gce',
        \ 'let list = split(@", "\n") <bar> *s/§\zs/\=remove(list, 0)/'
        \ )
endfu
" }}}1
" Core {{{1
fu! s:filetype_specific_substitute() abort "{{{2
    if &bt is# 'quickfix' && get(b:, 'qf_is_loclist', 0)
        if type(getloclist(0, {'context': 0}).context) == type({})
        \ && has_key(getloclist(0, {'context': 0}).context, 'populate')
            return getloclist(0, {'context': 0}).context.populate
        endif
    elseif &bt is# 'quickfix' && !get(b:, 'qf_is_loclist', 0)
        if type(getqflist({'context': 0}).context) == type({})
        \ && has_key(getqflist({'context': 0}).context, 'populate')
            return getqflist({'context': 0}).context.populate
        endif
    endif
    return '%s///g'
endfu
" }}}1
" Utilities {{{1
fu! s:snr() abort "{{{2
    return matchstr(expand('<sfile>'), '.*\zs<SNR>\d\+_')
endfu


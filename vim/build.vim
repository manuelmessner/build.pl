if exists('g:build_loaded')
    finish
endif
let g:build_loaded = 1

function! s:build(...)
    let l:fname = expand('%')
    let l:cmd = ""
    let l:args = a:000
    if a:0 != 0 && a:1 == 'quick'
        new
        setlocal colorcolumn= filetype= buftype=nofile
        let l:cmd = '.'
        let l:args = a:000[1:]
    end
    execute l:cmd.'! build '.l:fname.' '.join(l:args, ' ')
endfunction

" command! -bar -nargs=? -complete=file Build call s:build(<f-args>)
command! -bar -nargs=* Build call s:build(<f-args>)
command! -bar QBuild call s:build('quick')
command! -bar -nargs=* RBuild call s:build('--mode release', <f-args>)
command! -bar -nargs=* DBuild call s:build('--mode debug', <f-args>)

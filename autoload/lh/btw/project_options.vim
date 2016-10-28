"=============================================================================
" File:         autoload/lh/btw/project_options.vim               {{{1
" Author:       Luc Hermitte <EMAIL:hermitte {at} free {dot} fr>
"		<URL:http://github.com/LucHermitte/vim-build-tools-wrapper>
" Licence:      GPLv3
" Version:	0.7.0
let s:k_version = 0700
" Created:      06th Sep 2012
" Last Update:  28th Oct 2016
"------------------------------------------------------------------------
" Description:
"       API to help define project options
"
"------------------------------------------------------------------------
" Installation:
"       Drop this file into {rtp}/autoload/lh/btw
"       Requires Vim7+, lh-vim 3.1.6
" History:
"       v0.7.0
"       * Use new logging framework
"       v0.5.3
"       * Updated to new lh-vim-lib functions that create new splits, ignoring E36
"       v0.2.14:
"       * bug: When the project is organized with symbolic links, settings
"         weren't applied. e.g.
"          $$/
"          +-> repo/branches/B42
"          +-> sources/ -> symlink to $$/repo/branches/B42
"          +-> build/
"       v0.2.11:
"       * bug: don't prevent syntax highlighting & ft detection to be triggered
"         when launching vim with several files
"       v0.2.0: first factorization
" TODO:         «missing features»
" Example: Defining CTest verbosity from local_vimrc: {{{2
"    let s:root = expand("<sfile>:p:h")
"    let b:BTW_project_executable = { 'type': 'ctest', 'rule': '-VV'}
"    let g:sea_ctest_mode_menu = {
"          \ 'variable': 'sea_ctest_mode',
"          \ 'idx_crt_value': 0,
"          \ 'values': ['', '-V', '-VV'],
"          \ 'menu': {'priority': s:menu_priority.'30', 'name': s:menu_name.'CTest'},
"          \ '_root': s:root
"          \ }
"    function! g:sea_ctest_mode_menu.do_update() dict
"      let b:BTW_project_executable.rule = g:sea_ctest_mode
"    endfunction
"    call lh#btw#project_options#add_toggle_option(g:sea_ctest_mode_menu)
"
" Example: Defining compilation mode in a cmake environment from local_vimrc {{{2
" (two build dirs: build-d and build-r)
"    function! s:UpdateCompilDir()
"      let p = expand('%:p:h')
"      let s:build_dir = 'build-'.tolower(g:sea_compil_mode[0])
"      let b:BTW_compilation_dir    = s:project_root.'/'.s:build_dir
"    endfunction
"    let g:sea_compil_mode_menu = {
"          \ 'variable': 'sea_compil_mode',
"          \ 'idx_crt_value': 0,
"          \ 'values': ['Debug', 'Release'],
"          \ 'menu': {'priority': s:menu_priority.'20', 'name': s:menu_name.'M&ode'},
"          \ '_root': s:root
"          \ }
"
"    function! g:sea_compil_mode_menu.do_update() dict
"      let b:BTW_project_build_mode = g:sea_compil_mode
"      call s:UpdateCompilDir()
"      BTW rebuild
"      " we could also change the path to the project executable here as well
"    endfunction
"    call lh#btw#project_options#add_toggle_option(g:sea_compil_mode_menu)
"
" }}}1
"=============================================================================

let s:cpo_save=&cpo
set cpo&vim
"------------------------------------------------------------------------
" ## Misc Functions     {{{1
" # Version {{{2
function! lh#btw#project_options#version()
  return s:k_version
endfunction

" # Debug   {{{2
let s:verbose = get(s:, 'verbose', 0)
function! lh#btw#project_options#verbose(...)
  if a:0 > 0 | let s:verbose = a:1 | endif
  return s:verbose
endfunction

function! s:Log(expr, ...)
  call call('lh#log#this',[a:expr]+a:000)
endfunction

function! s:Verbose(expr, ...)
  if s:verbose
    call call('s:Log',[a:expr]+a:000)
  endif
endfunction

function! lh#btw#project_options#debug(expr) abort
  return eval(a:expr)
endfunction

"------------------------------------------------------------------------
" ## Globals            {{{1
let s:indices = get(s:, 'indices', {})
let s:menus   = get(s:, 'menus',   {})

"------------------------------------------------------------------------
" ## Internal functions {{{1
" # s:Hook() dict {{{2
" TODO: we should open every buffer when all the variables that we are
" manipulating are p:variables.
function! s:Hook() dict abort
  " Two cases:
  " 1- The project is under a lhvl-project -> no need to loop
  " We are not necesarily in a buffer related to the hook executed.
  if has_key(self, 'project') && lh#project#is_a_project(self.project)
        \ && self.project.get('BTW.is_using_project', 0)
    call s:Update2(self)
    " TODO: check whether we need to set _previous key in all related buffers
    return
  endif

  " 2- The project isn't
  " First check whether the data has already been updated for the buffer
  " considered
  let bid = bufnr('%')
  if !has_key(self, "_previous")
    let self._previous = {}
  endif
  if !has_key(self._previous, bid)
    let self._previous[bid] = -1
  endif
  let previous = self._previous[bid]
  let crt_value = self.val_id()
  if crt_value == previous
    call s:Verbose("abort for buffer ".expand('%:p'))
    return
  endif
  try
    call lh#window#split()
    " Bug: iterating on listed buffers (e.g. from vim *.cpp) is enough to
    " disable syntax highlighting
    " =>
    " We delay the settings of b:variables for not loaded buffers.
    if lh#project#is_in_a_project()
      let buffer_list = lh#project#crt().buffers
    else
      let buffer_list = lh#buffer#list('bufloaded')
    endif
    for b in buffer_list
      exe 'b '.b
      call s:Update(self)
    endfor
  finally
    q
    " Assert exists(self.variable)
    let self._previous[bid] = crt_value
  endtry
endfunction

" # s:Update(dict) {{{2
function! s:Update(dict) abort
  try
    let p = expand('%:p')
    let must_update = !empty(p) && lh#path#is_in(p, a:dict._root)
    if must_update
      if s:verbose
        debug call a:dict.do_update()
      else
        call a:dict.do_update()
      endif
      let bid = bufnr('%')
      let a:dict._previous[bid] = a:dict.val_id()
    endif
  catch /.*/
    let g:exception_data = a:dict
    echoerr "Buffer ".bufnr('%').": Cannot update project option ".string(a:dict).': '.v:exception.' at '.v:throwpoint
  endtry
endfunction

" # s:Update2(dict) {{{2
function! s:Update2(dict) abort
  try
    " let p = expand('%:p')
    " let must_update = !empty(p) && lh#path#is_in(p, a:dict._root)
    " if must_update
      if s:verbose
        debug call a:dict.do_update()
      else
        call a:dict.do_update()
      endif
    " endif
  catch /.*/
    let g:exception_data = a:dict
    let g:exception_msg = v:exception
    let g:exception_throwpoint = v:throwpoint
    " echoerr "Buffer ".bufnr('%').": Cannot update project option ".lh#object#to_string(a:dict).': '.v:exception.' at '.v:throwpoint
    echo "Buffer ".bufnr('%').": Cannot update project option ".lh#object#to_string(a:dict)
    echo "while:\n".join(map(lh#exception#callstack(v:throwpoint), '" - ". v:val.script .":". v:val.pos .":". v:val.fname'), "\n")
    throw 'because: '.v:exception
  endtry
endfunction

" # s:getSNR() {{{2
function! s:getSNR(...)
  if !exists("s:SNR")
    let s:SNR=matchstr(expand('<sfile>'), '<SNR>\d\+_\zegetSNR$')
  endif
  return s:SNR . (a:0>0 ? (a:1) : '')
endfunction

"------------------------------------------------------------------------
" ## Exported functions {{{1
" Function: lh#btw#project_options#add_toggle_option(menu) {{{2
function! lh#btw#project_options#add_toggle_option(menu) abort
  if has_key(s:menus, a:menu.menu.name)
    " need to merge new info (i.e. everything but idx_crt_value)
    let menu = s:menus[a:menu.menu.name]
    let menu.values = a:menu.values
    let menu.menu = a:menu.menu
  else
    let s:menus[a:menu.menu.name] = a:menu
    let menu = s:menus[a:menu.menu.name]
    let menu.hook = function(s:getSNR('Hook'))
  endif
  call lh#menu#def_toggle_item(menu)
  " call menu.hook() " already called in menu#s:Set()
  return menu
endfunction

" Function: lh#btw#project_options#add_string_option(menu) {{{2
function! lh#btw#project_options#add_string_option(menu) abort
  if has_key(s:menus, a:menu.menu.name)
    " need to merge new info (i.e. everything but idx_crt_value)
    let menu = s:menus[a:menu.menu.name]
    let menu.values = a:menu.values
    let menu.menu = a:menu.menu
  else
    let s:menus[a:menu.menu.name] = a:menu
    let menu = s:menus[a:menu.menu.name]
    let menu.hook = function(s:getSNR('Hook'))
  endif
  call lh#menu#def_string_item(menu)
  " call menu.hook() " already called in menu#s:Set()
  return menu
endfunction

" }}}1
"------------------------------------------------------------------------
let &cpo=s:cpo_save
"=============================================================================
" vim600: set fdm=marker:

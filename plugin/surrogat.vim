" Vim plugin for surrogate alphabets handling

" Maintainer:    Cyril Slobin (no email for now)
" Last change:   2006 Oct 05
" Documentation: See file surrogat.txt

" $Id: surrogat.vim 1.12 2006/10/04 21:31:29 slobin Exp $

" Public Domain
" Made on Earth

if &cp || &enc != "utf-8" || exists("g:loaded_surrogates")
  finish
endif
let g:loaded_surrogates = 1

let s:save_cpo = &cpo
set cpo&vim

function s:SurrogateLoadFilesHash()
  let s:surrogate_files_hash = {}
  let s:surrogate_names_list = []
  let s:surrogate_first_in_directory = {}
  let possible_index_locations = split(globpath(&runtimepath, "data/index.ini"), "\n")
  if has("dos32") || has("win32")
    call add(possible_index_locations, "c:/Program Files/UniRed/Ini/unired.ini")
  endif
  for index_location in possible_index_locations
    if filereadable(index_location)
      let directory = substitute(index_location, '[^\/]*$', "", "")
      let index = readfile(index_location)
      let surrogates_section = 0
      let first_flag = 1
      for line in index
        if line =~ '^\[.*\]$'
          let surrogates_section = line ==? "[surrogates]"
          continue
        endif
        if surrogates_section
          let list = split(line, '=')
          if len(list) != 2
            continue
          endif
          let [name, files] = list
          if exists("s:surrogate_files_hash[name]")
            continue
          endif
          let filelist = []
          for file in split(files, ',')
            let ext = tolower(matchstr(file, '\..*$'))
            if !has_key(s:surrogate_dispatch_table, ext)
              continue
            endif
            let file = directory . file
            if !filereadable(file)
              continue
            endif
            call add(filelist, file)
          endfor
          call add(s:surrogate_names_list, name)
          let s:surrogate_files_hash[name] = filelist
          let s:surrogate_first_in_directory[name] = first_flag
          let first_flag = 0
        endif
      endfor
    endif
  endfor
endfunction

function s:SurrogateMakeMenu()
  an <silent> S&urrogates.Encode ms:SurrogateEncode<CR>`s
  an <silent> S&urrogates.Decode ms:SurrogateDecode<CR>`s
  for name in s:surrogate_names_list
    let title = escape(name, ' \')
    if s:surrogate_first_in_directory[name]
      execute printf("an <silent> S&urrogates.-%s- <Nop>", title)
    endif
    execute printf("an <silent> S&urrogates.%s :SurrogateSetCurrent %s<CR>", title, name)
    if s:surrogate_files_hash[name] == []
      execute printf("an disable S&urrogates.%s", title)
    endif
  endfor
endfunction

function s:SurrogateSetCurrent(name)
  let name = a:name
  if !exists("s:surrogate_decode_pattern_hash[name]")
    let s:surrogate_current_name = name
    let s:surrogate_encode_dict_hash[name] = {}
    let s:surrogate_decode_dict_hash[name] = {}
    let encode_list = []
    let decode_list = []
    for file in s:surrogate_files_hash[name]
      if !filereadable(file)
        continue
      endif
      let ext = tolower(matchstr(file, '\..*$'))
      let ProcessLine = s:surrogate_dispatch_table[ext] 
      let data = readfile(file)
      for line in data
        let [encoded, decoded, ok] = ProcessLine(line)
        if !ok
          continue
        endif
        if !exists("s:surrogate_encode_dict_hash[name][decoded]") && decoded != ""
          let s:surrogate_encode_dict_hash[name][decoded] = escape(encoded, '\')
          call add(encode_list, escape(decoded, '\/^$.*[]~'))
        endif
        if !exists("s:surrogate_decode_dict_hash[name][encoded]") && encoded != ""
          let s:surrogate_decode_dict_hash[name][encoded] = escape(decoded, '\')
          call add(decode_list, escape(encoded, '\/^$.*[]~'))
        endif
      endfor
    endfor
    let s:surrogate_encode_pattern_hash[name] = join(encode_list, '\|')
    let s:surrogate_decode_pattern_hash[name] = join(decode_list, '\|')
  endif
  let s:surrogate_current_encode_pattern = s:surrogate_encode_pattern_hash[name]
  let s:surrogate_current_decode_pattern = s:surrogate_decode_pattern_hash[name]
  let s:surrogate_current_encode_dict = s:surrogate_encode_dict_hash[name]
  let s:surrogate_current_decode_dict = s:surrogate_decode_dict_hash[name]
endfunc

function s:SurrogateProcessUniredLine(line)
  let line = a:line
  if line[0] == ";"
    return ["", "", 0]
  endif
  let line = substitute(line, '\s*$', "", "")
  if line == ""
    return ["", "", 0]
  endif
  let list = split(line, '\s*=\s*')
  if len(list) != 2
    let list = split(line)
    if len(list) != 2
      return ["", "", 0]
    endif
  endif
  let [encoded, decoded] = list
  let encoded = substitute(encoded, '&#\(\d*\);', '\=nr2char(submatch(1))', "g")
  let decoded = substitute(decoded, '&#\(\d*\);', '\=nr2char(submatch(1))', "g")
  return [encoded, decoded, 1]
endfunction

function s:SurrogateProcessCatdocLine(line)
  let line = substitute(a:line, '^\s*', "", "")
  if line == "" || line[0] == "#"
    return ["", "", 0]
  endif
  let list = matchlist(line, '\v^(\x+)\s+%(\''(%(\\\''|[^''])*)\''|' .
                      \ '\"(%(\\\"|[^"])*)\"|\((%(\\\)|[^)])*)\)|' .
                      \ '\[(%(\\\]|[^]])*)\]|\{(%(\\\}|[^}])*)\}|(\S+))')
  if list == []
    return ["", "", 0]
  endif
  let decoded = nr2char(str2nr(list[0], 16))
  if decoded < " "
    return ["", "", 0]
  endif
  let encoded = join(list[2:], "")
  let encoded = substitute(encoded, '\C\\\(0\o*\|.\)',
                          \ '\=s:SurrogateProcessCatdocChar(submatch(1))', "g")
  return [encoded, decoded, 1]
endfunction

function s:SurrogateProcessCatdocChar(char)
  let c = a:char
  return c ==# "n" ? "\n" : c ==# "r" ? "\r" : c ==# "t" ? "\t" : c ==# "b" ? "\b" :
       \ c[0] == "0" ? nr2char(c) : c
endfunction

function s:SurrogateEncode() range
  if exists("s:surrogate_current_encode_pattern")
    execute printf('%d,%ds/\C\m\(%s\)/\=s:surrogate_current_encode_dict[submatch(1)]/eg',
                  \ a:firstline, a:lastline, s:surrogate_current_encode_pattern)
  endif
endfunction

function s:SurrogateDecode() range
  if exists("s:surrogate_current_decode_pattern")
    execute printf('%d,%ds/\C\m\(%s\)/\=s:surrogate_current_decode_dict[submatch(1)]/eg',
                  \ a:firstline, a:lastline, s:surrogate_current_decode_pattern)
  endif
endfunction

function s:SurrogateNameComplete(ArgLead, CmdLine, CursorPos)
  return filter(copy(s:surrogate_names_list),
               \ "strpart(v:val, 0, strlen(a:ArgLead)) == a:ArgLead")
endfunction

command -range=% SurrogateEncode <line1>,<line2>call s:SurrogateEncode()
command -range=% SurrogateDecode <line1>,<line2>call s:SurrogateDecode()
command -nargs=1 -complete=customlist,s:SurrogateNameComplete SurrogateSetCurrent
        \ call s:SurrogateSetCurrent(<q-args>)

let s:surrogate_dispatch_table = {".srg": function("s:SurrogateProcessUniredLine"),
                                 \".rpl": function("s:SurrogateProcessCatdocLine"),
                                 \".spc": function("s:SurrogateProcessCatdocLine")}
let s:surrogate_encode_pattern_hash = {}
let s:surrogate_decode_pattern_hash = {}
let s:surrogate_encode_dict_hash = {}
let s:surrogate_decode_dict_hash = {}

call s:SurrogateLoadFilesHash()
if has("gui_running")
  call s:SurrogateMakeMenu()
endif

let &cpo = s:save_cpo

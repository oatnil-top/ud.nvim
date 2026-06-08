" ud.vim — Auto-load bootstrap for ud.nvim
" Users call require('ud').setup() from their init.lua;
" this file ensures the plugin directory is on runtimepath.

if exists('g:loaded_ud')
  finish
endif
let g:loaded_ud = 1

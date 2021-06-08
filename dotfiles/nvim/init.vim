set relativenumber
set number

set ts=3
set sw=3

set rtp+=~/.config/nvim/bundle/Vundle.vim

call vundle#begin()
Plugin 'christoomey/vim-system-copy'
Plugin 'sheerun/vim-polyglot'
Plugin 'tomlion/vim-solidity'
call vundle#end()

" Spell check
set spelllang=es,en
set spell

" Installed plugins:
"
" https://github.com/tpope/vim-commentary
" https://github.com/tpope/vim-surround

" Add numbers to each line on the left-hand side.
set number

" Enable search highlighting.
set hlsearch

" Enable case insensitive search.      
" Similar to ignorecase, but only if you search with lowercase letters.
set smartcase

" Show the mode you are on the last line.
set showmode

" Turn syntax highlighting on.
syntax on

" Set shift width to 4 spaces.
set shiftwidth=4

" Set tab width to 4 columns.
set tabstop=4

" Use space characters instead of tabs.
set expandtab

" Use a line cursor within insert mode and a block cursor everywhere else.
"
" Reference chart of values:
"   Ps = 0  -> blinking block.
"   Ps = 1  -> blinking block (default).
"   Ps = 2  -> steady block.
"   Ps = 3  -> blinking underline.
"   Ps = 4  -> steady underline.
"   Ps = 5  -> blinking bar (xterm).
"   Ps = 6  -> steady bar (xterm).
let &t_SI = "\e[6 q"
let &t_EI = "\e[2 q"
" After exit insert mode, change cursor without waiting one second
set ttimeout
set ttimeoutlen=0

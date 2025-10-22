" Find help for each of these configs (CONF_NAME might need to be wrapped in '')
" :help CONF_NAME

" Sets encoding
set encoding=UTF-8

" Add numbers to each line on the left-hand side.
set number

" Ignore case when searching.
set ignorecase

" Similar to ignorecase, but only if you search with lowercase letters.
set smartcase

" Enable search highlighting.
set hlsearch

" Removes the highlight from the last search
nmap <esc><esc> :noh<return>

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

" Enable the use of mouse (a = all previous modes)
" set mouse=a

if has("unnamedplus")
    set clipboard=unnamedplus
else
    set clipboard=unnamed
endif

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

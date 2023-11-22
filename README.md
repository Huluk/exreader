# Ex mode speech

- inspiration: https://github.com/MaxwellBo/neoreader
- [ui plugins](https://github.com/neovim/neovim/wiki/Plugin-UI-architecture)
- [ruby neovim rpc](https://github.com/neovim/neovim-ruby)
Do I need treesitter bindings?
- [ruby treesitter](https://github.com/calicoday/ruby-tree-sitter-ffi)

# Installation

Add something like this to `.vimrc`:
```
if isdirectory($HOME.'/Documents/exread')
  Plug '~/Documents/exread'
endif

```

Then run `:PlugInstall` and `:UpdateRemotePlugins`.

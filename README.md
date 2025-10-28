# Ex mode speech

Produce voice output for code in Neovim. Adjust the pitch based on syntax trees.

I started working on this because I had some eye problems which made reading annoying,
but not to the level I would use "proper" assistive features.
Using normal voice output is not great because of the use/mention distinction.
I don't want to hear all the symbols read out, but ignoring them loses lots of information.
Hopefully pitch tuning helps with this.

This project is very much work in progress.

In particular it is not tested with the newest neovim versions and
the voice pitches need tuning / value setting.

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

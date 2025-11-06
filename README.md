# diffy.nvim

A Neovim plugin for displaying git diffs in a side-by-side floating window, similar to Gitsigns diffthis but with a more visual interface.

## Features

- Side-by-side diff display in floating windows
- Synchronized scrolling between original and modified content
- Syntax highlighting for the current file type
- Easy to close with `q`, `<Esc>`, or `<C-c>`
- Support for different diff targets (HEAD, staged, specific commits)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'JoshuaFurman/diffy',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('diffy').setup()
  end
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'JoshuaFurman/diffy',
  requires = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('diffy').setup()
  end
}
```

## Usage

### Commands

- `:Diffy` - Show diff for current file against HEAD
- `:Diffy staged` - Show diff for staged changes
- `:Diffy <commit>` - Show diff for current file at specific commit

### Key Mappings

When the diff window is open:
- `q` - Close the diff window
- `<Esc>` - Close the diff window
- `<C-c>` - Close the diff window

## Configuration

```lua
require('diffy').setup({
  width = 0.8,      -- Window width as fraction of screen
  height = 0.8,     -- Window height as fraction of screen
  border = 'rounded', -- Border style
  winblend = 10,    -- Window transparency
})
```

## Requirements

- Neovim 0.7+
- Git
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Similar Projects

- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) - Git signs and hunk management

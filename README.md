# diffy.nvim

A Neovim plugin for displaying git diffs in a side-by-side floating window, similar to Gitsigns diffthis but with a more visual interface.

## Features

- GitHub-style side-by-side diff display in floating windows
- Soft-wrapped lines with aligned rows and a separate line-number gutter
- Full-width red/green backgrounds with bold, stronger highlights on the exact changed characters
- Synchronized scrolling between original and modified content
- Syntax highlighting for the current file type
- Easy to close with `q`, `<Esc>`, or `<C-c>`
- Toggle staging for the current hunk with `a`
- Current hunk state in the footer (staged, unstaged, or partial), without covering code
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
- `<Enter>` - Jump to the selected location in the source buffer and close the diff window
- `n` - Jump to the next hunk
- `p` - Jump to the previous hunk
- `a` - Toggle staging for the current hunk

## Configuration

```lua
require('diffy').setup({
  width = 0.8,      -- Window width as fraction of screen
  height = 0.8,     -- Window height as fraction of screen
  border = 'rounded', -- Border style
  winblend = 0,    -- Opaque panes for readable diff colors
  wrap = true,     -- Soft-wrap long lines; false restores horizontal scrolling
})
```

### Highlight customization

Diffy provides light/dark defaults without changing Neovim's global `Diff*` groups.
Line backgrounds preserve syntax colors; exact changed characters also get bold text and a
stronger background. Override these groups in your colorscheme configuration (reapply overrides
on `ColorScheme` if you switch themes):

```lua
vim.api.nvim_set_hl(0, 'DiffyAdd', { bg = '#142b21' })
vim.api.nvim_set_hl(0, 'DiffyDelete', { bg = '#2b1b20' })
vim.api.nvim_set_hl(0, 'DiffyAddText', { bg = '#1f633b', bold = true })
vim.api.nvim_set_hl(0, 'DiffyDeleteText', { bg = '#7d2834', bold = true })
vim.api.nvim_set_hl(0, 'DiffyFiller', { bg = '#161b22' })
```

## Testing

```sh
nvim --clean --headless -c "luafile test.lua"
```

To verify the actual rendered UI colors (including changed spaces and wrapped lines):

```sh
uv run --no-project --with pynvim python tests/screen.py
```

This additional screen test uses `pynvim` only for testing, not as a plugin dependency.

## Requirements

- Neovim 0.10+ (wrapped-row measurement and smooth scrolling)
- Git
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Similar Projects

- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) - Git signs and hunk management

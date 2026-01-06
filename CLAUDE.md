# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

diffy.nvim is a Neovim plugin that displays git diffs in a side-by-side floating window interface with synchronized scrolling and syntax highlighting. It's written in pure Lua and uses plenary.nvim for async job execution.

## Development Commands

### Testing
- Run all tests: `nvim --headless -c "luafile test.lua"`
- Integration test: Open test file and run `:Diffy` command manually in Neovim

### Linting & Formatting
- Lint Lua code: `luacheck lua/`
- Check formatting: `stylua --check lua/`
- Format code: `stylua lua/`

### Development
- No build step required (pure Lua plugin)
- Reload plugin during development: `:lua package.loaded.diffy = nil; require('diffy')`

## Architecture

### Module Structure

The plugin follows a three-module architecture:

1. **lua/diffy/init.lua** - Entry point and public API
   - Exports setup() function and config table
   - Creates `:Diffy` user command
   - Orchestrates calls to git and ui modules

2. **lua/diffy/git.lua** - Git integration and diff parsing
   - `get_diff(file_path, target)` - Main function that coordinates git operations
   - `get_git_root()` - Finds repository root using plenary.job
   - `get_git_diff()` - Executes git diff with high context (-U999999)
   - `parse_and_align_diff()` - **Core logic**: Parses unified diff format and builds aligned left/right content arrays with line tracking
   - Returns diff_data table with: left_content, right_content, left_highlights, right_highlights, left_line_info, right_line_info

3. **lua/diffy/ui.lua** - Window management and display
   - `open_diff_window(diff_data)` - Creates side-by-side floating windows
   - `apply_line_numbers()` - Uses extmarks with virtual text to display line numbers inline (format: `  1234 │ ` for context, `- 1234 │ ` for deletions, `+ 1234 │ ` for additions)
   - `apply_highlighting()` - Applies DiffDelete/DiffAdd highlights
   - `setup_scroll_sync()` - Bidirectional scroll synchronization via CursorMoved autocmds
   - `setup_keymaps()` - Binds q/Esc/Ctrl-c to close windows

### Key Design Patterns

- **Diff Alignment**: git.lua's `parse_and_align_diff()` creates aligned arrays where removed lines show on left with empty right, added lines show on right with empty left, and context lines appear on both sides
- **Line Number Tracking**: Each display line tracks its original line number via left_line_info/right_line_info tables with `{num, type}` where type is 'context', 'remove', 'add', 'empty', or 'separator'
- **Async Git Operations**: All git commands use plenary.job:sync() for non-blocking execution
- **Window Lifecycle**: Windows and buffers are stored in module-level variables and cleaned up on close

### Code Style

- 2-space indentation, 100 character line limit
- Functions: snake_case (e.g., `get_diff_data()`)
- Module pattern: `local M = {}` with `return M`
- Error handling: Return nil on failure, use `vim.notify()` for user feedback
- All external commands go through plenary.job

## Usage

```
:Diffy           # Diff against HEAD
:Diffy staged    # Diff staged changes
:Diffy <commit>  # Diff against specific commit
```

Inside diff window: `q`, `<Esc>`, or `<C-c>` to close

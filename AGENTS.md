# Agent Guidelines for diffy.nvim

## Build/Lint/Test Commands

### Testing
- Run all tests: `nvim --headless -c "luafile test.lua"`
- Run single test file: `nvim --headless -c "lua require('test_module').test_function()"`
- Integration test: Open test file and run `:Diffy` command manually

### Linting
- Lua linting: `luacheck lua/`
- Style checking: `stylua --check lua/`
- Format code: `stylua lua/`

### Development
- No build step required (pure Lua plugin)
- Reload plugin: `:lua package.loaded.diffy = nil; require('diffy')`

## Code Style Guidelines

### Naming Conventions
- Functions: `snake_case` (e.g., `get_diff_data()`)
- Variables: `snake_case` (e.g., `diff_data`)
- Modules: `snake_case` (e.g., `git.lua`, `ui.lua`)
- Constants: `UPPER_SNAKE_CASE`

### Imports and Dependencies
- Use `local M = {}` for module exports
- Require modules at top: `local git = require('diffy.git')`
- Avoid global variables except Neovim builtins (`vim.*`)

### Error Handling
- Check function return values before using
- Use `vim.notify()` for user-facing errors
- Return `nil` for failure cases, handle gracefully
- Validate inputs before processing

### Formatting
- 2-space indentation
- Line length: 100 characters max
- Consistent spacing around operators
- Group related functions with blank lines

### Types and Documentation
- Use descriptive variable names
- Add comments for complex logic
- Document public API functions
- Avoid Hungarian notation

### Neovim Integration
- Use `vim.api.*` for core operations
- Handle window/buffer lifecycle properly
- Set appropriate buffer options (`buftype`, `bufhidden`)
- Clean up resources on plugin unload

### Performance
- Cache expensive operations when possible
- Use async jobs for external commands
- Minimize API calls in loops
- Profile with `:lua vim.loop.hrtime()` if needed
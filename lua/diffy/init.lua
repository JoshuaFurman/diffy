local M = {}

-- Configuration
M.config = {
  width = 0.8,
  height = 0.8,
  border = 'rounded',
  winblend = 10,
}

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})

  -- Create commands
  vim.api.nvim_create_user_command('Diffy', function(args)
    M.open_diff(args.args)
  end, {
    nargs = '?',
    desc = 'Open diff viewer for current file or specified target'
  })

  -- Key mappings for closing diff windows
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'diffy',
    callback = function()
      vim.keymap.set('n', 'q', M.close_diff, { buffer = true, silent = true })
      vim.keymap.set('n', '<Esc>', M.close_diff, { buffer = true, silent = true })
      vim.keymap.set('n', '<C-c>', M.close_diff, { buffer = true, silent = true })
    end
  })
end

-- Open diff viewer
function M.open_diff(target)
  local git = require('diffy.git')
  local ui = require('diffy.ui')

  -- Get current file
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file == '' then
    vim.notify('No file open', vim.log.levels.WARN)
    return
  end

  -- Get diff data
  local diff_data = git.get_diff(current_file, target)
  if not diff_data then
    vim.notify('No diff available', vim.log.levels.INFO)
    return
  end

  -- Open UI
  ui.open_diff_window(diff_data)
end

-- Close diff viewer
function M.close_diff()
  local ui = require('diffy.ui')
  ui.close_diff_window()
end

return M
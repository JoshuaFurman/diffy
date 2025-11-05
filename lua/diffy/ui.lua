local M = {}

local diffy_namespace = vim.api.nvim_create_namespace('diffy')

-- Window handles
local left_win = nil
local right_win = nil
local left_buf = nil
local right_buf = nil

-- Open the diff viewer window
function M.open_diff_window(diff_data)
  -- Close any existing diff windows
  M.close_diff_window()

  -- Calculate window dimensions
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)
  
  local content_width = math.floor(width / 2) - 2

  -- Get current filetype for syntax
  local ft = vim.bo.filetype

  -- Create left content buffer
  left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[left_buf].buftype = 'nofile'
  vim.bo[left_buf].bufhidden = 'wipe'
  vim.bo[left_buf].filetype = ft
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, diff_data.left_content)

  -- Create right content buffer
  right_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[right_buf].buftype = 'nofile'
  vim.bo[right_buf].bufhidden = 'wipe'
  vim.bo[right_buf].filetype = ft
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, diff_data.right_content)

  -- Create left content window
  left_win = vim.api.nvim_open_win(left_buf, false, {
    relative = 'editor',
    width = content_width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Original ',
    title_pos = 'center'
  })
  vim.wo[left_win].signcolumn = 'yes:1'
  vim.wo[left_win].number = false

  -- Create right content window
  right_win = vim.api.nvim_open_win(right_buf, true, {
    relative = 'editor',
    width = content_width,
    height = height,
    col = col + content_width + 2,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Modified ',
    title_pos = 'center'
  })
  vim.wo[right_win].signcolumn = 'yes:1'
  vim.wo[right_win].number = false

  -- Apply highlighting and signs
  M.apply_highlighting(left_buf, right_buf, diff_data)
  M.apply_signs(left_buf, right_buf, diff_data)

  -- Set up synchronized scrolling
  M.setup_scroll_sync()

  -- Set up keymaps
  M.setup_keymaps()
end

-- Close the diff viewer
function M.close_diff_window()
  local wins = {left_win, right_win}
  local bufs = {left_buf, right_buf}
  
  for _, win in ipairs(wins) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  
  for _, buf in ipairs(bufs) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  
  left_win = nil
  right_win = nil
  left_buf = nil
  right_buf = nil
end

-- Apply syntax highlighting to diff content
function M.apply_highlighting(left, right, diff_data)
  -- Apply diff-specific highlighting
  for _, line_num in ipairs(diff_data.left_highlights or {}) do
    vim.api.nvim_buf_add_highlight(left, diffy_namespace, 'DiffDelete', line_num - 1, 0, -1)
  end
  
  for _, line_num in ipairs(diff_data.right_highlights or {}) do
    vim.api.nvim_buf_add_highlight(right, diffy_namespace, 'DiffAdd', line_num - 1, 0, -1)
  end
end

-- Apply signs for line numbers with +/- indicators
function M.apply_signs(left, right, diff_data)
  -- Define sign types
  vim.fn.sign_define('DiffyContext', { text = '  ', texthl = 'LineNr' })
  vim.fn.sign_define('DiffyRemove', { text = '- ', texthl = 'DiffDelete' })
  vim.fn.sign_define('DiffyAdd', { text = '+ ', texthl = 'DiffAdd' })
  
  -- Place signs on left buffer
  for i, line_num_text in ipairs(diff_data.left_line_nums) do
    local sign_type = line_num_text:match('^%-') and 'DiffyRemove' or 'DiffyContext'
    vim.fn.sign_place(0, 'diffy', sign_type, left, { lnum = i })
  end
  
  -- Place signs on right buffer
  for i, line_num_text in ipairs(diff_data.right_line_nums) do
    local sign_type = line_num_text:match('^%+') and 'DiffyAdd' or 'DiffyContext'
    vim.fn.sign_place(0, 'diffy', sign_type, right, { lnum = i })
  end
end

-- Set up synchronized scrolling
function M.setup_scroll_sync()
  local function sync_scroll(source_win, target_win)
    if not source_win or not vim.api.nvim_win_is_valid(source_win) then
      return
    end
    if not target_win or not vim.api.nvim_win_is_valid(target_win) then
      return
    end
    
    local cursor = vim.api.nvim_win_get_cursor(source_win)
    local topline = vim.fn.line('w0', source_win)
    
    pcall(vim.api.nvim_win_set_cursor, target_win, cursor)
    pcall(vim.fn.winrestview, target_win, {topline = topline})
  end

  vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    buffer = left_buf,
    callback = function()
      sync_scroll(left_win, right_win)
    end
  })

  vim.api.nvim_create_autocmd({'CursorMoved', 'CursorMovedI'}, {
    buffer = right_buf,
    callback = function()
      sync_scroll(right_win, left_win)
    end
  })
end

-- Set up keymaps for closing
function M.setup_keymaps()
  for _, buf in ipairs({left_buf, right_buf}) do
    vim.keymap.set('n', 'q', M.close_diff_window, { buffer = buf, silent = true })
    vim.keymap.set('n', '<Esc>', M.close_diff_window, { buffer = buf, silent = true })
    vim.keymap.set('n', '<C-c>', M.close_diff_window, { buffer = buf, silent = true })
  end
end

return M

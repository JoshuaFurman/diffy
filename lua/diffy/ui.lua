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
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create left buffer (original)
  left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(left_buf, 'diffy://left')
  vim.api.nvim_buf_set_option(left_buf, 'filetype', 'diffy')
  vim.api.nvim_buf_set_option(left_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(left_buf, 'bufhidden', 'wipe')

  -- Create right buffer (modified)
  right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(right_buf, 'diffy://right')
  vim.api.nvim_buf_set_option(right_buf, 'filetype', 'diffy')
  vim.api.nvim_buf_set_option(right_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(right_buf, 'bufhidden', 'wipe')

  -- Set buffer content
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, diff_data.left_content)
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, diff_data.right_content)

  -- Create left window
  left_win = vim.api.nvim_open_win(left_buf, false, {
    relative = 'editor',
    width = math.floor(width / 2) - 1,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = 'Original',
    title_pos = 'center'
  })

  -- Create right window
  right_win = vim.api.nvim_open_win(right_buf, true, {
    relative = 'editor',
    width = math.floor(width / 2) - 1,
    height = height,
    col = col + math.floor(width / 2) + 1,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = 'Modified',
    title_pos = 'center'
  })

  -- Apply syntax highlighting
  M.apply_highlighting(left_buf, right_buf, diff_data)

  -- Set up synchronized scrolling
  M.setup_scroll_sync()

  -- Focus the right window
  vim.api.nvim_set_current_win(right_win)
end

-- Close the diff viewer
function M.close_diff_window()
  if left_win and vim.api.nvim_win_is_valid(left_win) then
    vim.api.nvim_win_close(left_win, true)
    left_win = nil
  end
  if right_win and vim.api.nvim_win_is_valid(right_win) then
    vim.api.nvim_win_close(right_win, true)
    right_win = nil
  end
  if left_buf and vim.api.nvim_buf_is_valid(left_buf) then
    vim.api.nvim_buf_delete(left_buf, { force = true })
    left_buf = nil
  end
  if right_buf and vim.api.nvim_buf_is_valid(right_buf) then
    vim.api.nvim_buf_delete(right_buf, { force = true })
    right_buf = nil
  end
end

-- Apply syntax highlighting to diff content
function M.apply_highlighting(left, right, diff_data)
  -- Get current buffer's filetype for syntax highlighting
  local ft = vim.bo.filetype

  -- Set filetype for syntax highlighting
  vim.api.nvim_buf_set_option(left, 'filetype', ft)
  vim.api.nvim_buf_set_option(right, 'filetype', ft)

  -- Apply diff-specific highlighting
  local line_num = 1
  for _, hunk in ipairs(diff_data.hunks) do
    for _, line in ipairs(hunk.lines) do
      if line.type == 'add' then
        vim.api.nvim_buf_add_highlight(right, diffy_namespace, 'DiffAdd', line_num - 1, 0, -1)
      elseif line.type == 'remove' then
        vim.api.nvim_buf_add_highlight(left, diffy_namespace, 'DiffDelete', line_num - 1, 0, -1)
      end
      line_num = line_num + 1
    end
  end
end

-- Set up synchronized scrolling
function M.setup_scroll_sync()
  -- Store original scroll positions
  local left_scroll = 0
  local right_scroll = 0

  -- Set up autocmds for scroll synchronization
  vim.api.nvim_create_autocmd('WinScrolled', {
    callback = function(args)
      if args.match == tostring(left_win) then
        local new_scroll = vim.api.nvim_win_get_cursor(left_win)[1]
        if new_scroll ~= left_scroll then
          left_scroll = new_scroll
          vim.api.nvim_win_set_cursor(right_win, {new_scroll, 0})
          right_scroll = new_scroll
        end
      elseif args.match == tostring(right_win) then
        local new_scroll = vim.api.nvim_win_get_cursor(right_win)[1]
        if new_scroll ~= right_scroll then
          right_scroll = new_scroll
          vim.api.nvim_win_set_cursor(left_win, {new_scroll, 0})
          left_scroll = new_scroll
        end
      end
    end
  })
end

return M
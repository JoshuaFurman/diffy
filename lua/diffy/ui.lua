local render = require("diffy.render")
local M = {}

local diffy_namespace = vim.api.nvim_create_namespace("diffy")
local ui_group = vim.api.nvim_create_augroup("DiffyUI", { clear = true })
local gutter_width = 4

-- Window handles
local left_win = nil
local right_win = nil
local left_buf = nil
local right_buf = nil
local footer_win = nil
local footer_buf = nil
local footer_total_width = nil -- Store for dynamic footer updates
local hunk_starts = nil -- Array of hunk start line numbers
local hunk_ranges = nil -- Array of hunk display ranges
local hunk_states = nil -- Array of hunk staged states
local active_diff_data = nil
local source_win = nil
local source_buf = nil
local update_footer_status = nil

local function setup_highlights()
  render.setup_highlights()
  vim.cmd("highlight default link DiffyHunkStaged DiffAdd")
  vim.cmd("highlight default link DiffyHunkUnstaged WarningMsg")
  vim.cmd("highlight default link DiffyHunkPartial DiffChange")
  vim.cmd("highlight default link DiffyHunkReadonly Comment")
  vim.cmd("highlight default link DiffyHunkUnknown Comment")
end

-- Calculate hunk display ranges from diff data
-- Detects "logical hunks" - contiguous sequences of changes separated by context
local function calculate_hunks(diff_data)
  if not diff_data or not diff_data.left_line_info then
    return {}
  end

  local hunks = {}
  local in_change = false
  local current_hunk = nil

  for i, info in ipairs(diff_data.left_line_info) do
    -- A line is a "change" if it's a remove or empty (empty = add on right side)
    local is_change = info.type == "remove" or info.type == "empty"

    if is_change and not in_change then
      -- Starting a new change region = new hunk
      current_hunk = { start = i, stop = i }
      in_change = true
    elseif is_change then
      current_hunk.stop = i
    elseif not is_change and current_hunk then
      -- Context or separator line = end of change region
      table.insert(hunks, current_hunk)
      current_hunk = nil
      in_change = false
    end
  end

  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return hunks
end

local function get_hunk_starts(hunks)
  local starts = {}

  for _, hunk in ipairs(hunks or {}) do
    table.insert(starts, hunk.start)
  end

  return starts
end

local function get_hunk_state_label(state)
  if state == "staged" then
    return "staged", "DiffyHunkStaged"
  elseif state == "unstaged" then
    return "unstaged", "DiffyHunkUnstaged"
  elseif state == "partial" then
    return "partial", "DiffyHunkPartial"
  elseif state == "readonly" then
    return "read-only", "DiffyHunkReadonly"
  end

  return "unknown", "DiffyHunkUnknown"
end

local function refresh_hunk_states()
  if not active_diff_data or not hunk_starts then
    hunk_states = {}
    return
  end

  local git = require("diffy.git")
  hunk_states = git.get_hunk_states(active_diff_data, hunk_starts)
end

-- Find the index of the hunk containing the cursor
-- Returns 0 if cursor is before the first hunk
local function find_current_hunk_index(strict)
  if not hunk_ranges or #hunk_ranges == 0 then
    return 0
  end

  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= left_win and current_win ~= right_win then
    return 0
  end

  local cursor = vim.api.nvim_win_get_cursor(current_win)
  local cursor_line = cursor[1]

  -- Find hunk containing cursor (iterate backwards)
  for i = #hunk_ranges, 1, -1 do
    local hunk = hunk_ranges[i]
    if cursor_line >= hunk.start and (not strict or cursor_line <= hunk.stop) then
      return i
    end
  end

  -- Cursor is before the first hunk
  return 0
end

local function focus_hunk(index)
  if not hunk_starts or not hunk_starts[index] then
    return
  end

  local target_line = hunk_starts[index]

  for _, win in ipairs({ left_win, right_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { target_line, 0 })
    end
  end

  if right_win and vim.api.nvim_win_is_valid(right_win) then
    vim.api.nvim_set_current_win(right_win)
  end

  update_footer_status()
end

local function find_source_window()
  if source_win and vim.api.nvim_win_is_valid(source_win) then
    return source_win
  end

  if not source_buf or not vim.api.nvim_buf_is_valid(source_buf) then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == source_buf then
      return win
    end
  end

  return nil
end

local function get_source_line(display_line)
  if not active_diff_data or not active_diff_data.right_line_info then
    return nil
  end

  local right_line_info = active_diff_data.right_line_info
  local line_info = right_line_info[display_line]
  if line_info and line_info.num then
    return line_info.num
  end

  for line = display_line + 1, #right_line_info do
    line_info = right_line_info[line]
    if line_info and line_info.num then
      return line_info.num
    end
  end

  for line = display_line - 1, 1, -1 do
    line_info = right_line_info[line]
    if line_info and line_info.num then
      return line_info.num + 1
    end
  end

  return 1
end

local function clamp_cursor(buf, line, col)
  local line_count = vim.api.nvim_buf_line_count(buf)
  line = math.max(1, math.min(line or 1, line_count))

  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  col = math.max(0, math.min(col or 0, #text))

  return { line, col }
end

-- Generate footer content with commands and hunk status
local function generate_footer_content(total_width)
  local commands = {
    { key = "q/Esc", desc = "close" },
    { key = "<CR>", desc = "jump" },
    { key = "n", desc = "next hunk" },
    { key = "p", desc = "prev hunk" },
    { key = "a", desc = "toggle stage" },
  }

  -- Build command parts
  local parts = {}
  for _, cmd in ipairs(commands) do
    table.insert(parts, cmd.key .. " " .. cmd.desc)
  end
  local commands_text = table.concat(parts, "  ")

  -- Build hunk status
  local hunk_status
  if not hunk_starts or #hunk_starts == 0 then
    hunk_status = "No hunks"
  else
    local current_idx = find_current_hunk_index()
    local state = hunk_states and hunk_states[current_idx]
    local label = get_hunk_state_label(state)
    hunk_status = string.format("Hunk %d/%d [%s]", current_idx, #hunk_starts, label)
  end

  local separator = "  │  "
  if vim.fn.strdisplaywidth(commands_text .. separator .. hunk_status) > total_width then
    commands = {
      { key = "q", desc = "close" },
      { key = "<CR>", desc = "jump" },
      { key = "n/p", desc = "hunks" },
      { key = "a", desc = "stage" },
    }
    parts = {}
    for _, cmd in ipairs(commands) do
      parts[#parts + 1] = cmd.key .. " " .. cmd.desc
    end
    commands_text = table.concat(parts, "  ")
  end
  if vim.fn.strdisplaywidth(commands_text .. separator .. hunk_status) > total_width then
    commands, commands_text, separator = {}, "", ""
  end
  local footer_text = commands_text .. separator .. hunk_status

  -- Keep the hunk state visible even when command hints need to be shortened.
  local padding = math.max(0, math.floor((total_width - vim.fn.strdisplaywidth(footer_text)) / 2))
  local centered_text = string.rep(" ", padding) .. footer_text

  return {
    text = centered_text,
    commands = commands,
    padding = padding,
    commands_text_len = #commands_text,
    separator_len = #separator,
    hunk_status = hunk_status,
  }
end

-- Update the footer with current hunk status
function update_footer_status()
  if not footer_buf or not vim.api.nvim_buf_is_valid(footer_buf) then
    return
  end
  if not footer_total_width then
    return
  end

  local content = generate_footer_content(footer_total_width)

  -- Update footer buffer content
  vim.bo[footer_buf].modifiable = true
  vim.api.nvim_buf_set_lines(footer_buf, 0, -1, false, { content.text })
  vim.bo[footer_buf].modifiable = false

  -- Clear existing highlights and reapply
  vim.api.nvim_buf_clear_namespace(footer_buf, diffy_namespace, 0, -1)

  -- Highlight commands (keys and descriptions)
  local col_offset = content.padding
  for _, cmd in ipairs(content.commands) do
    -- Highlight the key
    vim.api.nvim_buf_add_highlight(
      footer_buf,
      diffy_namespace,
      "Special",
      0,
      col_offset,
      col_offset + #cmd.key
    )
    col_offset = col_offset + #cmd.key + 1 -- +1 for space after key

    -- Highlight the description
    vim.api.nvim_buf_add_highlight(
      footer_buf,
      diffy_namespace,
      "Comment",
      0,
      col_offset,
      col_offset + #cmd.desc
    )
    col_offset = col_offset + #cmd.desc + 2 -- +2 for double space separator
  end

  if content.separator_len > 0 then
    local separator_start = content.padding + content.commands_text_len + 2
    vim.api.nvim_buf_add_highlight(
      footer_buf,
      diffy_namespace,
      "Comment",
      0,
      separator_start,
      separator_start + 3
    )
  end

  local hunk_status_start = content.padding + content.commands_text_len + content.separator_len
  vim.api.nvim_buf_add_highlight(
    footer_buf,
    diffy_namespace,
    "Title",
    0,
    hunk_status_start,
    hunk_status_start + #content.hunk_status
  )
end

-- Create the command footer window
local function create_footer_window(col, total_width, row)
  -- Store total width for dynamic updates
  footer_total_width = total_width

  footer_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[footer_buf].buftype = "nofile"
  vim.bo[footer_buf].bufhidden = "wipe"
  update_footer_status()

  -- Create footer window (borderless, non-focusable)
  footer_win = vim.api.nvim_open_win(footer_buf, false, {
    relative = "editor",
    width = total_width,
    height = 1,
    col = col,
    row = row,
    style = "minimal",
    border = "none",
    focusable = false,
  })
end

local function get_layout()
  local config = require("diffy").config
  local width = math.max(6, math.min(vim.o.columns, math.floor(vim.o.columns * config.width)))
  local total_height =
    math.max(4, math.min(vim.o.lines - 1, math.floor(vim.o.lines * config.height)))
  return {
    width = width,
    height = total_height - 3,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - total_height) / 2),
    content_width = math.max(1, math.floor(width / 2) - 2),
  }
end

local function resize_windows()
  if not left_win or not right_win or not footer_win then
    return
  end
  for _, win in ipairs({ left_win, right_win, footer_win }) do
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
  end
  local layout = get_layout()
  for i, win in ipairs({ left_win, right_win }) do
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      row = layout.row,
      col = layout.col + (i - 1) * (layout.content_width + 2),
      width = layout.content_width,
      height = layout.height,
    })
  end
  vim.api.nvim_win_set_config(footer_win, {
    relative = "editor",
    row = layout.row + layout.height + 2,
    col = layout.col,
    width = layout.width,
    height = 1,
  })
  footer_total_width = layout.width
  render.align(left_win, right_win)
  update_footer_status()
end

-- Open the diff viewer window
function M.open_diff_window(diff_data)
  -- Close any existing diff windows
  M.close_diff_window()
  active_diff_data = diff_data
  source_win = vim.api.nvim_get_current_win()
  source_buf = vim.api.nvim_get_current_buf()
  setup_highlights()

  -- Calculate window dimensions
  local layout = get_layout()
  local width, height = layout.width, layout.height
  local col, row = layout.col, layout.row
  local content_width = layout.content_width
  local config = require("diffy").config

  -- Get current filetype for syntax
  local ft = vim.bo.filetype

  -- Create left content buffer
  left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[left_buf].buftype = "nofile"
  vim.bo[left_buf].bufhidden = "wipe"
  vim.bo[left_buf].filetype = ft
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, diff_data.left_content)

  -- Create right content buffer
  right_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[right_buf].buftype = "nofile"
  vim.bo[right_buf].bufhidden = "wipe"
  vim.bo[right_buf].filetype = ft
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, diff_data.right_content)

  -- Create left content window
  left_win = vim.api.nvim_open_win(left_buf, false, {
    relative = "editor",
    width = content_width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = config.border,
    title = " Original ",
    title_pos = "center",
  })

  -- Create right content window
  right_win = vim.api.nvim_open_win(right_buf, true, {
    relative = "editor",
    width = content_width,
    height = height,
    col = col + content_width + 2,
    row = row,
    style = "minimal",
    border = config.border,
    title = " Modified ",
    title_pos = "center",
  })

  for _, win in ipairs({ left_win, right_win }) do
    local wo = vim.wo[win]
    wo.wrap = config.wrap
    wo.linebreak = false
    wo.breakindent = false
    wo.showbreak = ""
    wo.smoothscroll = true
    wo.number = true
    wo.relativenumber = false
    wo.numberwidth = 1
    wo.signcolumn = "no"
    wo.foldcolumn = "0"
    wo.foldenable = false
    wo.list = false
    wo.conceallevel = 0
    wo.winblend = config.winblend
    local buf = vim.api.nvim_win_get_buf(win)
    vim.bo[buf].tabstop = vim.bo[source_buf].tabstop
    vim.bo[buf].vartabstop = vim.bo[source_buf].vartabstop
    vim.bo[buf].modifiable = false
  end

  -- Apply highlighting and line numbers
  M.apply_highlighting(left_buf, right_buf, diff_data)
  M.apply_line_numbers(left_buf, right_buf, diff_data)
  render.align(left_win, right_win)

  -- Calculate hunk positions for navigation and staged state indicators
  hunk_ranges = calculate_hunks(diff_data)
  hunk_starts = get_hunk_starts(hunk_ranges)
  refresh_hunk_states()

  -- Set up synchronized scrolling
  M.setup_scroll_sync()

  -- Set up keymaps
  M.setup_keymaps()

  -- Create command footer
  local footer_row = row + height + 2 -- +2 to account for border
  create_footer_window(col, width, footer_row)
  focus_hunk(1)
end

-- Close the diff viewer
function M.close_diff_window()
  vim.api.nvim_clear_autocmds({ group = ui_group })
  render.clear()
  local wins = { left_win, right_win, footer_win }
  local bufs = { left_buf, right_buf, footer_buf }

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
  footer_win = nil
  footer_buf = nil
  footer_total_width = nil
  hunk_starts = nil
  hunk_ranges = nil
  hunk_states = nil
  active_diff_data = nil
  source_win = nil
  source_buf = nil
end

-- Jump from the diff view to the matching location in the source buffer.
function M.jump_to_source_location()
  if not active_diff_data then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= left_win and current_win ~= right_win then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(current_win)
  local target_line = get_source_line(cursor[1])
  if not target_line then
    vim.notify("No source location for this diff line", vim.log.levels.WARN)
    return
  end

  local target_win = find_source_window()
  local target_buf = source_buf
  local target_file = active_diff_data.file_path
  local target_col = cursor[2]

  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end

  M.close_diff_window()

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  elseif target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_set_current_buf(target_buf)
  elseif target_file and target_file ~= "" then
    vim.cmd("edit " .. vim.fn.fnameescape(target_file))
  else
    vim.notify("Source buffer is no longer available", vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local target_cursor = clamp_cursor(buf, target_line, target_col)
  vim.api.nvim_win_set_cursor(0, target_cursor)
end

-- Jump to next hunk
function M.jump_to_next_hunk()
  if not hunk_starts or #hunk_starts == 0 then
    return
  end

  local current_idx = find_current_hunk_index()
  local next_idx = (current_idx % #hunk_starts) + 1

  local current_win = vim.api.nvim_get_current_win()
  if current_win == left_win or current_win == right_win then
    focus_hunk(next_idx)
  end
end

-- Jump to previous hunk
function M.jump_to_prev_hunk()
  if not hunk_starts or #hunk_starts == 0 then
    return
  end

  local current_idx = find_current_hunk_index()
  -- Handle index 0 (before first hunk) and index 1 (at first hunk) -> go to last hunk
  local prev_idx
  if current_idx <= 1 then
    prev_idx = #hunk_starts
  else
    prev_idx = current_idx - 1
  end

  local current_win = vim.api.nvim_get_current_win()
  if current_win == left_win or current_win == right_win then
    focus_hunk(prev_idx)
  end
end

-- Toggle staging for the hunk under the cursor
function M.toggle_current_hunk_stage()
  if not hunk_starts or #hunk_starts == 0 then
    vim.notify("No hunks to toggle", vim.log.levels.WARN)
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= left_win and current_win ~= right_win then
    return
  end

  local current_idx = find_current_hunk_index(true)
  if current_idx == 0 then
    vim.notify("No hunk under cursor", vim.log.levels.WARN)
    return
  end

  local git = require("diffy.git")
  if git.toggle_hunk_stage(active_diff_data, hunk_starts[current_idx]) then
    refresh_hunk_states()
    update_footer_status()
  end
end

M.stage_current_hunk = M.toggle_current_hunk_stage

-- Apply line backgrounds and inline changes without replacing syntax colors.
function M.apply_highlighting(left, right, diff_data)
  render.highlight(left, right, diff_data)
end

-- A real gutter keeps continuation rows indented and out of the source text.
function M.statuscolumn()
  local win = vim.g.statusline_winid
  local info = active_diff_data
    and (win == left_win and active_diff_data.left_line_info or active_diff_data.right_line_info)
  local line = info and info[vim.v.lnum]
  local group = "LineNr"
  local sign = " "
  if line and line.type == "remove" then
    group, sign = "DiffyDelete", "-"
  elseif line and line.type == "add" then
    group, sign = "DiffyAdd", "+"
  end
  local number = line and line.num and tostring(line.num) or ""
  if vim.v.virtnum ~= 0 then
    sign, number = " ", ""
  end
  return string.format("%%#%s#%s %" .. gutter_width .. "s │ ", group, sign, number)
end

function M.apply_line_numbers(_left, _right, diff_data)
  gutter_width = 4
  for _, info in ipairs({ diff_data.left_line_info or {}, diff_data.right_line_info or {} }) do
    for _, line in ipairs(info) do
      gutter_width = math.max(gutter_width, #(tostring(line.num or "")))
    end
  end
  for _, win in ipairs({ left_win, right_win }) do
    vim.wo[win].statuscolumn = '%!v:lua.require("diffy.ui").statuscolumn()'
  end
  -- Force gutter width calculation before measuring the wrapped content.
  vim.cmd("redraw")
end

-- Synchronize both cursor movement and scrolling without cursor movement (wheel/C-e).
function M.setup_scroll_sync()
  local syncing = false
  local function sync_scroll()
    if syncing or not left_win or not right_win then
      return
    end
    if not vim.api.nvim_win_is_valid(left_win) or not vim.api.nvim_win_is_valid(right_win) then
      return
    end
    local current = vim.api.nvim_get_current_win()
    if current ~= left_win and current ~= right_win then
      return
    end
    syncing = true
    render.sync_scroll(current, current == left_win and right_win or left_win)
    update_footer_status()
    syncing = false
  end
  for _, buf in ipairs({ left_buf, right_buf }) do
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = ui_group,
      buffer = buf,
      callback = sync_scroll,
    })
  end
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = ui_group,
    pattern = { tostring(left_win), tostring(right_win) },
    callback = sync_scroll,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = ui_group,
    callback = function()
      if
        left_win
        and right_win
        and vim.api.nvim_win_is_valid(left_win)
        and vim.api.nvim_win_is_valid(right_win)
      then
        render.align(left_win, right_win)
        sync_scroll()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = ui_group,
    callback = resize_windows,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = ui_group,
    callback = setup_highlights,
  })
end

-- Set up keymaps for closing and navigation
function M.setup_keymaps()
  for _, buf in ipairs({ left_buf, right_buf }) do
    vim.keymap.set("n", "q", M.close_diff_window, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", M.close_diff_window, { buffer = buf, silent = true })
    vim.keymap.set("n", "<C-c>", M.close_diff_window, { buffer = buf, silent = true })
    vim.keymap.set("n", "<CR>", M.jump_to_source_location, { buffer = buf, silent = true })
    vim.keymap.set("n", "n", M.jump_to_next_hunk, { buffer = buf, silent = true })
    vim.keymap.set("n", "p", M.jump_to_prev_hunk, { buffer = buf, silent = true })
    vim.keymap.set("n", "a", M.toggle_current_hunk_stage, { buffer = buf, silent = true })
  end
end

return M

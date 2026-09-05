local M = {}

local namespace = vim.api.nvim_create_namespace('diffy_content')
local padding_namespace = vim.api.nvim_create_namespace('diffy_padding')
local row_heights = {}
local text_heights = {}
local text_widths = {}

-- Preserve syntax colors; only exact inline changes receive bold emphasis.
function M.setup_highlights()
  local light = vim.o.background == 'light'
  local colors = {
    DiffyAdd = { light and '#dafbe1' or '#142b21', light and 194 or 22 },
    DiffyDelete = { light and '#ffebe9' or '#2b1b20', light and 224 or 52 },
    DiffyAddText = { light and '#abf2bc' or '#1f633b', light and 157 or 28 },
    DiffyDeleteText = { light and '#ffcecb' or '#7d2834', light and 217 or 88 },
    DiffyFiller = { light and '#f6f8fa' or '#161b22', light and 255 or 234 },
  }
  for name, color in pairs(colors) do
    local highlight = { bg = color[1], ctermbg = color[2], default = true }
    if name == 'DiffyAddText' or name == 'DiffyDeleteText' then
      highlight.bold = true
    end
    vim.api.nvim_set_hl(0, name, highlight)
  end
end

local function highlight_side(buf, info, word_diffs, side, group)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  for row, line in ipairs(info or {}) do
    local line_group
    if line.type == 'add' or line.type == 'remove' then
      line_group = group
    elseif line.type == 'empty' then
      line_group = 'DiffyFiller'
    end
    if line_group then
      -- line_hl_group is composited over inline backgrounds regardless of priority.
      -- A range through the newline still fills wrapped rows/EOL, but lets the
      -- higher-priority character ranges supply their own backgrounds.
      vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, 0, {
        end_row = row,
        end_col = 0,
        hl_group = line_group,
        hl_eol = true,
        priority = 100,
      })
    end
    local ranges = word_diffs[row] and word_diffs[row][side] or {}
    for _, range in ipairs(ranges) do
      vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, range.start, {
        end_col = range.stop,
        hl_group = group .. 'Text',
        priority = 200,
      })
    end
  end
end

-- Apply full-width line tint and stronger, side-specific inline highlights.
function M.highlight(left, right, data)
  M.setup_highlights()
  highlight_side(left, data.left_line_info, data.word_diffs or {}, 'left', 'DiffyDelete')
  highlight_side(right, data.right_line_info, data.word_diffs or {}, 'right', 'DiffyAdd')
end

-- Pad the shorter side with virtual rows, keeping buffer/source line mappings intact.
-- Neovim measures wrapping, including tabs and wide characters, for us.
function M.align(left, right)
  row_heights, text_heights, text_widths = {}, {}, {}
  for _, win in ipairs({ left, right }) do
    local buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_buf_clear_namespace(buf, padding_namespace, 0, -1)
    text_widths[win] =
      math.max(1, vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff)
    text_heights[win] = {}
    for row = 1, vim.api.nvim_buf_line_count(buf) do
      local height = vim.api.nvim_win_text_height(win, {
        start_row = row - 1,
        end_row = row - 1,
        start_vcol = 0,
      }).all
      text_heights[win][row] = height
      row_heights[row] = math.max(row_heights[row] or 0, height)
    end
  end
  for _, win in ipairs({ left, right }) do
    local buf = vim.api.nvim_win_get_buf(win)
    local blank = { { string.rep(' ', text_widths[win]), 'DiffyFiller' } }
    for row, height in ipairs(text_heights[win]) do
      local padding = {}
      for _ = height + 1, row_heights[row] do
        padding[#padding + 1] = blank
      end
      if #padding > 0 then
        vim.api.nvim_buf_set_extmark(buf, padding_namespace, row - 1, 0, {
          virt_lines = padding,
        })
      end
    end
  end
end

-- Translate the top screen row between wrapped text and the other side's filler.
function M.sync_scroll(source, target)
  if not text_heights[source] or not text_heights[target] then
    return
  end
  local view = vim.api.nvim_win_call(source, vim.fn.winsaveview)
  local row = view.topline
  local offset = math.floor(view.skipcol / text_widths[source])
  if view.topfill > 0 and row > 1 then
    row = row - 1
    offset = row_heights[row] - view.topfill
  end
  local target_view = { topline = row, topfill = 0, skipcol = 0, leftcol = view.leftcol }
  if offset >= text_heights[target][row] and row < #row_heights then
    target_view.topline = row + 1
    target_view.topfill = row_heights[row] - offset
  else
    target_view.skipcol = offset * text_widths[target]
  end
  local cursor = vim.api.nvim_win_get_cursor(source)
  vim.api.nvim_win_call(target, function()
    vim.api.nvim_win_set_cursor(target, cursor)
    vim.fn.winrestview(target_view)
  end)
end

function M.clear()
  row_heights, text_heights, text_widths = {}, {}, {}
end

return M

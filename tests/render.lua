local git = require('diffy.git')
local ui = require('diffy.ui')
local render = require('diffy.render')

local function equal(actual, expected)
  assert(
    vim.deep_equal(actual, expected),
    'Expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual)
  )
end

local function test_inline_ranges()
  equal(git.compute_word_diff('same', 'same'), nil)
  equal(git.compute_word_diff('a=1; b=2', 'a=3; b=4'), {
    left = { { start = 2, stop = 3 }, { start = 7, stop = 8 } },
    right = { { start = 2, stop = 3 }, { start = 7, stop = 8 } },
  })
  equal(git.compute_word_diff('abc', 'abXYZc'), {
    left = {},
    right = { { start = 2, stop = 5 } },
  })
  equal(git.compute_word_diff('abXYZc', 'abc'), {
    left = { { start = 2, stop = 5 } },
    right = {},
  })
  equal(git.compute_word_diff('', 'text'), {
    left = {},
    right = { { start = 0, stop = 4 } },
  })
  equal(git.compute_word_diff('text', ''), {
    left = { { start = 0, stop = 4 } },
    right = {},
  })
  equal(git.compute_word_diff('café 🙂', 'cafê 🙃'), {
    left = { { start = 3, stop = 5 }, { start = 6, stop = 10 } },
    right = { { start = 3, stop = 5 }, { start = 6, stop = 10 } },
  })
  equal(git.compute_word_diff('a b', 'a\tb'), {
    left = { { start = 1, stop = 2 } },
    right = { { start = 1, stop = 2 } },
  })
end

local function diff_windows()
  local left, right
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local title = vim.api.nvim_win_get_config(win).title
    if title and title[1][1] == ' Original ' then
      left = win
    elseif title and title[1][1] == ' Modified ' then
      right = win
    end
  end
  assert(left and right, 'Expected two diff panes')
  return left, right
end

local function test_rendering()
  vim.o.columns, vim.o.lines = 140, 40
  local source_buf = vim.api.nvim_get_current_buf()
  local long_line = '\t' .. string.rep('界 long content ', 14)
  local data = git.parse_and_align_diff(table.concat({
    '--- a/test',
    '+++ b/test',
    '@@ -1,5 +1,6 @@',
    ' context',
    '-short',
    '+' .. long_line,
    ' after wrap',
    '-a=1; b=2',
    '+a=3; b=4',
    '+',
    ' end',
  }, '\n'))
  vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, {
    'context',
    long_line,
    'after wrap',
    'a=3; b=4',
    '',
    'end',
  })
  ui.open_diff_window(data)
  local left, right = diff_windows()
  local left_buf = vim.api.nvim_win_get_buf(left)
  local right_buf = vim.api.nvim_win_get_buf(right)
  for _, win in ipairs({ left, right }) do
    assert(vim.wo[win].wrap, 'Wrapping must be enabled by default')
    assert(not vim.bo[vim.api.nvim_win_get_buf(win)].modifiable, 'Diff must be read-only')
  end

  local function check_alignment()
    for row = 0, #data.left_content - 1 do
      local opts = { start_row = 0, end_row = row, end_vcol = 0 }
      equal(
        vim.api.nvim_win_text_height(left, opts).all,
        vim.api.nvim_win_text_height(right, opts).all
      )
    end
  end
  check_alignment()
  assert(vim.api.nvim_win_text_height(right, {
    start_row = 1,
    end_row = 1,
    start_vcol = 0,
  }).all > 1, 'Long lines must occupy multiple screen rows')
  equal(vim.api.nvim_buf_get_lines(left_buf, 0, -1, false), data.left_content)
  equal(vim.api.nvim_buf_get_lines(right_buf, 0, -1, false), data.right_content)

  for _, side in ipairs({ { left, '-    2 │ ' }, { right, '+    2 │ ' } }) do
    local gutter = vim.api.nvim_eval_statusline(vim.wo[side[1]].statuscolumn, {
      winid = side[1],
      use_statuscol_lnum = 2,
    })
    equal(gutter.str, side[2])
  end

  local ns = vim.api.nvim_get_namespaces().diffy_content
  for _, side in ipairs({ { left_buf, 'DiffyDelete' }, { right_buf, 'DiffyAdd' } }) do
    local marks = vim.api.nvim_buf_get_extmarks(side[1], ns, { 3, 0 }, { 3, -1 }, {
      details = true,
    })
    equal(#marks, 3)
    equal(marks[1][4].hl_group, side[2])
    equal(marks[1][4].line_hl_group, nil)
    equal(marks[1][4].end_row, 4)
    equal(marks[1][4].hl_eol, true)
    equal(marks[2][4].hl_group, side[2] .. 'Text')
    equal(marks[3][4].hl_group, side[2] .. 'Text')
    assert(marks[2][4].priority > marks[1][4].priority)
    -- Only the changed digits get inline emphasis, not the text between them.
    equal({ marks[2][3], marks[2][4].end_col }, { 2, 3 })
    equal({ marks[3][3], marks[3][4].end_col }, { 7, 8 })
    local line_highlight = vim.api.nvim_get_hl(0, { name = side[2] })
    local inline_highlight = vim.api.nvim_get_hl(0, { name = side[2] .. 'Text' })
    assert(not line_highlight.bold, 'The entire line must not become bold')
    equal(inline_highlight.bold, true)
    assert(inline_highlight.bg ~= line_highlight.bg, 'Inline background should stand out')
    equal(inline_highlight.fg, nil) -- Keep the file's syntax foreground colors.
  end
  local blank_marks = vim.api.nvim_buf_get_extmarks(right_buf, ns, { 4, 0 }, { 4, -1 }, {
    details = true,
  })
  equal(blank_marks[1][4].hl_group, 'DiffyAdd')
  equal(blank_marks[1][4].hl_eol, true)

  -- Resizing must recalculate wrapping and padding rather than changing buffer lines.
  vim.o.columns = 100
  vim.api.nvim_exec_autocmds('VimResized', {})
  check_alignment()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative ~= '' and not config.focusable then
      local text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
      assert(text:find('Hunk 1/2', 1, true), 'The footer must retain hunk status')
      assert(vim.fn.strdisplaywidth(text) <= config.width, 'The footer must fit after resizing')
    end
  end
  local padding_ns = vim.api.nvim_get_namespaces().diffy_padding
  local before = vim.api.nvim_buf_get_extmarks(left_buf, padding_ns, 0, -1, {})
  render.align(left, right)
  equal(#vim.api.nvim_buf_get_extmarks(left_buf, padding_ns, 0, -1, {}), #before)

  -- A top row inside wrapped text maps to virtual padding on the shorter side.
  local text_width = vim.api.nvim_win_get_width(right) - vim.fn.getwininfo(right)[1].textoff
  vim.api.nvim_win_call(right, function()
    vim.api.nvim_win_set_cursor(right, { 2, text_width + 10 })
    vim.fn.winrestview({ topline = 2, skipcol = text_width })
  end)
  render.sync_scroll(right, left)
  local left_view = vim.api.nvim_win_call(left, vim.fn.winsaveview)
  equal(left_view.topline, 3)
  assert(left_view.topfill > 0, 'Wrapped scrolling should retain the matching filler rows')
  render.sync_scroll(left, right)
  local right_view = vim.api.nvim_win_call(right, vim.fn.winsaveview)
  equal(right_view.topline, 2)
  equal(right_view.skipcol, text_width)

  -- Scrolling without moving the cursor still synchronizes the top buffer row.
  vim.api.nvim_win_set_cursor(right, { 4, 0 })
  vim.api.nvim_win_call(right, function()
    vim.fn.winrestview({ topline = 3, skipcol = 0, topfill = 0 })
  end)
  vim.api.nvim_exec_autocmds('WinScrolled', { pattern = tostring(right) })
  equal(vim.api.nvim_win_call(left, vim.fn.winsaveview).topline, 3)

  vim.api.nvim_set_hl(0, 'DiffyAddText', { bg = '#123456' })
  render.setup_highlights()
  equal(vim.api.nvim_get_hl(0, { name = 'DiffyAddText' }).bg, 0x123456)
  assert(
    not vim.api.nvim_get_hl(0, { name = 'DiffyAddText' }).bold,
    'Explicit user highlights must still override the default bold style'
  )
  vim.api.nvim_set_hl(0, 'DiffyAddText', {})
  vim.api.nvim_exec_autocmds('ColorScheme', {})
  assert(vim.api.nvim_get_hl(0, { name = 'DiffyAddText' }).bg)
  equal(vim.api.nvim_get_hl(0, { name = 'DiffyAddText' }).bold, true)
  local background = vim.o.background
  vim.o.background = 'light'
  vim.api.nvim_set_hl(0, 'DiffyAdd', {})
  render.setup_highlights()
  equal(vim.api.nvim_get_hl(0, { name = 'DiffyAdd' }).bg, 0xdafbe1)
  vim.o.background = background
  vim.api.nvim_set_hl(0, 'DiffyAdd', {})
  render.setup_highlights()

  vim.api.nvim_win_set_cursor(right, { 2, 13 })
  ui.jump_to_source_location()
  equal(vim.api.nvim_get_current_buf(), source_buf)
  equal(vim.api.nvim_win_get_cursor(0), { 2, 13 })
  equal(#vim.api.nvim_get_autocmds({ group = 'DiffyUI' }), 0)
  assert(not vim.api.nvim_buf_is_valid(left_buf) and not vim.api.nvim_buf_is_valid(right_buf))

  require('diffy').config.wrap = false
  ui.open_diff_window(data)
  left, right = diff_windows()
  assert(not vim.wo[left].wrap and not vim.wo[right].wrap)
  equal(#vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(left), padding_ns, 0, -1, {}), 0)
  ui.close_diff_window()
  require('diffy').config.wrap = true
end

return function()
  test_inline_ranges()
  test_rendering()
  print('✓ Inline highlighting and wrapped rendering tests passed')
end

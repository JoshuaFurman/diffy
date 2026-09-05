local M = {}

-- Get diff data for a file
function M.get_diff(file_path, target)
  if vim.fn.filereadable(file_path) == 0 then
    vim.notify('File does not exist: ' .. file_path, vim.log.levels.ERROR)
    return nil
  end

  -- Get git root directory
  local git_root = M.get_git_root(file_path)
  if not git_root then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return nil
  end

  -- Get relative path from git root
  local rel_path = vim.fn.fnamemodify(file_path, ':p'):sub(#git_root + 2)

  -- Get git diff
  local diff_output = M.get_git_diff(git_root, rel_path, target)
  if not diff_output or diff_output == '' then
    vim.notify('No changes to display', vim.log.levels.INFO)
    return nil
  end

  -- Parse diff and build aligned content
  local diff_data = M.parse_and_align_diff(diff_output)
  diff_data.git_root = git_root
  diff_data.rel_path = rel_path
  diff_data.file_path = vim.fn.fnamemodify(file_path, ':p')
  diff_data.target = target

  return diff_data
end

-- Get git root directory
function M.get_git_root(file_path)
  local Job = require('plenary.job')

  local job = Job:new({
    command = 'git',
    args = { 'rev-parse', '--show-toplevel' },
    cwd = vim.fn.fnamemodify(file_path, ':p:h'),
  })

  local result = job:sync()

  if job.code ~= 0 or #result == 0 then
    return nil
  end

  return result[1]
end

-- Get git diff output
function M.get_git_diff(git_root, rel_path, target)
  local Job = require('plenary.job')

  local args
  if target == 'staged' then
    args = { 'diff', '--cached', '--no-color', '--no-ext-diff', '-U999999', '--', rel_path }
  elseif target and target ~= '' then
    -- Compare specific commit/ref to working directory
    args = { 'diff', '--no-color', '--no-ext-diff', '-U999999', target, '--', rel_path }
  else
    -- Default: compare HEAD to working directory
    args = { 'diff', '--no-color', '--no-ext-diff', '-U999999', 'HEAD', '--', rel_path }
  end

  local job = Job:new({
    command = 'git',
    args = args,
    cwd = git_root,
  })

  local result = job:sync()

  if #result == 0 then
    return nil
  end

  return table.concat(result, '\n')
end

-- Get zero-context unstaged diff output for staging a single hunk.
function M.get_unstaged_diff(git_root, rel_path)
  local Job = require('plenary.job')

  local job = Job:new({
    command = 'git',
    args = { 'diff', '--no-color', '--no-ext-diff', '--unified=0', '--', rel_path },
    cwd = git_root,
  })

  local result = job:sync()

  if job.code ~= 0 or #result == 0 then
    return nil
  end

  return table.concat(result, '\n')
end

-- Get zero-context staged diff output for unstaging a single hunk.
function M.get_staged_diff(git_root, rel_path)
  local Job = require('plenary.job')

  local job = Job:new({
    command = 'git',
    args = { 'diff', '--cached', '--no-color', '--no-ext-diff', '--unified=0', '--', rel_path },
    cwd = git_root,
  })

  local result = job:sync()

  if job.code ~= 0 or #result == 0 then
    return nil
  end

  return table.concat(result, '\n')
end

local function parse_count(count)
  if count == nil or count == '' then
    return 1
  end

  return tonumber(count)
end

-- Parse a unified diff hunk header.
function M.parse_hunk_header(line)
  local old_start, old_count, new_start, new_count =
    line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

  if not old_start or not new_start then
    return nil
  end

  old_start = tonumber(old_start)
  new_start = tonumber(new_start)
  old_count = parse_count(old_count)
  new_count = parse_count(new_count)

  return {
    old_start = old_start,
    old_count = old_count,
    old_end = old_count > 0 and old_start + old_count - 1 or old_start,
    new_start = new_start,
    new_count = new_count,
    new_end = new_count > 0 and new_start + new_count - 1 or new_start,
  }
end

-- Parse patch text into file headers and individual hunks.
function M.parse_patch_hunks(diff_text)
  local parsed = {
    header = {},
    hunks = {},
  }
  local current_hunk = nil
  local lines = vim.split(diff_text, '\n', { plain = true, trimempty = true })

  for _, line in ipairs(lines) do
    if line:match('^@@') then
      if current_hunk then
        table.insert(parsed.hunks, current_hunk)
      end

      local hunk_info = M.parse_hunk_header(line)
      if hunk_info then
        current_hunk = vim.tbl_extend('force', hunk_info, { lines = { line } })
      else
        current_hunk = { lines = { line } }
      end
    elseif current_hunk then
      table.insert(current_hunk.lines, line)
    else
      table.insert(parsed.header, line)
    end
  end

  if current_hunk then
    table.insert(parsed.hunks, current_hunk)
  end

  return parsed
end

local function is_display_change(diff_data, display_line)
  local left_info = diff_data.left_line_info and diff_data.left_line_info[display_line]

  return left_info and (left_info.type == 'remove' or left_info.type == 'empty')
end

local function update_range(range, line_num)
  if not line_num then
    return
  end

  if not range.start or line_num < range.start then
    range.start = line_num
  end

  if not range.stop or line_num > range.stop then
    range.stop = line_num
  end
end

-- Get old/new line ranges for the displayed logical hunk at display_line.
function M.get_display_hunk(diff_data, display_line)
  if not diff_data or not diff_data.left_line_info or not diff_data.right_line_info then
    return nil
  end

  if not is_display_change(diff_data, display_line) then
    return nil
  end

  local start_line = display_line
  while start_line > 1 and is_display_change(diff_data, start_line - 1) do
    start_line = start_line - 1
  end

  local end_line = display_line
  while end_line < #diff_data.left_line_info and is_display_change(diff_data, end_line + 1) do
    end_line = end_line + 1
  end

  local old_range = {}
  local new_range = {}

  for i = start_line, end_line do
    local left_info = diff_data.left_line_info[i]
    local right_info = diff_data.right_line_info[i]

    if left_info and left_info.type == 'remove' then
      update_range(old_range, left_info.num)
    end

    if right_info and right_info.type == 'add' then
      update_range(new_range, right_info.num)
    end
  end

  return {
    display_start = start_line,
    display_end = end_line,
    old_start = old_range.start,
    old_end = old_range.stop,
    old_count = old_range.start and old_range.stop - old_range.start + 1 or 0,
    new_start = new_range.start,
    new_end = new_range.stop,
    new_count = new_range.start and new_range.stop - new_range.start + 1 or 0,
  }
end

local function range_matches(display_start, display_end, hunk_start, hunk_end, hunk_count)
  if not display_start then
    return true
  end

  return hunk_count > 0 and display_start == hunk_start and display_end == hunk_end
end

local function ranges_overlap(display_start, display_end, hunk_start, hunk_end, hunk_count)
  if not display_start or hunk_count == 0 then
    return false
  end

  return display_start <= hunk_end and hunk_start <= display_end
end

local function hunk_overlaps_display(display_hunk, patch_hunk)
  local old_matches = range_matches(
    display_hunk.old_start,
    display_hunk.old_end,
    patch_hunk.old_start,
    patch_hunk.old_end,
    patch_hunk.old_count or 0
  )
  local new_matches = range_matches(
    display_hunk.new_start,
    display_hunk.new_end,
    patch_hunk.new_start,
    patch_hunk.new_end,
    patch_hunk.new_count or 0
  )

  if old_matches and new_matches then
    return true
  end

  local old_overlaps = ranges_overlap(
    display_hunk.old_start,
    display_hunk.old_end,
    patch_hunk.old_start,
    patch_hunk.old_end,
    patch_hunk.old_count or 0
  )
  local new_overlaps = ranges_overlap(
    display_hunk.new_start,
    display_hunk.new_end,
    patch_hunk.new_start,
    patch_hunk.new_end,
    patch_hunk.new_count or 0
  )

  return old_overlaps or new_overlaps
end

-- Find patch hunks that overlap a displayed logical hunk.
function M.find_matching_patch_hunks(display_hunk, parsed_patch)
  if not display_hunk or not parsed_patch then
    return {}
  end

  local matching_hunks = {}

  for _, hunk in ipairs(parsed_patch.hunks or {}) do
    if hunk_overlaps_display(display_hunk, hunk) then
      table.insert(matching_hunks, hunk)
    end
  end

  return matching_hunks
end

-- Find the first patch hunk that overlaps a displayed logical hunk.
function M.find_matching_patch_hunk(display_hunk, parsed_patch)
  local matching_hunks = M.find_matching_patch_hunks(display_hunk, parsed_patch)

  return matching_hunks[1]
end

-- Build a patch containing selected hunks from a parsed file diff.
function M.build_hunk_patch(parsed_patch, hunks)
  local patch_lines = {}

  for _, line in ipairs(parsed_patch.header or {}) do
    table.insert(patch_lines, line)
  end

  for _, hunk in ipairs(hunks or {}) do
    for _, line in ipairs(hunk.lines or {}) do
      table.insert(patch_lines, line)
    end
  end

  return table.concat(patch_lines, '\n') .. '\n'
end

-- Build a patch containing only one hunk from a parsed file diff.
function M.build_single_hunk_patch(parsed_patch, hunk)
  return M.build_hunk_patch(parsed_patch, { hunk })
end

-- Apply a patch to the index.
function M.apply_patch_to_index(git_root, patch, reverse)
  local args = { 'git', '-C', git_root, 'apply', '--cached', '--unidiff-zero', '-' }
  if reverse then
    table.insert(args, 6, '--reverse')
  end

  local output = vim.fn.system(args, patch)

  if vim.v.shell_error ~= 0 then
    return false, output
  end

  return true
end

function M.get_hunk_state(diff_data, display_line)
  if not diff_data or not diff_data.git_root or not diff_data.rel_path then
    return nil
  end

  if diff_data.target == 'staged' then
    return 'staged'
  elseif diff_data.target and diff_data.target ~= '' then
    return 'readonly'
  end

  local display_hunk = M.get_display_hunk(diff_data, display_line)
  if not display_hunk then
    return nil
  end

  local staged_count = 0
  local staged_diff = M.get_staged_diff(diff_data.git_root, diff_data.rel_path)
  if staged_diff then
    staged_count = #M.find_matching_patch_hunks(display_hunk, M.parse_patch_hunks(staged_diff))
  end

  local unstaged_count = 0
  local unstaged_diff = M.get_unstaged_diff(diff_data.git_root, diff_data.rel_path)
  if unstaged_diff then
    unstaged_count = #M.find_matching_patch_hunks(display_hunk, M.parse_patch_hunks(unstaged_diff))
  end

  if staged_count > 0 and unstaged_count > 0 then
    return 'partial'
  elseif staged_count > 0 then
    return 'staged'
  elseif unstaged_count > 0 then
    return 'unstaged'
  end

  return 'unknown'
end

function M.get_hunk_states(diff_data, display_lines)
  local states = {}

  if not diff_data or not display_lines then
    return states
  end

  if diff_data.target == 'staged' then
    for i = 1, #display_lines do
      states[i] = 'staged'
    end
    return states
  elseif diff_data.target and diff_data.target ~= '' then
    for i = 1, #display_lines do
      states[i] = 'readonly'
    end
    return states
  end

  if not diff_data.git_root or not diff_data.rel_path then
    for i = 1, #display_lines do
      states[i] = 'unknown'
    end
    return states
  end

  local staged_patch = nil
  local staged_diff = M.get_staged_diff(diff_data.git_root, diff_data.rel_path)
  if staged_diff then
    staged_patch = M.parse_patch_hunks(staged_diff)
  end

  local unstaged_patch = nil
  local unstaged_diff = M.get_unstaged_diff(diff_data.git_root, diff_data.rel_path)
  if unstaged_diff then
    unstaged_patch = M.parse_patch_hunks(unstaged_diff)
  end

  for i, display_line in ipairs(display_lines) do
    local display_hunk = M.get_display_hunk(diff_data, display_line)
    if display_hunk then
      local staged_count = 0
      if staged_patch then
        staged_count = #M.find_matching_patch_hunks(display_hunk, staged_patch)
      end

      local unstaged_count = 0
      if unstaged_patch then
        unstaged_count = #M.find_matching_patch_hunks(display_hunk, unstaged_patch)
      end

      if staged_count > 0 and unstaged_count > 0 then
        states[i] = 'partial'
      elseif staged_count > 0 then
        states[i] = 'staged'
      elseif unstaged_count > 0 then
        states[i] = 'unstaged'
      else
        states[i] = 'unknown'
      end
    end
  end

  return states
end

-- Toggle the displayed hunk in the index.
function M.toggle_hunk_stage(diff_data, display_line)
  if not diff_data or not diff_data.git_root or not diff_data.rel_path then
    vim.notify('Diffy cannot toggle this hunk: missing git metadata', vim.log.levels.ERROR)
    return false
  end

  if diff_data.target and diff_data.target ~= '' then
    vim.notify('Hunk staging is only available from :Diffy without a target', vim.log.levels.WARN)
    return false
  end

  local display_hunk = M.get_display_hunk(diff_data, display_line)
  if not display_hunk then
    vim.notify('No hunk under cursor', vim.log.levels.WARN)
    return false
  end

  local state = M.get_hunk_state(diff_data, display_line)
  local should_unstage = state == 'staged'
  local source_diff
  if should_unstage then
    source_diff = M.get_staged_diff(diff_data.git_root, diff_data.rel_path)
  else
    source_diff = M.get_unstaged_diff(diff_data.git_root, diff_data.rel_path)
  end

  if not source_diff then
    vim.notify('No matching changes to toggle for this file', vim.log.levels.INFO)
    return false
  end

  local parsed_patch = M.parse_patch_hunks(source_diff)
  local patch_hunks = M.find_matching_patch_hunks(display_hunk, parsed_patch)
  if #patch_hunks == 0 then
    vim.notify('No matching hunk under cursor', vim.log.levels.WARN)
    return false
  end

  local patch = M.build_hunk_patch(parsed_patch, patch_hunks)
  local ok, err = M.apply_patch_to_index(diff_data.git_root, patch, should_unstage)
  if not ok then
    local message = err and vim.trim(err) or ''
    if message ~= '' then
      vim.notify('Failed to toggle hunk: ' .. message, vim.log.levels.ERROR)
    else
      vim.notify('Failed to toggle hunk', vim.log.levels.ERROR)
    end
    return false
  end

  vim.notify(should_unstage and 'Unstaged hunk' or 'Staged hunk', vim.log.levels.INFO)
  return true
end

-- Stage the displayed hunk by applying matching unstaged patch hunks to the index.
function M.stage_hunk(diff_data, display_line)
  local state = M.get_hunk_state(diff_data, display_line)
  if state == 'staged' then
    vim.notify('Hunk is already staged', vim.log.levels.INFO)
    return false
  end

  return M.toggle_hunk_stage(diff_data, display_line)
end

-- Diff characters rather than bytes so highlight boundaries never split UTF-8.
local function split_characters(line)
  local characters = vim.fn.split(line, '\\zs')
  local offsets = { 0 }
  for _, character in ipairs(characters) do
    offsets[#offsets + 1] = offsets[#offsets] + #character
  end
  local text = #characters > 0 and table.concat(characters, '\n') .. '\n' or ''
  return text, offsets
end

-- Return lists of zero-based, end-exclusive byte ranges on each side.
-- Separate edits on a line stay separate instead of highlighting the text between them.
function M.compute_word_diff(old_line, new_line)
  if old_line == new_line then
    return nil
  end

  local old_text, old_offsets = split_characters(old_line)
  local new_text, new_offsets = split_characters(new_line)
  local hunks = vim.diff(old_text, new_text, { result_type = 'indices', algorithm = 'minimal' })
  local result = { left = {}, right = {} }
  for _, hunk in ipairs(hunks) do
    if hunk[2] > 0 then
      table.insert(result.left, {
        start = old_offsets[hunk[1]],
        stop = old_offsets[hunk[1] + hunk[2]],
      })
    end
    if hunk[4] > 0 then
      table.insert(result.right, {
        start = new_offsets[hunk[3]],
        stop = new_offsets[hunk[3] + hunk[4]],
      })
    end
  end
  return result
end

-- Parse diff and create aligned content for side-by-side view
-- Uses GitHub-style pairing: consecutive deletions and additions are zipped together
function M.parse_and_align_diff(diff_text)
  local lines = vim.split(diff_text, '\n')
  local left_content = {}
  local right_content = {}
  local left_highlights = {}
  local right_highlights = {}
  local left_line_info = {}
  local right_line_info = {}
  local word_diffs = {}
  local left_num = 0
  local right_num = 0
  local display_line = 0

  -- Buffers for collecting consecutive changes
  local pending_removes = {}
  local pending_adds = {}

  -- Flush pending changes by pairing deletions with additions
  local function flush_pending()
    local max_len = math.max(#pending_removes, #pending_adds)

    for i = 1, max_len do
      display_line = display_line + 1
      local remove = pending_removes[i]
      local add = pending_adds[i]

      if remove and add then
        -- Paired modification - both sides have content
        table.insert(left_content, remove.content)
        table.insert(right_content, add.content)
        table.insert(left_line_info, { num = remove.num, type = 'remove' })
        table.insert(right_line_info, { num = add.num, type = 'add' })
        table.insert(left_highlights, display_line)
        table.insert(right_highlights, display_line)

        word_diffs[display_line] = M.compute_word_diff(remove.content, add.content)
      elseif remove then
        -- Pure deletion - only left side has content
        table.insert(left_content, remove.content)
        table.insert(right_content, '')
        table.insert(left_line_info, { num = remove.num, type = 'remove' })
        table.insert(right_line_info, { num = nil, type = 'empty' })
        table.insert(left_highlights, display_line)
      else
        -- Pure addition - only right side has content
        table.insert(left_content, '')
        table.insert(right_content, add.content)
        table.insert(left_line_info, { num = nil, type = 'empty' })
        table.insert(right_line_info, { num = add.num, type = 'add' })
        table.insert(right_highlights, display_line)
      end
    end

    pending_removes = {}
    pending_adds = {}
  end

  for _, line in ipairs(lines) do
    if line:match('^@@') then
      -- Flush any pending changes before processing hunk header
      flush_pending()

      -- Parse hunk header to get line numbers
      local old_start = line:match('@@ %-(%d+)')
      local new_start = line:match('%+(%d+)')

      if old_start and new_start then
        -- If this is not the first hunk (display_line > 0), add a separator line
        if display_line > 0 then
          display_line = display_line + 1
          table.insert(
            left_content,
            '──────────────────────────────────────────────────'
          )
          table.insert(
            right_content,
            '──────────────────────────────────────────────────'
          )
          table.insert(left_line_info, { num = nil, type = 'separator' })
          table.insert(right_line_info, { num = nil, type = 'separator' })
        end

        left_num = tonumber(old_start) - 1
        right_num = tonumber(new_start) - 1
      end
    elseif
      not (
        line:match('^%-%-%-')
        or line:match('^%+%+%+')
        or line:match('^diff')
        or line:match('^index')
      )
    then
      local prefix = line:sub(1, 1)
      local content = line:sub(2)

      if prefix == ' ' then
        -- Context line - flush pending changes first, then add context
        flush_pending()
        left_num = left_num + 1
        right_num = right_num + 1
        display_line = display_line + 1
        table.insert(left_content, content)
        table.insert(right_content, content)
        table.insert(left_line_info, { num = left_num, type = 'context' })
        table.insert(right_line_info, { num = right_num, type = 'context' })
      elseif prefix == '-' then
        -- Removed line - buffer it for pairing
        left_num = left_num + 1
        table.insert(pending_removes, { content = content, num = left_num })
      elseif prefix == '+' then
        -- Added line - buffer it for pairing
        right_num = right_num + 1
        table.insert(pending_adds, { content = content, num = right_num })
      end
    end
  end

  -- Flush any remaining pending changes
  flush_pending()

  return {
    left_content = left_content,
    right_content = right_content,
    left_highlights = left_highlights,
    right_highlights = right_highlights,
    left_line_info = left_line_info,
    right_line_info = right_line_info,
    word_diffs = word_diffs,
  }
end

return M

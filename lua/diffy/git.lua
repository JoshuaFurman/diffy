local M = {}

-- Get diff data for a file
function M.get_diff(file_path, target)
  local Job = require('plenary.job')

  -- Check if file exists and is in a git repo
  if vim.fn.filereadable(file_path) == 0 then
    vim.notify('File does not exist: ' .. file_path, vim.log.levels.ERROR)
    return nil
  end

  -- Determine diff command based on target
  local cmd
  if target == 'staged' then
    cmd = { 'git', 'diff', '--cached', file_path }
  elseif target == 'head' or target == '' then
    cmd = { 'git', 'diff', 'HEAD', file_path }
  else
    -- Assume target is a commit hash
    cmd = { 'git', 'show', target .. ':' .. vim.fn.fnamemodify(file_path, ':p:t') }
  end

  local job = Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = vim.fn.fnamemodify(file_path, ':p:h'),
  })

  local result = job:sync()

  if job.code ~= 0 and #result == 0 then
    vim.notify('Failed to get diff for: ' .. file_path, vim.log.levels.WARN)
    return nil
  end

  if #result == 0 then
    return nil
  end

  return M.parse_diff(table.concat(result, '\n'))
end

-- Parse unified diff format
function M.parse_diff(diff_text)
  local lines = vim.split(diff_text, '\n')
  local hunks = {}
  local current_hunk = nil

  for _, line in ipairs(lines) do
    if line:match('^@@') then
      -- New hunk
      if current_hunk then
        table.insert(hunks, current_hunk)
      end

      local old_start, old_count, new_start, new_count = line:match('@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')
      current_hunk = {
        old_start = tonumber(old_start) or 0,
        old_count = tonumber(old_count) or 0,
        new_start = tonumber(new_start) or 0,
        new_count = tonumber(new_count) or 0,
        lines = {}
      }
    elseif current_hunk then
      local prefix = line:sub(1, 1)
      local content = line:sub(2)

      if prefix == ' ' then
        -- Context line
        table.insert(current_hunk.lines, { type = 'context', content = content })
      elseif prefix == '-' then
        -- Removed line
        table.insert(current_hunk.lines, { type = 'remove', content = content })
      elseif prefix == '+' then
        -- Added line
        table.insert(current_hunk.lines, { type = 'add', content = content })
      end
    end
  end

  -- Add final hunk
  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return {
    hunks = hunks,
    left_content = M.build_side_content(hunks, 'left'),
    right_content = M.build_side_content(hunks, 'right')
  }
end

-- Build content for one side of the diff
function M.build_side_content(hunks, side)
  local content = {}
  local line_num = 1

  for _, hunk in ipairs(hunks) do
    -- Add context lines before hunk
    for i = 1, hunk.old_start - line_num do
      table.insert(content, '')
    end

    -- Add hunk lines
    for _, line in ipairs(hunk.lines) do
      _ = line -- Mark as used
      if side == 'left' then
        if line.type == 'remove' or line.type == 'context' then
          table.insert(content, line.content)
        elseif line.type == 'add' then
          table.insert(content, '')
        end
      else -- right side
        if line.type == 'add' or line.type == 'context' then
          table.insert(content, line.content)
        elseif line.type == 'remove' then
          table.insert(content, '')
        end
      end
    end

    line_num = hunk.new_start + hunk.new_count
  end

  return content
end

return M
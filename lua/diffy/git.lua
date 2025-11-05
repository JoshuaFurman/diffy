local M = {}

-- Get diff data for a file
function M.get_diff(file_path, target)
  local Job = require('plenary.job')

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
  return M.parse_and_align_diff(diff_output)
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
    args = { 'diff', '--cached', '--no-color', '--no-ext-diff', '-U999999', rel_path }
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

-- Parse diff and create aligned content for side-by-side view
function M.parse_and_align_diff(diff_text)
  local lines = vim.split(diff_text, '\n')
  local left_content = {}
  local right_content = {}
  local left_highlights = {}
  local right_highlights = {}
  local left_line_nums = {}
  local right_line_nums = {}
  local left_num = 0
  local right_num = 0
  local display_line = 0

  for _, line in ipairs(lines) do
    if line:match('^@@') then
      -- Parse hunk header to get line numbers
      local old_start = line:match('@@ %-(%d+)')
      local new_start = line:match('%+(%d+)')
      left_num = tonumber(old_start) - 1
      right_num = tonumber(new_start) - 1
    elseif not (line:match('^%-%-%-') or line:match('^%+%+%+') or line:match('^diff') or line:match('^index')) then
      local prefix = line:sub(1, 1)
      local content = line:sub(2)
      
      if prefix == ' ' then
        -- Context line - same on both sides
        left_num = left_num + 1
        right_num = right_num + 1
        display_line = display_line + 1
        table.insert(left_content, content)
        table.insert(right_content, content)
        table.insert(left_line_nums, '  ' .. left_num)
        table.insert(right_line_nums, '  ' .. right_num)
      elseif prefix == '-' then
        -- Removed line - only on left
        left_num = left_num + 1
        display_line = display_line + 1
        table.insert(left_content, content)
        table.insert(right_content, '')
        table.insert(left_line_nums, '- ' .. left_num)
        table.insert(right_line_nums, '  ')
        table.insert(left_highlights, display_line)
      elseif prefix == '+' then
        -- Added line - only on right
        right_num = right_num + 1
        display_line = display_line + 1
        table.insert(left_content, '')
        table.insert(right_content, content)
        table.insert(left_line_nums, '  ')
        table.insert(right_line_nums, '+ ' .. right_num)
        table.insert(right_highlights, display_line)
      end
    end
  end

  return {
    left_content = left_content,
    right_content = right_content,
    left_highlights = left_highlights,
    right_highlights = right_highlights,
    left_line_nums = left_line_nums,
    right_line_nums = right_line_nums
  }
end

return M

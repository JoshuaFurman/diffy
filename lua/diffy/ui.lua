local M = {}

local diffy_namespace = vim.api.nvim_create_namespace("diffy")

-- Window handles
local left_win = nil
local right_win = nil
local left_buf = nil
local right_buf = nil
local footer_win = nil
local footer_buf = nil
local footer_total_width = nil -- Store for dynamic footer updates
local hunk_starts = nil -- Array of hunk start line numbers

-- Calculate hunk start positions from diff data
-- Detects "logical hunks" - contiguous sequences of changes separated by context
local function calculate_hunk_starts(diff_data)
	if not diff_data or not diff_data.left_line_info then
		return {}
	end

	local hunks = {}
	local in_change = false

	for i, info in ipairs(diff_data.left_line_info) do
		-- A line is a "change" if it's a remove or empty (empty = add on right side)
		local is_change = info.type == "remove" or info.type == "empty"

		if is_change and not in_change then
			-- Starting a new change region = new hunk
			table.insert(hunks, i)
			in_change = true
		elseif not is_change then
			-- Context or separator line = end of change region
			in_change = false
		end
	end

	return hunks
end

-- Find the index of the hunk containing the cursor
-- Returns 0 if cursor is before the first hunk
local function find_current_hunk_index()
	if not hunk_starts or #hunk_starts == 0 then
		return 0
	end

	local current_win = vim.api.nvim_get_current_win()
	if current_win ~= left_win and current_win ~= right_win then
		return 0
	end

	local cursor = vim.api.nvim_win_get_cursor(current_win)
	local cursor_line = cursor[1]

	-- Find hunk containing cursor (iterate backwards)
	for i = #hunk_starts, 1, -1 do
		if cursor_line >= hunk_starts[i] then
			return i
		end
	end

	-- Cursor is before the first hunk
	return 0
end

-- Generate footer content with commands and hunk status
local function generate_footer_content(total_width)
	local commands = {
		{ key = "q/Esc", desc = "close" },
		{ key = "n", desc = "next hunk" },
		{ key = "p", desc = "prev hunk" },
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
		hunk_status = string.format("Hunk %d/%d", current_idx, #hunk_starts)
	end

	local separator = "  │  "
	local footer_text = commands_text .. separator .. hunk_status

	-- Center the text within the total width
	local padding = math.floor((total_width - #footer_text) / 2)
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
local function update_footer_status()
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
		vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Special", 0, col_offset, col_offset + #cmd.key)
		col_offset = col_offset + #cmd.key + 1 -- +1 for space after key

		-- Highlight the description
		vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Comment", 0, col_offset, col_offset + #cmd.desc)
		col_offset = col_offset + #cmd.desc + 2 -- +2 for double space separator
	end

	-- Highlight separator (the "│" character)
	local separator_start = content.padding + content.commands_text_len + 2 -- +2 for "  " before separator
	vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Comment", 0, separator_start, separator_start + 3) -- "│" is 3 bytes in UTF-8

	-- Highlight hunk status
	local hunk_status_start = content.padding + content.commands_text_len + content.separator_len
	vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Title", 0, hunk_status_start, hunk_status_start + #content.hunk_status)
end

-- Create the command footer window
local function create_footer_window(col, total_width, row)
	-- Store total width for dynamic updates
	footer_total_width = total_width

	-- Generate initial footer content
	local content = generate_footer_content(total_width)

	-- Create footer buffer
	footer_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[footer_buf].buftype = "nofile"
	vim.bo[footer_buf].bufhidden = "wipe"
	vim.bo[footer_buf].modifiable = true
	vim.api.nvim_buf_set_lines(footer_buf, 0, -1, false, { content.text })
	vim.bo[footer_buf].modifiable = false

	-- Apply highlighting for keys and descriptions
	local col_offset = content.padding
	for _, cmd in ipairs(content.commands) do
		-- Highlight the key
		vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Special", 0, col_offset, col_offset + #cmd.key)
		col_offset = col_offset + #cmd.key + 1 -- +1 for space after key

		-- Highlight the description
		vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Comment", 0, col_offset, col_offset + #cmd.desc)
		col_offset = col_offset + #cmd.desc + 2 -- +2 for double space separator
	end

	-- Highlight separator (the "│" character)
	local separator_start = content.padding + content.commands_text_len + 2 -- +2 for "  " before separator
	vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Comment", 0, separator_start, separator_start + 3) -- "│" is 3 bytes in UTF-8

	-- Highlight hunk status
	local hunk_status_start = content.padding + content.commands_text_len + content.separator_len
	vim.api.nvim_buf_add_highlight(footer_buf, diffy_namespace, "Title", 0, hunk_status_start, hunk_status_start + #content.hunk_status)

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

-- Open the diff viewer window
function M.open_diff_window(diff_data)
	-- Close any existing diff windows
	M.close_diff_window()

	-- Calculate window dimensions
	local width = math.floor(vim.o.columns * 0.9)
	local total_height = math.floor(vim.o.lines * 0.85)
	local footer_height = 1
	local height = total_height - footer_height - 1 -- -1 for spacing between panels and footer
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - total_height) / 2)

	local content_width = math.floor(width / 2) - 2

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
		border = "rounded",
		title = " Original ",
		title_pos = "center",
	})
	vim.wo[left_win].number = false
	vim.wo[left_win].wrap = false

	-- Create right content window
	right_win = vim.api.nvim_open_win(right_buf, true, {
		relative = "editor",
		width = content_width,
		height = height,
		col = col + content_width + 2,
		row = row,
		style = "minimal",
		border = "rounded",
		title = " Modified ",
		title_pos = "center",
	})
	vim.wo[right_win].number = false
	vim.wo[right_win].wrap = false

	-- Apply highlighting and line numbers
	M.apply_highlighting(left_buf, right_buf, diff_data)
	M.apply_line_numbers(left_buf, right_buf, diff_data)

	-- Calculate hunk positions for navigation
	hunk_starts = calculate_hunk_starts(diff_data)

	-- Set up synchronized scrolling
	M.setup_scroll_sync()

	-- Set up keymaps
	M.setup_keymaps()

	-- Create command footer
	local footer_row = row + height + 2 -- +2 to account for border
	create_footer_window(col, width, footer_row)
end

-- Close the diff viewer
function M.close_diff_window()
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
end

-- Jump to next hunk
function M.jump_to_next_hunk()
	if not hunk_starts or #hunk_starts == 0 then
		return
	end

	local current_idx = find_current_hunk_index()
	local next_idx = (current_idx % #hunk_starts) + 1
	local target_line = hunk_starts[next_idx]

	local current_win = vim.api.nvim_get_current_win()
	if current_win == left_win or current_win == right_win then
		vim.api.nvim_win_set_cursor(current_win, { target_line, 0 })
		update_footer_status()
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
	local target_line = hunk_starts[prev_idx]

	local current_win = vim.api.nvim_get_current_win()
	if current_win == left_win or current_win == right_win then
		vim.api.nvim_win_set_cursor(current_win, { target_line, 0 })
		update_footer_status()
	end
end

-- Apply syntax highlighting to diff content
function M.apply_highlighting(left, right, diff_data)
	-- Apply diff-specific highlighting
	for _, line_num in ipairs(diff_data.left_highlights or {}) do
		vim.api.nvim_buf_add_highlight(left, diffy_namespace, "DiffDelete", line_num - 1, 0, -1)
	end

	for _, line_num in ipairs(diff_data.right_highlights or {}) do
		vim.api.nvim_buf_add_highlight(right, diffy_namespace, "DiffAdd", line_num - 1, 0, -1)
	end
end

-- Apply line numbers as virtual text
function M.apply_line_numbers(left, right, diff_data)
	-- Apply line numbers to left buffer
	for i, info in ipairs(diff_data.left_line_info or {}) do
		local text
		local hl
		if info.type == "context" then
			text = string.format("  %4d │ ", info.num)
			hl = "LineNr"
		elseif info.type == "remove" then
			text = string.format("- %4d │ ", info.num)
			hl = "DiffDelete"
		else
			text = "       │ "
			hl = "LineNr"
		end

		vim.api.nvim_buf_set_extmark(left, diffy_namespace, i - 1, 0, {
			virt_text = { { text, hl } },
			virt_text_pos = "inline",
			priority = 100,
		})
	end

	-- Apply line numbers to right buffer
	for i, info in ipairs(diff_data.right_line_info or {}) do
		local text
		local hl
		if info.type == "context" then
			text = string.format("  %4d │ ", info.num)
			hl = "LineNr"
		elseif info.type == "add" then
			text = string.format("+ %4d │ ", info.num)
			hl = "DiffAdd"
		else
			text = "       │ "
			hl = "LineNr"
		end

		vim.api.nvim_buf_set_extmark(right, diffy_namespace, i - 1, 0, {
			virt_text = { { text, hl } },
			virt_text_pos = "inline",
			priority = 100,
		})
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
		local topline = vim.fn.line("w0", source_win)

		-- Use nvim_win_call to execute in the context of the target window
		vim.api.nvim_win_call(target_win, function()
			pcall(vim.api.nvim_win_set_cursor, target_win, cursor)
			pcall(vim.fn.winrestview, { topline = topline })
		end)
	end

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = left_buf,
		callback = function()
			sync_scroll(left_win, right_win)
			update_footer_status()
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = right_buf,
		callback = function()
			sync_scroll(right_win, left_win)
			update_footer_status()
		end,
	})
end

-- Set up keymaps for closing and navigation
function M.setup_keymaps()
	for _, buf in ipairs({ left_buf, right_buf }) do
		vim.keymap.set("n", "q", M.close_diff_window, { buffer = buf, silent = true })
		vim.keymap.set("n", "<Esc>", M.close_diff_window, { buffer = buf, silent = true })
		vim.keymap.set("n", "<C-c>", M.close_diff_window, { buffer = buf, silent = true })
		vim.keymap.set("n", "n", M.jump_to_next_hunk, { buffer = buf, silent = true })
		vim.keymap.set("n", "p", M.jump_to_prev_hunk, { buffer = buf, silent = true })
	end
end

return M

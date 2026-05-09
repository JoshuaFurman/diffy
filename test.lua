#!/usr/bin/env lua

-- Simple test script for diffy plugin
-- This would be run with: nvim --headless -c "luafile test.lua"

local function test_git_parsing()
	print("Testing git diff parsing...")

	-- Mock diff output
	local mock_diff = [[
diff --git a/test.txt b/test.txt
index 1234567..abcdef0 100644
--- a/test.txt
+++ b/test.txt
@@ -1,3 +1,4 @@
 line 1
-line 2
+modified line 2
 line 3
+new line 4
]]

	local git = require("diffy.git")
	local result = git.parse_and_align_diff(mock_diff)

	assert(result, "Diff parsing failed")
	assert(#result.left_content > 0, "Left content is empty")
	assert(#result.right_content > 0, "Right content is empty")

	-- Verify content alignment (GitHub-style pairing)
	-- Line 1 is context
	assert(result.left_content[1] == "line 1", "Expected line 1 context")
	assert(result.right_content[1] == "line 1", "Expected line 1 context")

	-- Line 2: deletion paired with addition (GitHub-style)
	assert(result.left_content[2] == "line 2", "Expected line 2 removed on left")
	assert(result.right_content[2] == "modified line 2", "Expected modified line 2 on right (paired)")

	-- Line 3 is context
	assert(result.left_content[3] == "line 3", "Expected line 3 context")
	assert(result.right_content[3] == "line 3", "Expected line 3 context")

	-- Line 4: pure addition (empty on left)
	assert(result.left_content[4] == "", "Expected line 4 empty in left")
	assert(result.right_content[4] == "new line 4", "Expected new line 4 added in right")

	-- Verify word_diffs exists for paired modification
	assert(result.word_diffs, "Expected word_diffs table")
	assert(result.word_diffs[2], "Expected word diff for line 2 (paired modification)")

	print("✓ Git parsing test passed")
end

local function test_stage_hunk_patch_selection()
	print("Testing stage hunk patch selection...")

	local mock_diff = [[
diff --git a/test.txt b/test.txt
index 1234567..abcdef0 100644
--- a/test.txt
+++ b/test.txt
@@ -1,3 +1,4 @@
 line 1
-line 2
+modified line 2
 line 3
+new line 4
]]

	local zero_context_diff = [[
diff --git a/test.txt b/test.txt
index 1234567..abcdef0 100644
--- a/test.txt
+++ b/test.txt
@@ -2 +2 @@
-line 2
+modified line 2
@@ -3,0 +4 @@
+new line 4
]]

	local git = require("diffy.git")
	local diff_data = git.parse_and_align_diff(mock_diff)
	local parsed_patch = git.parse_patch_hunks(zero_context_diff)

	local modified_hunk = git.get_display_hunk(diff_data, 2)
	local modified_patch_hunks = git.find_matching_patch_hunks(modified_hunk, parsed_patch)
	assert(#modified_patch_hunks == 1, "Expected to find patch hunk for modified line")

	local modified_patch = git.build_hunk_patch(parsed_patch, modified_patch_hunks)
	assert(modified_patch:find("@@ %-2 %+2 @@", 1), "Expected modified hunk header")
	assert(not modified_patch:find("new line 4", 1, true), "Did not expect addition hunk in patch")

	local added_hunk = git.get_display_hunk(diff_data, 4)
	local added_patch_hunks = git.find_matching_patch_hunks(added_hunk, parsed_patch)
	assert(#added_patch_hunks == 1, "Expected to find patch hunk for added line")
	assert(added_patch_hunks[1].new_start == 4, "Expected added hunk to start at new line 4")

	local partial_display_hunk = {
		old_start = 2,
		old_end = 3,
		new_start = 2,
		new_end = 3,
	}
	local partial_patch = git.parse_patch_hunks([[
diff --git a/test.txt b/test.txt
index 1234567..abcdef0 100644
--- a/test.txt
+++ b/test.txt
@@ -3 +3 @@
-line 3
+modified line 3
]])
	local partial_patch_hunks = git.find_matching_patch_hunks(partial_display_hunk, partial_patch)
	assert(#partial_patch_hunks == 1, "Expected overlap matching for partially staged hunk")

	print("✓ Stage hunk patch selection test passed")
end

local function test_ui_creation()
	print("Testing UI creation...")

	-- This would require a running Neovim instance to test properly
	-- For now, just test that the module loads
	local ui = require("diffy.ui")
	assert(ui, "UI module failed to load")
	assert(type(ui.open_diff_window) == "function", "open_diff_window is not a function")
	assert(type(ui.close_diff_window) == "function", "close_diff_window is not a function")
	assert(type(ui.stage_current_hunk) == "function", "stage_current_hunk is not a function")
	assert(type(ui.toggle_current_hunk_stage) == "function", "toggle_current_hunk_stage is not a function")

	vim.o.columns = 140
	vim.o.lines = 40
	ui.open_diff_window({
		left_content = { "line 1", "old line", "line 3" },
		right_content = { "line 1", "new line", "line 3" },
		left_highlights = { 2 },
		right_highlights = { 2 },
		left_line_info = {
			{ num = 1, type = "context" },
			{ num = 2, type = "remove" },
			{ num = 3, type = "context" },
		},
		right_line_info = {
			{ num = 1, type = "context" },
			{ num = 2, type = "add" },
			{ num = 3, type = "context" },
		},
		word_diffs = {},
	})
	assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "Expected cursor to start at the first hunk")
	ui.close_diff_window()

	print("✓ UI creation test passed")
end

-- Run tests
print("Running diffy plugin tests...")
test_git_parsing()
test_stage_hunk_patch_selection()
test_ui_creation()
print("All tests passed! ✓")

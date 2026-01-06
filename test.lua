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

	-- Verify content alignment
	-- Line 1 is context
	assert(result.left_content[1] == "line 1", "Expected line 1 context")
	assert(result.right_content[1] == "line 1", "Expected line 1 context")

	-- Line 2 changed
	assert(result.left_content[2] == "line 2", "Expected line 2 removed")
	assert(result.right_content[2] == "", "Expected line 2 empty in right")

	assert(result.left_content[3] == "", "Expected line 3 empty in left")
	assert(result.right_content[3] == "modified line 2", "Expected line 3 added in right")

	print("✓ Git parsing test passed")
end

local function test_ui_creation()
	print("Testing UI creation...")

	-- This would require a running Neovim instance to test properly
	-- For now, just test that the module loads
	local ui = require("diffy.ui")
	assert(ui, "UI module failed to load")
	assert(type(ui.open_diff_window) == "function", "open_diff_window is not a function")
	assert(type(ui.close_diff_window) == "function", "close_diff_window is not a function")

	print("✓ UI creation test passed")
end

-- Run tests
print("Running diffy plugin tests...")
test_git_parsing()
test_ui_creation()
print("All tests passed! ✓")

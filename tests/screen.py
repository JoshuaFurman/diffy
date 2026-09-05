"""Check actual UI cell colors, not just extmark definitions.

Run: uv run --no-project --with pynvim python tests/screen.py
pynvim is a test-only dependency; the plugin itself remains pure Lua.
"""

from pathlib import Path

import pynvim


nvim = pynvim.attach("child", argv=["nvim", "--clean", "--embed", "--headless"])
cells = {}
attributes = {}
samples = []


def notification(name, args):
    if name == "diffy_test_done":
        nvim.stop_loop()
        return
    if name != "redraw":
        return
    for event, *updates in args:
        for update in updates:
            if event == "hl_attr_define":
                attributes[update[0]] = update[1]
            elif event == "grid_line":
                grid, row, col, chunks = update[:4]
                highlight = 0
                for chunk in chunks:
                    text = chunk[0]
                    if len(chunk) > 1:
                        highlight = chunk[1]
                    repeat = chunk[2] if len(chunk) > 2 else 1
                    for _ in range(repeat):
                        cells[grid, row, col] = (text, highlight)
                        col += 1


def setup():
    nvim.ui_attach(140, 40, rgb=True, ext_linegrid=True)
    samples.extend(nvim.exec_lua(r'''
      local root = ...
      vim.opt.rtp:prepend(root)
      local git = require('diffy.git')
      local prefix = 'prefix ' .. string.rep('x', 100)
      local data = git.parse_and_align_diff(table.concat({
        '@@ -1,7 +1,7 @@', ' context',
        '-a=1; b=2', '+a=3; b=4',
        '-a b', '+a   b',
        '-end   ', '+end',
        '-' .. prefix .. '1 tail', '+' .. prefix .. '2 tail',
        '-', '+', ' context',
      }, '\n'))
      require('diffy.ui').open_diff_window(data)
      local panes = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local title = vim.api.nvim_win_get_config(win).title
        if title then
          panes[title[1][1]] = win
        end
      end
      local left, right = panes[' Original '], panes[' Modified ']
      local ns = vim.api.nvim_create_namespace('diffy_test_syntax')
      vim.api.nvim_set_hl(0, 'DiffyTestSyntax', { fg = '#abcdef' })
      for _, win in ipairs({ left, right }) do
        vim.api.nvim_buf_add_highlight(vim.api.nvim_win_get_buf(win), ns,
          'DiffyTestSyntax', 1, 0, -1)
      end
      vim.cmd('redraw!')
      local result = {}
      local function sample(win, row, col, group, text, bold, syntax, eol)
        local pos = vim.fn.screenpos(win, row, col)
        if eol then
          pos.col = vim.api.nvim_win_get_position(win)[2] + vim.api.nvim_win_get_width(win)
        end
        result[#result + 1] = {
          row = pos.row - 1, col = pos.col - 1, text = text,
          bg = vim.api.nvim_get_hl(0, { name = group }).bg,
          bold = bold, fg = syntax and 0xabcdef or nil,
        }
      end
      for _, side in ipairs({ { left, 'DiffyDelete', '1' }, { right, 'DiffyAdd', '3' } }) do
        local win, group = side[1], side[2]
        sample(win, 2, 1, group, 'a', false, true)
        sample(win, 2, 3, group .. 'Text', side[3], true, true)
        sample(win, 2, 4, group, ';', false, true)
        sample(win, 2, 1, group, ' ', false, false, true)
        sample(win, 6, 1, group, ' ', false)
        sample(win, 5, #prefix + 3, group, 't', false)
        sample(win, 5, #prefix + 1, group, ' ', false, false, true)
      end
      sample(right, 3, 3, 'DiffyAddText', ' ', true)
      sample(left, 4, 5, 'DiffyDeleteText', ' ', true)
      sample(left, 5, #prefix + 1, 'DiffyDeleteText', '1', true)
      sample(right, 5, #prefix + 1, 'DiffyAddText', '2', true)
      return result
    ''', str(Path(__file__).resolve().parents[1])))
    # Redraw notifications precede this sentinel on the same RPC channel.
    nvim.exec_lua("vim.rpcnotify(..., 'diffy_test_done')", nvim.channel_id)


try:
    nvim.run_loop(None, notification, setup_cb=setup)
    assert samples, "No rendered samples collected"
    for sample in samples:
        text, highlight = cells[1, sample["row"], sample["col"]]
        actual = attributes[highlight]
        assert text == sample["text"], (sample, text)
        assert actual.get("background") == sample["bg"], (sample, actual)
        assert actual.get("bold", False) == sample["bold"], (sample, actual)
        if "fg" in sample:
            assert actual.get("foreground") == sample["fg"], (sample, actual)
    print("✓ Rendered character, whitespace, wrapped-line, and syntax colors passed")
finally:
    try:
        nvim.command("qa!")
    except EOFError:
        pass
    nvim.close()

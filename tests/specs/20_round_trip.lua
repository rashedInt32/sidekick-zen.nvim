-- Entering and leaving zen is a round trip. Mutation testing showed the suite
-- could not see the terminal's own options being left mutated, nor the cursor
-- being dropped on the way in or out, so each of those is asserted here.
local H = _G.H
H.reset()
local Z = H.zen()

local entry = H.layout()
local t = H.term()

-- ---------- the terminal's own opts round trip ----------
local opts_before = { layout = t.opts.layout, float = vim.deepcopy(t.opts.float) }
Z.toggle()
vim.wait(500)
H.check("layout mutated while zen is open", t.opts.layout == "float", tostring(t.opts.layout))
Z.toggle()
vim.wait(600)
H.check(
  "terminal layout restored",
  t.opts.layout == opts_before.layout,
  tostring(t.opts.layout) .. " want " .. tostring(opts_before.layout)
)
H.check(
  "terminal float opts restored",
  vim.deep_equal(t.opts.float, opts_before.float),
  "now=" .. vim.inspect(t.opts.float) .. " want=" .. vim.inspect(opts_before.float)
)

-- ---------- the cursor round trips into the code view ----------
vim.api.nvim_set_current_win(entry)
vim.cmd("edit " .. H.dir .. "/alpha.txt")
vim.api.nvim_win_set_cursor(entry, { 200, 0 })
-- zt, not zz: the buffer's own last-position mark only records the cursor, so
-- nvim would re-derive a centred view on its own. Pinning the cursor to the
-- top row makes the assertion prove the VIEW was carried, not just the line.
vim.cmd("normal! zt")
local want_line = vim.api.nvim_win_get_cursor(entry)[1]
local want_top = vim.fn.getwininfo(entry)[1].topline

Z.toggle()
vim.wait(500)
local cw = H.code_win()
H.check("code view opened on the same buffer", H.buf_name(cw) == "alpha.txt", H.buf_name(cw))
H.check(
  "cursor carried into the code view",
  vim.api.nvim_win_get_cursor(cw)[1] == want_line,
  vim.api.nvim_win_get_cursor(cw)[1] .. " want " .. want_line
)
H.check(
  "scroll position carried into the code view",
  vim.fn.getwininfo(cw)[1].topline == want_top,
  vim.fn.getwininfo(cw)[1].topline .. " want " .. want_top
)

-- ---------- and back out again ----------
vim.api.nvim_win_set_cursor(cw, { 120, 0 })
vim.cmd("normal! zt")
local moved_line = vim.api.nvim_win_get_cursor(cw)[1]
local moved_top = vim.fn.getwininfo(cw)[1].topline
Z.toggle()
vim.wait(600)
H.check(
  "cursor carried back to the window you came from",
  vim.api.nvim_win_get_cursor(entry)[1] == moved_line,
  vim.api.nvim_win_get_cursor(entry)[1] .. " want " .. moved_line
)
H.check(
  "scroll position carried back",
  vim.fn.getwininfo(entry)[1].topline == moved_top,
  vim.fn.getwininfo(entry)[1].topline .. " want " .. moved_top
)
H.no_workspace_left()

return H.report()

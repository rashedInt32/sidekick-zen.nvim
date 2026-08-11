-- Regressions around the window zen invents when nothing is usable as an
-- origin: a modified buffer used to survive exit unlisted and modified, which
-- blocked :qall with no visible culprit, and an external close left the whole
-- window behind.
local H = _G.H
H.reset()
local Z = H.zen()

local function lone_cli()
  H.layout()
  vim.api.nvim_set_current_win(H.term_win())
  vim.cmd("only")
  vim.wait(300)
end

-- untouched placeholder: dropped on exit
lone_cli()
Z.toggle()
vim.wait(500)
local cw = H.code_win()
local ph = vim.api.nvim_win_get_buf(cw)
Z.toggle()
vim.wait(600)
H.check(
  "untouched placeholder buffer is gone",
  not vim.api.nvim_buf_is_valid(ph) or vim.fn.bufloaded(ph) == 0,
  "buf=" .. ph
)
local hidden_modified = false
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[b].modified and vim.fn.bufwinid(b) == -1 then
    hidden_modified = true
  end
end
H.check("no hidden modified buffer left behind", not hidden_modified)

-- placeholder typed into: kept, and visible so it can be dealt with
lone_cli()
Z.toggle()
vim.wait(500)
cw = H.code_win()
ph = vim.api.nvim_win_get_buf(cw)
vim.api.nvim_buf_set_lines(ph, 0, -1, false, { "typed in the zen canvas" })
Z.toggle()
vim.wait(600)
H.check(
  "typed-in content was not discarded",
  vim.api.nvim_buf_is_valid(ph) and vim.bo[ph].modified,
  "valid=" .. tostring(vim.api.nvim_buf_is_valid(ph))
)
H.check("and it is visible in a window", vim.fn.bufwinid(ph) ~= -1, "winid=" .. vim.fn.bufwinid(ph))
vim.bo[ph].modified = false

-- external close of the code float must not strand the invented window
lone_cli()
Z.toggle()
vim.wait(500)
local before = #vim.api.nvim_list_wins()
vim.api.nvim_win_close(H.code_win(), true)
vim.wait(900)
H.no_workspace_left()
local leftover = 0
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local b = vim.api.nvim_win_get_buf(w)
  if vim.api.nvim_buf_get_name(b) == "" and vim.bo[b].buftype == "" then
    leftover = leftover + 1
  end
end
H.check(
  "invented window not stranded after an external close",
  leftover == 0,
  "leftover=" .. leftover .. " before=" .. before
)

return H.report()

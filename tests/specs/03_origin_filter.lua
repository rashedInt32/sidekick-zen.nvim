-- Regression: origin resolution accepted any non-floating window, so entering
-- from the CLI could adopt a sidebar and write the zen buffer into it on exit.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
vim.cmd("topleft vsplit")
local side = vim.api.nvim_get_current_win()
local sbuf = vim.api.nvim_create_buf(false, true)
vim.bo[sbuf].buftype = "nofile"
vim.api.nvim_win_set_buf(side, sbuf)
vim.api.nvim_win_set_width(side, 30)

-- make the sidebar the alternate window, then enter zen from the CLI
vim.api.nvim_set_current_win(side)
vim.api.nvim_set_current_win(H.term_win())
vim.wait(150)

Z.toggle()
vim.wait(500)
local cw = H.code_win()
local shown = cw and vim.api.nvim_win_get_buf(cw)
H.check("sidebar buffer not adopted", shown ~= sbuf, "shown=" .. tostring(shown) .. " sidebar=" .. sbuf)
H.check(
  "code float shows a real file",
  shown and vim.bo[shown].buftype == "",
  "buftype=" .. tostring(shown and vim.bo[shown].buftype)
)

Z.toggle()
vim.wait(500)
H.check(
  "sidebar untouched after exit",
  vim.api.nvim_win_is_valid(side) and vim.api.nvim_win_get_buf(side) == sbuf,
  "now=" .. tostring(vim.api.nvim_win_is_valid(side) and vim.api.nvim_win_get_buf(side))
)
pcall(vim.api.nvim_win_close, side, true)

return H.report()

-- Regression: entering zen from a lone CLI window used to clone the terminal
-- buffer into the code float and strand the old split, so the PTY ended up
-- sized to the smallest of three windows.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
vim.api.nvim_set_current_win(H.term_win())
vim.cmd("only")
vim.wait(300)
H.check("precondition: cli is the only window", #vim.api.nvim_list_wins() == 1, "n=" .. #vim.api.nvim_list_wins())

Z.toggle()
vim.wait(500)
H.check("terminal in exactly one window", #H.term_wins() == 1, vim.inspect(H.term_wins()))
local cw = H.code_win()
H.check("code float exists", cw ~= nil)
H.check(
  "code float is not the terminal buffer",
  cw and vim.bo[vim.api.nvim_win_get_buf(cw)].buftype ~= "terminal",
  cw and vim.bo[vim.api.nvim_win_get_buf(cw)].buftype or "nil"
)
H.check("entered on the cli view", H.cur() == H.term_win())

Z.toggle()
vim.wait(500)
H.check("terminal in one window after exit", #H.term_wins() == 1, vim.inspect(H.term_wins()))
H.check(
  "terminal width restored",
  H.term_win() and vim.api.nvim_win_get_width(H.term_win()) > 20,
  "w=" .. tostring(H.term_win() and vim.api.nvim_win_get_width(H.term_win()))
)
H.no_workspace_left()

return H.report()

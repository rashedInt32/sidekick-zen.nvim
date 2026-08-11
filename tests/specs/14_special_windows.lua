-- Regression: the focused window skipped the sidebar filter, on the theory
-- that the user had chosen it deliberately. Exit then wrote the code view's
-- buffer into it, which destroyed quickfix, oil and explorer windows.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
vim.fn.setqflist({ { filename = H.dir .. "/alpha.txt", lnum = 1, text = "entry" } })
vim.cmd("copen")
vim.wait(200)
local qf = vim.api.nvim_get_current_win()
H.check("precondition: focused on quickfix", vim.bo[vim.api.nvim_win_get_buf(qf)].buftype == "quickfix")

Z.toggle()
vim.wait(500)
local cw = H.code_win()
H.check("workspace opened from quickfix", cw ~= nil)
H.check(
  "code float did not clone the quickfix buffer",
  cw and vim.bo[vim.api.nvim_win_get_buf(cw)].buftype ~= "quickfix",
  cw and vim.bo[vim.api.nvim_win_get_buf(cw)].buftype or "nil"
)

vim.api.nvim_set_current_win(cw)
vim.cmd("edit " .. H.dir .. "/beta.txt")
vim.wait(400)
Z.toggle()
vim.wait(500)

local still_qf = false
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "quickfix" then
    still_qf = true
  end
end
H.check("quickfix window survived", still_qf)
H.no_workspace_left()

vim.cmd("silent! cclose")
return H.report()

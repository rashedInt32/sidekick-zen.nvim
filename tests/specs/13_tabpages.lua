-- Regression: the cleanup loop used win_findbuf, which spans every tabpage,
-- so entering zen could close the sole window of another tabpage and destroy
-- it. And the switch keys were global, so they drove an invisible workspace
-- from other tabs.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
local term_buf = H.term().buf

-- a second tabpage that happens to show the CLI buffer
vim.cmd("tabnew")
vim.api.nvim_win_set_buf(0, term_buf)
vim.cmd("tabprevious")
vim.wait(200)
H.check("precondition: two tabpages", #vim.api.nvim_list_tabpages() == 2, "n=" .. #vim.api.nvim_list_tabpages())

Z.toggle()
vim.wait(500)
H.check(
  "other tabpage survived entering zen",
  #vim.api.nvim_list_tabpages() == 2,
  "n=" .. #vim.api.nvim_list_tabpages()
)
H.check("workspace opened", H.code_win() ~= nil)

-- leaving the tabpage closes the workspace rather than leaving global keys
-- driving something invisible
vim.cmd("tabnext")
vim.wait(600)
H.check("zen exited on tab leave", H.zen_floats() == nil or #H.zen_floats() == 0, vim.inspect(H.zen_floats()))
H.check(
  "switch keys restored in the other tab",
  (vim.fn.maparg(Z.config.keys.code, "n", false, true).desc or "") ~= "Zen: code view"
)
H.check(
  "exit key restored in the other tab",
  (vim.fn.maparg(Z.config.keys.exit, "n", false, true).desc or "") ~= "Zen: exit"
)

vim.cmd("tabonly")
vim.wait(200)
H.check("workspace autocmds cleared", H.ws_autocmds() == 0, "n=" .. H.ws_autocmds())

return H.report()

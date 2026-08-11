-- Regression: :q inside a view configured an already-closed window from the
-- focus watcher. Any external close must tear the workspace down cleanly.
local H = _G.H
H.reset()
local Z = H.zen()

-- :q with the cli float as the previously focused window
H.layout()
Z.toggle()
vim.wait(400)
H.key(Z.config.keys.cli)()
vim.wait(400)
H.key(Z.config.keys.code)()
vim.wait(400)

local ok, err = pcall(vim.cmd, "quit")
vim.wait(900)
H.check(":q did not raise", ok, tostring(err))
H.no_workspace_left()
H.check(
  "global switch key restored",
  (vim.fn.maparg(Z.config.keys.code, "n", false, true).desc or "") ~= "Zen: code view"
)

-- the CLI process dying while zen is open
H.layout()
Z.toggle()
vim.wait(400)
H.check("zen open again", H.code_win() ~= nil)
H.term():close()
vim.wait(900)
H.no_workspace_left()
H.check("a normal window is focused", vim.api.nvim_win_get_config(0).relative == "")

return H.report()

-- Two regressions. A queued WinClosed teardown only checked that some
-- workspace existed, so it could tear down a workspace opened after the one
-- it watched. And the backdrop highlight was computed once and never again,
-- because its guard read a `default` field nvim does not return.
local H = _G.H
H.reset()
local Z = H.zen()

-- re-entry inside one tick
H.layout()
Z.toggle()
vim.wait(400)
vim.api.nvim_win_close(H.code_win(), true) -- queues a teardown for THIS workspace
Z.toggle() -- exits it
Z.toggle() -- opens a fresh one
vim.wait(900) -- let the queued callback fire
H.check("fresh workspace survived the queued teardown", H.code_win() ~= nil, vim.inspect(H.zen_floats()))
H.check("backdrop still present", H.backdrop() ~= nil)
Z.toggle()
vim.wait(500)
H.no_workspace_left()

-- backdrop recomputed when the colours change
vim.api.nvim_set_hl(0, "SidekickChat", { bg = "#112233" })
H.layout()
Z.toggle()
vim.wait(400)
local first = vim.api.nvim_get_hl(0, { name = "SidekickZenBg" }).bg
H.check("backdrop follows the cli background", first == tonumber("112233", 16), "got=" .. tostring(first))
Z.toggle()
vim.wait(400)

vim.api.nvim_set_hl(0, "SidekickChat", { bg = "#445566" })
Z.toggle()
vim.wait(400)
local second = vim.api.nvim_get_hl(0, { name = "SidekickZenBg" }).bg
H.check("backdrop recomputed after the colours changed", second == tonumber("445566", 16), "got=" .. tostring(second))
Z.toggle()
vim.wait(400)

-- explicit override wins
Z.setup({ backdrop_bg = "#0d1522" })
Z.toggle()
vim.wait(400)
local third = vim.api.nvim_get_hl(0, { name = "SidekickZenBg" }).bg
H.check("backdrop_bg override respected", third == tonumber("0d1522", 16), "got=" .. tostring(third))
Z.toggle()
vim.wait(400)
Z.config.backdrop_bg = nil
H.no_workspace_left()

return H.report()

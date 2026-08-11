-- Regression: the focus watcher knew only about the two zen floats, so any
-- other window command walked the cursor into a window under the backdrop.
-- The switch keys could not rescue it either, because switch() returned early
-- when the requested view was already the active one.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
Z.toggle()
vim.wait(400)
local cw = H.code_win()
H.check("started on the code view", H.cur() == cw)

-- walk into the hidden origin split
vim.cmd("wincmd w")
vim.wait(400)
H.check(
  "focus bounced out of the hidden window",
  vim.api.nvim_win_get_config(0).relative ~= "",
  "cur=" .. tostring(H.cur()) .. " relative=" .. tostring(vim.api.nvim_win_get_config(0).relative)
)
H.check("bounced onto the active view", H.cur() == cw, "cur=" .. tostring(H.cur()))

-- and the switch key re-asserts focus rather than no-opping
vim.cmd("wincmd p")
vim.wait(200)
H.key(Z.config.keys.code)()
vim.wait(300)
H.check("switch key recovers focus onto the code view", H.cur() == cw, "cur=" .. tostring(H.cur()))

-- The invariant that matters: after any window walk the cursor sits on a
-- raised view, never on something buried under the backdrop. Landing on the
-- other float is fine, since following that focus raises it.
H.key(Z.config.keys.cli)()
vim.wait(400)
H.check("on the cli view", H.cur() == H.term_win())
for i = 1, 4 do
  vim.cmd("wincmd w")
  vim.wait(300)
  H.check(
    "cursor on a raised view after walk " .. i,
    H.zindex(H.cur()) == 50,
    "cur=" .. tostring(H.cur()) .. " z=" .. tostring(H.zindex(H.cur()))
  )
end

Z.toggle()
vim.wait(500)
H.no_workspace_left()

return H.report()

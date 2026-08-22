-- The User events fire exactly once per enter and once per exit, carry the
-- windows a handler needs, and a handler that throws cannot leave a half-built
-- workspace behind or skip teardown.
local H = _G.H
H.reset()
local Z = H.zen()

local seen = {}
local group = vim.api.nvim_create_augroup("zen_event_spec", { clear = true })
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = { "SidekickZenOpen", "SidekickZenClose" },
  callback = function(ev)
    -- Recorded at fire time: the events promise a settled state, so open must
    -- already see the floats and close must already see them gone.
    table.insert(seen, { match = ev.match, data = ev.data or {}, floats = #H.zen_floats() })
  end,
})

H.layout()
Z.toggle()
vim.wait(600)
H.check("open fired once", #seen == 1, "n=" .. #seen)
local open = seen[1] or { data = {} }
H.check("open is named SidekickZenOpen", open.match == "SidekickZenOpen", tostring(open.match))
H.check("open reports the code view", open.data.view == "code", tostring(open.data.view))
H.check("open reports the tabpage", open.data.tab == vim.api.nvim_get_current_tabpage(), tostring(open.data.tab))
H.check("open saw the workspace already built", open.floats == 3, tostring(open.floats))
-- The whole point of the payload: a handler must be able to touch the floats
-- without going through plugin internals.
H.check(
  "open hands over the code window",
  open.data.code_win == H.code_win(),
  tostring(open.data.code_win) .. " vs " .. tostring(H.code_win())
)
H.check(
  "open hands over the cli window",
  open.data.cli_win == H.term_win(),
  tostring(open.data.cli_win) .. " vs " .. tostring(H.term_win())
)

-- Close fires after the floats are gone, so a handler restoring options sees
-- the layout it is restoring for.
Z.toggle()
vim.wait(600)
H.check("close fired once", #seen == 2, "n=" .. #seen)
H.check("close is named SidekickZenClose", seen[2] and seen[2].match == "SidekickZenClose", tostring(seen[2]))
H.check("close reports the tabpage", seen[2] and seen[2].data.tab ~= nil)
H.check("close saw the floats already gone", seen[2] and seen[2].floats == 0, tostring(seen[2] and seen[2].floats))
H.no_workspace_left()

-- An inert toggle-out announces nothing: every close must pair with an open.
Z.exit()
vim.wait(300)
H.check("exiting with no workspace fires nothing", #seen == 2, "n=" .. #seen)

-- Switching views is not a lifecycle change, so it must stay silent.
Z.toggle()
vim.wait(600)
pcall(H.key(Z.config.keys.cli))
vim.wait(500)
pcall(H.key(Z.config.keys.code))
vim.wait(500)
H.check("view switches fire nothing", #seen == 3, "n=" .. #seen)
Z.toggle()
vim.wait(600)
H.check("that pair closed cleanly", #seen == 4, "n=" .. #seen)

-- A handler is user code. An error in one is the user's problem, not zen's:
-- the workspace must still build, and must still tear down completely.
vim.api.nvim_clear_autocmds({ group = group })
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = { "SidekickZenOpen", "SidekickZenClose" },
  callback = function()
    error("handler blew up")
  end,
})

local ok_enter = pcall(Z.toggle)
vim.wait(600)
H.check("enter survives a throwing handler", ok_enter and H.code_win() ~= nil, tostring(ok_enter))
local ok_exit = pcall(Z.toggle)
vim.wait(600)
H.check("exit survives a throwing handler", ok_exit, tostring(ok_exit))
H.no_workspace_left()

vim.api.nvim_del_augroup_by_id(group)
H.close_cli()

return H.report()

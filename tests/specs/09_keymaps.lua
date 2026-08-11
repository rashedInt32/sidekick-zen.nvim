-- Zen's overrides must exist only while the workspace is open, and must
-- restore exactly what they shadowed, globals and sidekick's buffer-local
-- terminal maps alike.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
vim.keymap.set("n", Z.config.keys.code, "<C-w>h", { desc = "user left" })
vim.keymap.set("n", Z.config.keys.cli, "<C-w>l", { desc = "user right" })

local before = {}
for _, k in ipairs({ Z.config.keys.code, Z.config.keys.cli, Z.config.keys.exit }) do
  before[k] = vim.fn.maparg(k, "n", false, true)
end
local tbuf = H.term().buf
local tbefore = vim.api.nvim_buf_call(tbuf, function()
  return {
    q = vim.fn.maparg("q", "n", false, true),
    nav = vim.fn.maparg(Z.config.keys.code, "t", false, true),
  }
end)

Z.toggle()
vim.wait(400)
H.check("zen switch key installed", vim.fn.maparg(Z.config.keys.code, "n", false, true).desc == "Zen: code view")
H.check("zen exit key installed", vim.fn.maparg(Z.config.keys.exit, "n", false, true).desc == "Zen: exit")
local tin = vim.api.nvim_buf_call(tbuf, function()
  return {
    q = vim.fn.maparg("q", "n", false, true),
    nav = vim.fn.maparg(Z.config.keys.code, "t", false, true),
  }
end)
H.check("terminal q hijacked", tin.q.desc == "Zen: exit", tostring(tin.q.desc))
H.check("terminal nav key hijacked", tin.nav.desc == "Zen: code view", tostring(tin.nav.desc))

-- exit from the CLI view through the hijacked q
H.key(Z.config.keys.cli)()
vim.wait(400)
vim.api.nvim_buf_call(tbuf, function()
  vim.fn.maparg("q", "n", false, true).callback()
end)
vim.wait(600)
H.no_workspace_left()

for _, k in ipairs({ Z.config.keys.code, Z.config.keys.cli, Z.config.keys.exit }) do
  local now = vim.fn.maparg(k, "n", false, true)
  H.check(
    "global " .. k .. " restored",
    (now.rhs or now.desc or "") == (before[k].rhs or before[k].desc or ""),
    "was=" .. tostring(before[k].rhs or before[k].desc) .. " now=" .. tostring(now.rhs or now.desc)
  )
end
local tafter = vim.api.nvim_buf_call(tbuf, function()
  return {
    q = vim.fn.maparg("q", "n", false, true),
    nav = vim.fn.maparg(Z.config.keys.code, "t", false, true),
  }
end)
H.check(
  "terminal q restored to sidekick's",
  (tafter.q.desc or "") == (tbefore.q.desc or ""),
  "was=" .. tostring(tbefore.q.desc) .. " now=" .. tostring(tafter.q.desc)
)
H.check(
  "terminal nav restored to sidekick's",
  (tafter.nav.desc or "") == (tbefore.nav.desc or ""),
  "was=" .. tostring(tbefore.nav.desc) .. " now=" .. tostring(tafter.nav.desc)
)

pcall(vim.keymap.del, "n", Z.config.keys.code)
pcall(vim.keymap.del, "n", Z.config.keys.cli)
return H.report()

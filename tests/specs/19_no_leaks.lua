-- Nothing zen creates may outlive it. The suite previously counted only
-- floats and autocmds, so a mutation that leaked a buffer on every toggle
-- passed cleanly.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
vim.wait(300)
local base = H.counts()

for i = 1, 5 do
  Z.toggle()
  vim.wait(350)
  Z.toggle()
  vim.wait(450)
end

local after = H.counts()
H.check("no windows leaked over five cycles", after.wins == base.wins, after.wins .. " want " .. base.wins)
H.check("no buffers leaked over five cycles", after.bufs == base.bufs, after.bufs .. " want " .. base.bufs)
H.check("no autocmds leaked", after.autocmds == 0, "n=" .. after.autocmds)
H.check("no keymaps leaked", after.maps == base.maps, after.maps .. " want " .. base.maps)

-- the same, but exiting through the CLI view each time
for i = 1, 3 do
  Z.toggle()
  vim.wait(350)
  H.key(Z.config.keys.cli)()
  vim.wait(350)
  Z.toggle()
  vim.wait(450)
end
local after2 = H.counts()
H.check("no windows leaked exiting from the cli view", after2.wins == base.wins, after2.wins .. " want " .. base.wins)
H.check("no buffers leaked exiting from the cli view", after2.bufs == base.bufs, after2.bufs .. " want " .. base.bufs)
H.check("no keymaps leaked exiting from the cli view", after2.maps == base.maps, after2.maps .. " want " .. base.maps)

-- and the terminal itself must be the same session throughout, never respawned
local t = H.term()
H.check("cli session survived all cycles", t ~= nil and t:is_running())
H.check("terminal in exactly one window", #H.term_wins() == 1, vim.inspect(H.term_wins()))
H.no_workspace_left()

return H.report()

-- Regression: switching to a dead CLI raised E5108 after the zindex swap had
-- already happened, leaving the cursor in a window below the backdrop.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
Z.toggle()
vim.wait(400)
local cw = H.code_win()
H.check("started on the code view", H.cur() == cw)

vim.fn.jobstop(H.term().job)
vim.wait(900)
H.check("cli process is dead", not H.term():is_running())

local ok, err = pcall(H.key(Z.config.keys.cli))
vim.wait(300)
H.check("switching to a dead cli does not error", ok, tostring(err))
H.check("code view stayed raised", H.zindex(cw) == H.Z.top, "z=" .. tostring(H.zindex(cw)))
H.check("cursor stayed on the code view", H.cur() == cw, "cur=" .. tostring(H.cur()))

Z.toggle()
vim.wait(500)
H.no_workspace_left()

return H.report()

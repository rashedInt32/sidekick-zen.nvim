-- With no CLI session the workspace still opens, and asking for the CLI view
-- warns instead of erroring.
local H = _G.H
H.reset()
local Z = H.zen()

H.close_cli()
vim.cmd("silent! only")
vim.cmd("silent! edit! " .. H.dir .. "/alpha.txt")
vim.bo.modified = false
local origin = vim.api.nvim_get_current_win()

Z.toggle()
vim.wait(400)
H.check("code-only workspace entered", H.code_win() ~= nil)
H.check("backdrop present", H.backdrop() ~= nil)
H.check("no cli float", H.term_win() == nil)

local ok, err = pcall(H.key(Z.config.keys.cli))
vim.wait(300)
H.check("asking for the cli warns instead of erroring", ok, tostring(err))
H.check("still on the code view", H.code_win() ~= nil and H.zindex(H.code_win()) == 50)

Z.toggle()
vim.wait(500)
H.no_workspace_left()
H.check("origin refocused", H.cur() == origin)
H.check("buffer preserved", H.buf_name() == "alpha.txt", H.buf_name())

-- and toggling twice in a row must be inert
Z.toggle()
vim.wait(300)
Z.toggle()
vim.wait(400)
H.no_workspace_left()

return H.report()

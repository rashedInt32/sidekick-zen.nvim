-- Regression: sidekick's blur moved the cursor into the hidden code float
-- while the CLI stayed on screen, so keystrokes edited an invisible buffer.
-- The visible view must always match where the cursor is.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
Z.toggle()
vim.wait(400)
H.key(Z.config.keys.cli)()
vim.wait(400)
H.check("on the cli view", H.cur() == H.term_win())

require("sidekick.cli").focus() -- focused, so this blurs
vim.wait(500)
local cw = H.code_win()
H.check("blur landed on the code float", H.cur() == cw, "cur=" .. tostring(H.cur()))
H.check("code view raised by blur", H.zindex(cw) == 50, "z=" .. tostring(H.zindex(cw)))
H.check("cli lowered by blur", H.zindex(H.term_win()) == 30, "z=" .. tostring(H.zindex(H.term_win())))

require("sidekick.cli").focus() -- not focused, so this focuses
vim.wait(500)
H.check("cli raised by focus", H.zindex(H.term_win()) == 50)
H.check("cursor on the cli", H.cur() == H.term_win())

-- sending context must bring the CLI forward too
H.key(Z.config.keys.code)()
vim.wait(400)
H.check("back on the code view", H.zindex(cw) == 50)
require("sidekick.cli").send({ msg = "{file}" })
vim.wait(1200)
H.check("send raised the cli view", H.zindex(H.term_win()) == 50, "z=" .. tostring(H.zindex(H.term_win())))
H.check("send lowered the code view", H.zindex(cw) == 30, "z=" .. tostring(H.zindex(cw)))
H.check("cursor followed into the cli", H.cur() == H.term_win())

Z.toggle()
vim.wait(500)
H.no_workspace_left()

return H.report()

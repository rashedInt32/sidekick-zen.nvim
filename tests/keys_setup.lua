-- Not a spec. Puts the editor in the standard layout with zen open on the
-- code view, so run.sh can drive it with real keystrokes.
local H = _G.H
H.layout()
H.zen().toggle()
vim.wait(400)
return "ready"

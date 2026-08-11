-- The code view stays live: files open into it, restored cursors get centered
-- rather than stranded at the bottom, and buffers opened in the hidden origin
-- window get adopted. On exit the origin inherits whatever was reached.
local H = _G.H
H.reset()
local Z = H.zen()

local origin = H.layout()
Z.toggle()
vim.wait(400)
local cw = H.code_win()

-- give beta.txt a remembered position near its end
vim.api.nvim_set_current_win(cw)
vim.cmd("edit " .. H.dir .. "/beta.txt")
vim.wait(250)
vim.api.nvim_win_set_cursor(cw, { 250, 0 })
vim.cmd("edit " .. H.dir .. "/alpha.txt")
vim.wait(250)
vim.cmd("edit " .. H.dir .. "/beta.txt")
vim.wait(700)

H.check("file opened in the code float", H.buf_name(cw) == "beta.txt", H.buf_name(cw))
H.check("no extra window opened", #H.zen_floats() == 3, "floats=" .. #H.zen_floats())
local top = vim.fn.getwininfo(cw)[1].topline
local line = vim.api.nvim_win_get_cursor(cw)[1]
local height = vim.api.nvim_win_get_height(cw)
H.check(
  "restored cursor centered, not at the bottom",
  math.abs((line - top) - math.floor(height / 2)) <= 3,
  "line=" .. line .. " top=" .. top .. " height=" .. height
)

-- a buffer opened in the hidden origin window must be adopted into the float
vim.api.nvim_set_current_win(origin)
vim.cmd("edit " .. H.dir .. "/alpha.txt")
vim.wait(700)
H.check(
  "origin-opened buffer adopted by the code float",
  H.buf_name(H.code_win()) == "alpha.txt",
  H.buf_name(H.code_win())
)
H.check("focus pulled back above the backdrop", H.cur() == H.code_win(), "cur=" .. tostring(H.cur()))
H.check("code view raised after adoption", H.zindex(H.code_win()) == 50)

Z.toggle()
vim.wait(600)
H.check("origin inherited the buffer", H.buf_name(origin) == "alpha.txt", H.buf_name(origin))
H.check("origin refocused", H.cur() == origin)
H.no_workspace_left()

return H.report()

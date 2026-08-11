-- The happy path: enter from code, swap both ways, exit back to the split.
local H = _G.H
H.reset()
local Z = H.zen()

local code = H.layout()
local t = H.term()
H.check("cli session running", t ~= nil and t:is_running())
local split_width = vim.api.nvim_win_get_width(t.win)

Z.toggle()
vim.wait(400)
local cw = H.code_win()
H.check("entered on the code view", H.cur() == cw, "cur=" .. tostring(H.cur()))
H.check("code float raised", H.zindex(cw) == 50, "z=" .. tostring(H.zindex(cw)))
H.check("cli float hidden", H.zindex(H.term_win()) == 30, "z=" .. tostring(H.zindex(H.term_win())))
H.check("backdrop present", H.backdrop() ~= nil)
H.check("terminal in exactly one window", #H.term_wins() == 1, vim.inspect(H.term_wins()))
local zen_w = vim.api.nvim_win_get_width(H.term_win())

H.key(H.zen().config.keys.cli)()
vim.wait(400)
H.check("swapped to the cli view", H.cur() == H.term_win())
H.check("cli raised", H.zindex(H.term_win()) == 50)
H.check("code lowered", H.zindex(cw) == 30)
H.check(
  "terminal not resized by the swap",
  vim.api.nvim_win_get_width(H.term_win()) == zen_w,
  zen_w .. " -> " .. vim.api.nvim_win_get_width(H.term_win())
)
H.check("terminal still in one window", #H.term_wins() == 1, vim.inspect(H.term_wins()))

H.key(H.zen().config.keys.code)()
vim.wait(400)
H.check("swapped back to code", H.cur() == cw)

Z.toggle()
vim.wait(500)
H.check("origin refocused after exit", H.cur() == code, "cur=" .. tostring(H.cur()))
H.no_workspace_left()
H.check("cli split restored", H.term() ~= nil and H.term():is_open())
H.check(
  "cli split back to its original width",
  H.term_win() and vim.api.nvim_win_get_width(H.term_win()) == split_width,
  "want=" .. split_width .. " got=" .. tostring(H.term_win() and vim.api.nvim_win_get_width(H.term_win()))
)
H.check("terminal in one window after exit", #H.term_wins() == 1, vim.inspect(H.term_wins()))

return H.report()

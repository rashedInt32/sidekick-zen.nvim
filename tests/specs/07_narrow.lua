-- Regression: below ~100 columns sidekick clamped its float to a minimum 80
-- while zen asked for less, so the first swap resized the PTY. The runner
-- shrinks the real terminal before this spec and leaves zen open for 08.
local H = _G.H
H.reset()
local Z = H.zen()

H.check("editor is narrow", vim.o.columns <= 90, "columns=" .. vim.o.columns)

H.layout()
Z.toggle()
vim.wait(500)
local w = vim.api.nvim_win_get_width(H.term_win())
local h = vim.api.nvim_win_get_height(H.term_win())
H.check("cli float fits the screen", w <= vim.o.columns, "w=" .. w .. " cols=" .. vim.o.columns)

H.key(Z.config.keys.cli)()
vim.wait(500)
H.check(
  "width unchanged by the swap",
  vim.api.nvim_win_get_width(H.term_win()) == w,
  w .. " -> " .. vim.api.nvim_win_get_width(H.term_win())
)
H.check(
  "height unchanged by the swap",
  vim.api.nvim_win_get_height(H.term_win()) == h,
  h .. " -> " .. vim.api.nvim_win_get_height(H.term_win())
)

H.key(Z.config.keys.code)()
vim.wait(500)
H.check(
  "width unchanged swapping back",
  vim.api.nvim_win_get_width(H.term_win()) == w,
  w .. " -> " .. vim.api.nvim_win_get_width(H.term_win())
)
H.check(
  "term.opts.float tracks the live window",
  H.term().opts.float.width == w,
  "opts=" .. tostring(H.term().opts.float.width) .. " live=" .. w
)

-- left open on purpose: 08_resized.lua asserts what VimResized does to it
return H.report()

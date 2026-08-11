-- VimResized while the workspace is open. The runner widens the real terminal
-- between 07 and this spec, so zen must have re-centered everything.
local H = _G.H
H.reset()
local Z = H.zen()

H.check("workspace survived the resize", H.code_win() ~= nil)
H.check("editor is wide again", vim.o.columns >= 150, "columns=" .. vim.o.columns)

local want = math.min(math.max(math.floor(vim.o.columns * Z.config.width), 80), vim.o.columns)
local cw, tw = H.code_win(), H.term_win()
H.check(
  "code float re-centered",
  vim.api.nvim_win_get_width(cw) == want,
  vim.api.nvim_win_get_width(cw) .. " want " .. want
)
H.check(
  "cli float re-centered",
  vim.api.nvim_win_get_width(tw) == want,
  vim.api.nvim_win_get_width(tw) .. " want " .. want
)
H.check(
  "backdrop spans the editor",
  vim.api.nvim_win_get_config(H.backdrop()).width == vim.o.columns,
  tostring(vim.api.nvim_win_get_config(H.backdrop()).width)
)
H.check("terminal still in one window", #H.term_wins() == 1, vim.inspect(H.term_wins()))

local w = vim.api.nvim_win_get_width(tw)
H.key(Z.config.keys.cli)()
vim.wait(500)
H.check(
  "no resize on swap after VimResized",
  vim.api.nvim_win_get_width(H.term_win()) == w,
  w .. " -> " .. vim.api.nvim_win_get_width(H.term_win())
)

Z.toggle()
vim.wait(500)
H.no_workspace_left()

return H.report()

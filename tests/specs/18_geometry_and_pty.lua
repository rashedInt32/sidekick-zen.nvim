-- The suite used to assert only widths and window counts, so mutations that
-- broke float height, row, or column all passed. This asserts full geometry,
-- and asks the CLI process what size its terminal actually is, which is the
-- invariant the plugin exists to protect.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
Z.toggle()
vim.wait(500)

local want = H.expect_geo()
local cw, tw = H.code_win(), H.term_win()

for _, pair in ipairs({ { "code", cw }, { "cli", tw } }) do
  local name, win = pair[1], pair[2]
  local g = H.win_geo(win)
  H.check(name .. " float width", g.width == want.width, g.width .. " want " .. want.width)
  H.check(name .. " float height", g.height == want.height, g.height .. " want " .. want.height)
  H.check(name .. " float row", g.row == want.row, tostring(g.row) .. " want " .. want.row)
  H.check(name .. " float col", g.col == want.col, tostring(g.col) .. " want " .. want.col)
end
H.check(
  "both views occupy the same rectangle",
  vim.deep_equal(
    { H.win_geo(cw).width, H.win_geo(cw).height, H.win_geo(cw).row, H.win_geo(cw).col },
    { H.win_geo(tw).width, H.win_geo(tw).height, H.win_geo(tw).row, H.win_geo(tw).col }
  ),
  "code=" .. vim.inspect(H.win_geo(cw)) .. " cli=" .. vim.inspect(H.win_geo(tw))
)

local bd = vim.api.nvim_win_get_config(H.backdrop())
H.check("backdrop spans the editor width", bd.width == vim.o.columns, bd.width .. " want " .. vim.o.columns)
H.check("backdrop covers the usable rows", bd.height >= want.avail, bd.height .. " want >= " .. want.avail)
H.check(
  "backdrop starts at the top",
  bd.row == 0 and bd.col == 0,
  "row=" .. tostring(bd.row) .. " col=" .. tostring(bd.col)
)
H.check(
  "floats fit on screen",
  want.row + want.height + 2 <= want.avail + 1 and want.col + want.width <= vim.o.columns,
  "row+h=" .. (want.row + want.height) .. " avail=" .. want.avail
)

-- The real thing: what the process believes its terminal to be.
local rows, cols = H.pty_size()
H.check("cli process reported its size", cols ~= nil, "rows=" .. tostring(rows) .. " cols=" .. tostring(cols))
H.check("PTY width matches the cli float", cols == want.width, tostring(cols) .. " want " .. want.width)

-- and it must survive swapping views, which is the whole design claim
H.key(Z.config.keys.cli)()
vim.wait(500)
local r2, c2 = H.pty_size()
H.check(
  "PTY unchanged after swapping to the cli",
  c2 == cols and r2 == rows,
  tostring(r2) .. "x" .. tostring(c2) .. " want " .. tostring(rows) .. "x" .. tostring(cols)
)
H.key(Z.config.keys.code)()
vim.wait(500)
local r3, c3 = H.pty_size()
H.check(
  "PTY unchanged after swapping back",
  c3 == cols and r3 == rows,
  tostring(r3) .. "x" .. tostring(c3) .. " want " .. tostring(rows) .. "x" .. tostring(cols)
)
H.check("terminal still in exactly one window", #H.term_wins() == 1, vim.inspect(H.term_wins()))

-- changing cmdheight changes the usable height; the floats must follow rather
-- than let the next swap resize the PTY underneath the user
local before_h = H.win_geo(cw).height
vim.o.cmdheight = 5
vim.wait(500)
local want2 = H.expect_geo()
H.check(
  "code float followed cmdheight",
  H.win_geo(H.code_win()).height == want2.height,
  H.win_geo(H.code_win()).height .. " want " .. want2.height
)
H.check(
  "cli float followed cmdheight",
  H.win_geo(H.term_win()).height == want2.height,
  H.win_geo(H.term_win()).height .. " want " .. want2.height
)
H.check(
  "backdrop followed cmdheight",
  vim.api.nvim_win_get_config(H.backdrop()).height >= want2.avail,
  tostring(vim.api.nvim_win_get_config(H.backdrop()).height) .. " want >= " .. want2.avail
)
H.check(
  "height actually changed, so this proved something",
  before_h ~= want2.height,
  "before=" .. before_h .. " after=" .. want2.height
)
vim.o.cmdheight = 1
vim.wait(400)

Z.toggle()
vim.wait(600)
H.no_workspace_left()

return H.report()

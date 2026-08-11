-- When nothing is worth mirroring (zen from a lone CLI window) the code view
-- opens an empty scratch canvas. Zen must not invent a real window for it:
-- an earlier design did, and that window survived exit, held a modified
-- unlisted buffer, and blocked :qall with no discoverable culprit.
local H = _G.H
H.reset()
local Z = H.zen()

local function lone_cli()
  H.layout()
  vim.api.nvim_set_current_win(H.term_win())
  vim.cmd("only")
  vim.wait(300)
end

-- untouched canvas: gone on exit, and no window invented for it
lone_cli()
local wins_before = #vim.api.nvim_list_wins()
local bufs_before = #vim.api.nvim_list_bufs()
Z.toggle()
vim.wait(500)
local cw = H.code_win()
H.check("workspace opened", cw ~= nil)
local canvas = cw and vim.api.nvim_win_get_buf(cw)
H.check(
  "code view shows a scratch canvas",
  canvas and vim.bo[canvas].buftype == "nofile",
  tostring(canvas and vim.bo[canvas].buftype)
)
H.check("no real window invented", (function()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      n = n + 1
    end
  end
  return n
end)() == 1, "normal windows during zen")

Z.toggle()
vim.wait(700)
H.no_workspace_left()
H.check("canvas discarded", not vim.api.nvim_buf_is_valid(canvas), "buf=" .. tostring(canvas))
H.check(
  "window count back to normal",
  #vim.api.nvim_list_wins() == wins_before,
  #vim.api.nvim_list_wins() .. " want " .. wins_before
)
H.check(
  "no buffers leaked",
  #vim.api.nvim_list_bufs() <= bufs_before,
  #vim.api.nvim_list_bufs() .. " want <= " .. bufs_before
)
local hidden_modified = false
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[b].modified and vim.fn.bufwinid(b) == -1 and vim.bo[b].buftype == "" then
    hidden_modified = true
  end
end
H.check("nothing modified and hidden left behind", not hidden_modified)

-- a canvas that was typed into is kept and listed, never silently discarded
lone_cli()
Z.toggle()
vim.wait(500)
cw = H.code_win()
canvas = vim.api.nvim_win_get_buf(cw)
vim.api.nvim_buf_set_lines(canvas, 0, -1, false, { "typed into the zen canvas" })
Z.toggle()
vim.wait(700)
H.check("typed-in canvas survived", vim.api.nvim_buf_is_valid(canvas), "buf=" .. tostring(canvas))
H.check("and is listed so it can be found", vim.api.nvim_buf_is_valid(canvas) and vim.bo[canvas].buflisted)
H.check(
  "and still holds the text",
  vim.api.nvim_buf_is_valid(canvas)
    and vim.api.nvim_buf_get_lines(canvas, 0, -1, false)[1] == "typed into the zen canvas",
  vim.inspect(vim.api.nvim_buf_is_valid(canvas) and vim.api.nvim_buf_get_lines(canvas, 0, -1, false))
)
H.check(
  "and cannot block quitting",
  vim.api.nvim_buf_is_valid(canvas) and vim.bo[canvas].buftype == "nofile",
  tostring(vim.api.nvim_buf_is_valid(canvas) and vim.bo[canvas].buftype)
)
if vim.api.nvim_buf_is_valid(canvas) then
  pcall(vim.api.nvim_buf_delete, canvas, { force = true })
end

-- an external close of the code float still tears down cleanly
lone_cli()
Z.toggle()
vim.wait(500)
vim.api.nvim_win_close(H.code_win(), true)
vim.wait(900)
H.no_workspace_left()
local leftover = 0
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local b = vim.api.nvim_win_get_buf(w)
  if vim.api.nvim_buf_get_name(b) == "" and vim.bo[b].buftype == "" then
    leftover = leftover + 1
  end
end
H.check("nothing stranded after an external close", leftover == 0, "leftover=" .. leftover)

return H.report()

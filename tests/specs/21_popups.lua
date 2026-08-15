-- Regression: LSP hover and signature help opened UNDER the code view, so
-- they were invisible in zen. Zen's floats used zindex 50, which is both
-- nvim_open_win()'s default and what nui/noice build popups at, and zen won
-- the tie. Lowering zen to 45 was not enough either: noice's hover view is
-- hardcoded at exactly 45. Zen now sits under the whole popup cluster.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
Z.toggle()
vim.wait(400)
local cw = H.code_win()
H.check("entered on the code view", H.cur() == cw)

-- Every popup zindex zen has to lose to: the bottom of the cluster (snacks
-- layout), noice's hover, and the plain nvim default most plugins inherit.
local function popup(zindex)
  local buf = vim.api.nvim_create_buf(false, true)
  local cfg = { relative = "editor", row = 1, col = 1, width = 20, height = 3, style = "minimal" }
  cfg.zindex = zindex -- omitted means "nvim's default", which is what most plugins take
  return vim.api.nvim_open_win(buf, false, cfg)
end

for _, case in ipairs({
  { label = "the lowest popup in the wild", z = H.LOWEST_POPUP },
  { label = "a noice hover", z = 45 },
  { label = "a default-zindex popup", z = nil },
}) do
  local win = popup(case.z)
  local detail = "popup=" .. tostring(H.zindex(win)) .. " code=" .. tostring(H.zindex(cw))
  H.check(case.label .. " floats above the code view", H.zindex(win) > H.zindex(cw), detail)
  H.check(case.label .. " floats above the backdrop", H.zindex(win) > H.zindex(H.backdrop()), detail)
  vim.api.nvim_win_close(win, true)
end

-- The real thing: what vim.lsp.buf.hover() and signature_help() open.
local _, hover = vim.lsp.util.open_floating_preview({ "const runProbe: HttpApiEndpoint" }, "markdown", {
  focus = false,
  border = "rounded",
})
vim.wait(100)
H.check(
  "an LSP preview floats above the code view",
  hover ~= nil and H.zindex(hover) > H.zindex(cw),
  "hover=" .. tostring(hover and H.zindex(hover)) .. " code=" .. tostring(H.zindex(cw))
)
H.check("the popup did not tear the workspace down", H.code_win() == cw)
H.check("nor steal focus from the code view", H.cur() == cw)
if hover and vim.api.nvim_win_is_valid(hover) then
  vim.api.nvim_win_close(hover, true)
end
vim.wait(200)

-- Zen must still own exactly its three floats afterwards.
H.check("workspace intact", H.code_win() ~= nil and H.backdrop() ~= nil and H.term_win() ~= nil)
H.check("no stray zen floats", #H.zen_floats() == 3, vim.inspect(H.zen_floats()))

Z.toggle()
vim.wait(500)
H.no_workspace_left()

return H.report()

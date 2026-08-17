-- The code float mirrors the gutter of the window it was opened from, instead
-- of taking `style = "minimal"`'s `signcolumn=auto`, under which the first
-- gitsign or diagnostic shifts every line one column right.
local H = _G.H
H.reset()
local Z = H.zen()

local origin = H.layout()
local saved = {
  signcolumn = vim.wo[origin].signcolumn,
  number = vim.wo[origin].number,
  foldcolumn = vim.wo[origin].foldcolumn,
}

-- The text column of a window, i.e. everything the gutter occupies.
local function textoff(win)
  local info = vim.fn.getwininfo(win)[1]
  return info and info.textoff or -1
end

-- 1. A reserved gutter is carried over, and stays put when a sign lands in it.
vim.wo[origin].signcolumn = "yes"
vim.wo[origin].number = false
vim.wo[origin].foldcolumn = "0"

Z.toggle()
vim.wait(400)
local cw = H.code_win()
H.check("code float open", cw ~= nil)
H.check("signcolumn mirrored", vim.wo[cw].signcolumn == "yes", vim.wo[cw].signcolumn)
H.check("numbers left off", vim.wo[cw].number == false)

local before = textoff(cw)
H.check("gutter reserved while empty", before > 0, "textoff=" .. before)

local buf = vim.api.nvim_win_get_buf(cw)
local ns = vim.api.nvim_create_namespace("zen_gutter_spec")
vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { sign_text = "E>" })
vim.wait(200)
local after = textoff(cw)
H.check("code does not shift when a sign lands", before == after, before .. " -> " .. after)
vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

Z.toggle()
vim.wait(500)
H.no_workspace_left()

-- 2. `auto` is the shift itself, so it is pinned open rather than mirrored.
vim.wo[origin].signcolumn = "auto"
Z.toggle()
vim.wait(400)
cw = H.code_win()
H.check("auto pinned open", cw and vim.wo[cw].signcolumn == "yes", cw and vim.wo[cw].signcolumn or "no win")
Z.toggle()
vim.wait(500)

-- 3. Whoever does use line numbers keeps them.
vim.wo[origin].signcolumn = "yes"
vim.wo[origin].number = true
Z.toggle()
vim.wait(400)
cw = H.code_win()
H.check("numbers mirrored when the origin has them", cw and vim.wo[cw].number == true)
H.check("numbers widen the gutter", cw and textoff(cw) > 2, "textoff=" .. (cw and textoff(cw) or -1))
Z.toggle()
vim.wait(500)
H.no_workspace_left()

for opt, value in pairs(saved) do
  vim.wo[origin][opt] = value
end

return H.report()

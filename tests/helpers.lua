-- Assertions and window introspection shared by every spec, exposed as _G.H.
local H = {}

H.dir = vim.env.ZEN_FIXTURES or "/tmp"
H.log = {}
H.fail = {}

function H.reset()
  H.log = {}
  H.fail = {}
end

function H.check(name, cond, detail)
  if not cond then
    table.insert(H.fail, name)
  end
  table.insert(H.log, (cond and "  pass  " or "  FAIL  ") .. name .. (detail and ("   [" .. detail .. "]") or ""))
end

function H.report()
  local head = (#H.fail == 0) and "ALL PASS" or ("FAIL: " .. table.concat(H.fail, "; "))
  return head .. "\n" .. table.concat(H.log, "\n")
end

function H.zen()
  return require("sidekick-zen")
end

-- A fake CLI tool: a long-lived line-reader. No network, no auth, and it
-- behaves like a TUI as far as the PTY is concerned.
function H.register_tool()
  require("sidekick.config").cli.tools.zentest = {
    cmd = { "sh", "-c", "printf 'ZENTEST READY\\n'; while true; do read -r x || sleep 1; done" },
  }
end

function H.term()
  local ok, T = pcall(require, "sidekick.cli.terminal")
  if not ok then
    return nil
  end
  for _, t in ipairs(T.sessions()) do
    if t:buf_valid() then
      return t
    end
  end
  return nil
end

function H.open_cli()
  H.register_tool()
  require("sidekick.cli").show({ name = "zentest", focus = false })
  vim.wait(3000, function()
    local t = H.term()
    return t ~= nil and t:is_running()
  end)
  vim.wait(500)
  return H.term()
end

function H.close_cli()
  local ok, T = pcall(require, "sidekick.cli.terminal")
  if not ok then
    return
  end
  for _, t in ipairs(T.sessions()) do
    pcall(function()
      t:close()
    end)
  end
  vim.wait(400)
end

function H.term_win()
  local t = H.term()
  return t and t:win_valid() and t.win or nil
end

-- Every window currently showing the terminal buffer. The PTY follows the
-- smallest of these, so the suite asserts there is exactly one.
function H.term_wins()
  local t = H.term()
  if not t or not t:buf_valid() then
    return {}
  end
  local out = {}
  for _, w in ipairs(vim.fn.win_findbuf(t.buf)) do
    table.insert(out, { win = w, width = vim.api.nvim_win_get_width(w) })
  end
  return out
end

function H.zindex(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  return vim.api.nvim_win_get_config(win).zindex
end

function H.cur()
  return vim.api.nvim_get_current_win()
end

function H.buf_name(win)
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win or 0)), ":t")
end

-- Only zen's own floats. Notification popups sit at a much higher zindex and
-- must never be mistaken for the workspace.
function H.zen_floats()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local c = vim.api.nvim_win_get_config(w)
    if c.relative ~= "" and (c.zindex == 50 or c.zindex == 40 or c.zindex == 30) then
      table.insert(out, { win = w, z = c.zindex, width = c.width })
    end
  end
  return out
end

function H.code_win()
  local tw = H.term_win()
  for _, f in ipairs(H.zen_floats()) do
    if f.win ~= tw and f.z ~= 40 then
      return f.win
    end
  end
  return nil
end

function H.backdrop()
  for _, f in ipairs(H.zen_floats()) do
    if f.z == 40 then
      return f.win
    end
  end
  return nil
end

function H.ws_autocmds()
  local ok, list = pcall(vim.api.nvim_get_autocmds, { group = "sidekick_zen_ws" })
  return ok and #list or -1
end

function H.key(lhs, mode)
  local m = vim.fn.maparg(lhs, mode or "n", false, true)
  return m and m.callback
end

-- Standard working layout: one code window plus a sidekick CLI split.
function H.layout()
  pcall(function()
    require("sidekick-zen").exit()
  end)
  H.close_cli()
  vim.cmd("silent! only")
  vim.cmd("silent! edit! " .. H.dir .. "/alpha.txt")
  vim.bo.modified = false
  H.open_cli()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype ~= "terminal" then
      vim.api.nvim_set_current_win(w)
      break
    end
  end
  return vim.api.nvim_get_current_win()
end

function H.no_workspace_left()
  H.check("no zen floats left", #H.zen_floats() == 0, vim.inspect(H.zen_floats()))
  H.check("workspace autocmds cleared", H.ws_autocmds() == 0, "n=" .. H.ws_autocmds())
end

_G.H = H
return "helpers loaded"

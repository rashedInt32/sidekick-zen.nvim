-- sidekick-zen.nvim: a zen workspace for code + your sidekick.nvim CLI tool.
--
-- One toggle opens a distraction-free workspace: your code and your AI CLI
-- session as centered floats over an opaque backdrop, one visible at a time.
-- Switch keys flip between them from normal AND terminal mode, so you never
-- leave the flow to juggle windows.
--
-- Why views swap by zindex instead of opening/closing windows: nvim sizes a
-- terminal's PTY to the *smallest* window showing its buffer. A zen plugin
-- that opens a second window on the terminal leaves the TUI rendering at the
-- old split's width. Here the terminal float is always the only window on
-- its buffer, and swapping views just raises one float above the backdrop
-- and lowers the other beneath it. Nothing resizes, so the TUI never
-- reflows or flickers between switches.
--
-- The sidekick terminal is re-opened as a float by mutating the terminal's
-- own opts (sidekick deep-copies `cli.win` per instance). The code view is a
-- separate float on the same buffer as the origin window; buffer and cursor
-- sync back to the origin on exit.

local M = {}

M.config = {
  -- Fraction of the editor width (absolute columns if > 1).
  width = 0.8,
  -- View-switch keys, active in normal and terminal mode only while zen is
  -- active. Whatever they shadowed is restored on exit.
  keys = {
    code = "<C-h>", -- show the code view
    cli = "<C-l>", -- show the CLI view
    -- Exit zen from normal mode in either view. Shadows macro recording
    -- while zen is active; set to false if you record macros in zen.
    exit = "q",
  },
  -- Remap sidekick's hide keys (`q` and `<c-.>`) on the CLI buffer to
  -- "switch to code view" while zen is active, so they don't tear the
  -- workspace down. Set to false if you rebound sidekick's hide keys.
  hijack_hide_keys = true,
}

local Z = { top = 50, backdrop = 40, hidden = 30 }

---@class sidekick.zen.Workspace
---@field view "code"|"cli"
---@field origin integer original code window (stays behind the backdrop)
---@field code_win integer
---@field backdrop integer
---@field term? sidekick.cli.Terminal
---@field term_was_open? boolean
---@field saved? { layout: string, float: vim.api.keyset.win_config }
---@field watchers integer[]

---@type sidekick.zen.Workspace?
local ws = nil

local initialized = false
local group = vim.api.nvim_create_augroup("sidekick_zen", { clear = true })

local function editor_height()
  return vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
end

local function geo()
  local width = M.config.width <= 1 and math.floor(vim.o.columns * M.config.width) or M.config.width
  return {
    width = width,
    height = editor_height() - 2, -- minus the two solid border rows
    row = 0,
    col = math.floor((vim.o.columns - width) / 2),
  }
end

-- "solid" border = one cell of bg-colored padding all around.
local function float_cfg(g, visible)
  return {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
    border = "solid",
    zindex = visible and Z.top or Z.hidden,
  }
end

local function define_bg()
  if vim.fn.hlexists("SidekickZenBg") == 1 and not vim.api.nvim_get_hl(0, { name = "SidekickZenBg" }).default then
    return -- user or colorscheme defined it explicitly
  end
  local chat = vim.api.nvim_get_hl(0, { name = "SidekickChat", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.api.nvim_set_hl(0, "SidekickZenBg", { bg = chat.bg or normal.bg, default = true })
end

local function open_backdrop()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = math.max(editor_height(), 1),
    style = "minimal",
    focusable = false,
    zindex = Z.backdrop,
  })
  vim.wo[win].winhighlight = "Normal:SidekickZenBg,NormalNC:SidekickZenBg,EndOfBuffer:SidekickZenBg"
  return win
end

-- Keymap overrides live only while zen is active. Save whatever they shadow
-- (user globals, sidekick's buffer-local keys) and restore on exit.
local saved_maps = {} ---@type { mode: string, lhs: string, dict: table, buf?: integer }[]

local function push_map(mode, lhs, rhs, opts)
  opts = opts or {}
  local dict
  if opts.buffer then
    dict = vim.api.nvim_buf_call(opts.buffer, function()
      return vim.fn.maparg(lhs, mode, false, true)
    end)
  else
    dict = vim.fn.maparg(lhs, mode, false, true)
  end
  table.insert(saved_maps, { mode = mode, lhs = lhs, dict = dict, buf = opts.buffer })
  vim.keymap.set(mode, lhs, rhs, opts)
end

local function pop_maps()
  for i = #saved_maps, 1, -1 do
    local m = saved_maps[i]
    if not m.buf or vim.api.nvim_buf_is_valid(m.buf) then
      local restore = function()
        pcall(vim.keymap.del, m.mode, m.lhs, m.buf and { buffer = m.buf } or nil)
        if m.dict and not vim.tbl_isempty(m.dict) then
          vim.fn.mapset(m.mode, false, m.dict)
        end
      end
      if m.buf then
        vim.api.nvim_buf_call(m.buf, restore)
      else
        restore()
      end
    end
  end
  saved_maps = {}
end

local function terminals()
  local ok, Terminal = pcall(require, "sidekick.cli.terminal")
  return ok and Terminal or nil
end

-- The terminal to adopt: the current window's session if we're in one,
-- otherwise the most recently used running session.
local function find_term()
  local Terminal = terminals()
  if not Terminal then
    return nil
  end
  local id = vim.w.sidekick_session_id
  if id and Terminal.get(id) then
    return Terminal.get(id)
  end
  local sessions = vim.tbl_filter(function(t)
    return t:is_running() and t:buf_valid()
  end, Terminal.sessions())
  table.sort(sessions, function(a, b)
    return (a.atime or 0) > (b.atime or 0)
  end)
  return sessions[1]
end

local function cli_win()
  return ws and ws.term and ws.term:win_valid() and ws.term.win or nil
end

local function switch(view)
  if not ws or ws.view == view then
    return
  end
  local cwin = cli_win()
  if view == "cli" and not cwin then
    vim.notify("No sidekick CLI session running", vim.log.levels.WARN, { title = "sidekick-zen" })
    return
  end
  local g = geo()
  if view == "cli" then
    vim.api.nvim_win_set_config(ws.code_win, float_cfg(g, false))
    vim.api.nvim_win_set_config(cwin, float_cfg(g, true))
    ws.view = view
    ws.term:focus() -- also enters insert in the CLI's input box
  else
    if cwin then
      vim.api.nvim_win_set_config(cwin, float_cfg(g, false))
    end
    vim.api.nvim_win_set_config(ws.code_win, float_cfg(g, true))
    ws.view = view
    vim.api.nvim_set_current_win(ws.code_win)
  end
end

local function watch(win)
  return vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    once = true,
    callback = function()
      -- A zen window closed behind our back (:q, process exit, plugin
      -- keymaps): tear the whole workspace down to stay consistent.
      vim.schedule(function()
        if ws then
          M.exit()
        end
      end)
    end,
  })
end

local function enter()
  local term = find_term()
  local entry = (vim.w.sidekick_session_id and term) and "cli" or "code"

  -- Origin code window: current one, or the previous window when entering
  -- from the sidekick split. It stays untouched behind the backdrop.
  local origin = vim.api.nvim_get_current_win()
  if entry == "cli" then
    local prev = vim.fn.win_getid(vim.fn.winnr("#"))
    origin = prev ~= 0 and vim.api.nvim_win_get_config(prev).relative == "" and prev or origin
    if origin == vim.api.nvim_get_current_win() then
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if w ~= origin and vim.api.nvim_win_get_config(w).relative == "" then
          origin = w
          break
        end
      end
    end
  end

  define_bg()
  local g = geo()

  -- Code view: a live float on the origin's buffer, view carried over.
  local view = vim.api.nvim_win_call(origin, function()
    return vim.fn.winsaveview()
  end)
  local cfg = float_cfg(g, entry == "code")
  cfg.style = "minimal"
  local code_win = vim.api.nvim_open_win(vim.api.nvim_win_get_buf(origin), false, cfg)
  -- Snacks pickers exclude floats when resolving their "main" window and
  -- would open files in the hidden origin split; this marker whitelists the
  -- zen float (same trick as Snacks.zen itself).
  vim.w[code_win].snacks_main = true
  vim.wo[code_win].winhighlight =
    "NormalFloat:SidekickZenBg,FloatBorder:SidekickZenBg,EndOfBuffer:SidekickZenBg,SignColumn:SidekickZenBg"
  vim.api.nvim_win_call(code_win, function()
    vim.fn.winrestview(view)
  end)

  ws = {
    view = entry,
    origin = origin,
    code_win = code_win,
    backdrop = open_backdrop(),
    term = term,
    last_buf = vim.api.nvim_win_get_buf(origin),
    watchers = { watch(code_win) },
  }

  -- A fresh float has no per-buffer view memory, so a file opened here lands
  -- on its remembered cursor line at an arbitrary window row (often showing
  -- the file's tail). Center once the position settles; the schedule lets
  -- last-position autocmds (BufReadPost) move the cursor first.
  table.insert(
    ws.watchers,
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      callback = function(ev)
        if not ws or not vim.api.nvim_win_is_valid(ws.code_win) then
          return
        end
        if vim.api.nvim_get_current_win() ~= ws.code_win or ev.buf == ws.last_buf then
          return
        end
        ws.last_buf = ev.buf
        vim.schedule(function()
          if ws and vim.api.nvim_win_is_valid(ws.code_win) and vim.api.nvim_win_get_buf(ws.code_win) == ev.buf then
            vim.api.nvim_win_call(ws.code_win, function()
              vim.cmd("normal! zvzz")
            end)
          end
        end)
      end,
    })
  )

  -- Fallback for openers that still target a "real" window: if a buffer
  -- lands in the hidden origin window, adopt it into the code view and pull
  -- focus back above the backdrop.
  table.insert(
    ws.watchers,
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      callback = function(ev)
        if not ws or vim.api.nvim_get_current_win() ~= ws.origin then
          return
        end
        if not vim.api.nvim_win_is_valid(ws.code_win) then
          return
        end
        -- The opener placed the cursor in the origin window; carry it over,
        -- since set_buf would otherwise clamp the float's stale cursor.
        local cur = vim.api.nvim_win_get_cursor(ws.origin)
        vim.api.nvim_win_set_buf(ws.code_win, ev.buf)
        ws.last_buf = ev.buf
        pcall(vim.api.nvim_win_set_cursor, ws.code_win, cur)
        vim.api.nvim_win_call(ws.code_win, function()
          vim.cmd("normal! zvzz")
        end)
        if ws.view ~= "code" then
          switch("code")
        else
          vim.api.nvim_set_current_win(ws.code_win)
        end
      end,
    })
  )

  -- CLI view: re-open the sidekick terminal as a zen float. The blank title
  -- overrides sidekick's default " Sidekick " (nvim rejects a title without
  -- a border, so it can't simply be dropped).
  if term then
    ws.term_was_open = term:is_open()
    ws.saved = { layout = term.opts.layout, float = vim.deepcopy(term.opts.float) }
    term.opts.layout = "float"
    term.opts.float = vim.tbl_extend("force", float_cfg(g, entry == "cli"), { title = " " })
    term:hide()
    term:show()
    if term:win_valid() then
      vim.wo[term.win].winhighlight = vim.wo[term.win].winhighlight .. ",FloatBorder:SidekickZenBg"
      table.insert(ws.watchers, watch(term.win))
    end
  end

  -- Sidekick's own actions (send {this}/{file}/{selection}, prompt, focus)
  -- show+focus the terminal window directly. During zen that window is the
  -- hidden CLI float, so focusing it would land below the backdrop; raise
  -- the CLI view instead, as if the user pressed keys.cli.
  table.insert(
    ws.watchers,
    vim.api.nvim_create_autocmd("WinEnter", {
      group = group,
      callback = function()
        if not ws or ws.view == "cli" then
          return
        end
        if vim.api.nvim_get_current_win() == cli_win() then
          switch("cli")
        end
      end,
    })
  )

  -- Switch keys swap views instead of walking (hidden) splits.
  for _, mode in ipairs({ "n", "t" }) do
    push_map(mode, M.config.keys.code, function()
      switch("code")
    end, { desc = "Zen: code view" })
    push_map(mode, M.config.keys.cli, function()
      switch("cli")
    end, { desc = "Zen: CLI view" })
  end
  if M.config.keys.exit then
    push_map("n", M.config.keys.exit, function()
      M.exit()
    end, { desc = "Zen: exit" })
  end
  if term and term:buf_valid() then
    -- Sidekick's hide keys exit zen / switch views instead of hiding the
    -- terminal mid-workspace. q needs the buffer-local override because
    -- sidekick's own buffer-local q (hide) shadows the global exit map.
    if M.config.hijack_hide_keys then
      push_map("n", "q", function()
        M.exit()
      end, { buffer = term.buf, desc = "Zen: exit" })
      for _, mode in ipairs({ "n", "t" }) do
        push_map(mode, "<c-.>", function()
          switch("code")
        end, { buffer = term.buf, desc = "Zen: code view" })
      end
    end
    -- Sidekick's own buffer-local t-mode nav maps (<c-h>/<c-l> by default)
    -- shadow the global zen overrides and no-op in float layouts, sending
    -- the key into the TUI. Shadow them right back on the terminal buffer.
    for _, mode in ipairs({ "n", "t" }) do
      push_map(mode, M.config.keys.code, function()
        switch("code")
      end, { buffer = term.buf, desc = "Zen: code view" })
      push_map(mode, M.config.keys.cli, function()
        switch("cli")
      end, { buffer = term.buf, desc = "Zen: CLI view" })
    end
  end

  if entry == "cli" then
    term:focus()
  else
    vim.api.nvim_set_current_win(code_win)
  end
end

function M.exit()
  if not ws then
    return
  end
  local s = ws
  ws = nil
  for _, id in ipairs(s.watchers) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  pop_maps()

  -- Whatever was reached inside the code view becomes the origin's state.
  if vim.api.nvim_win_is_valid(s.code_win) then
    local buf = vim.api.nvim_win_get_buf(s.code_win)
    local view = vim.api.nvim_win_call(s.code_win, function()
      return vim.fn.winsaveview()
    end)
    pcall(vim.api.nvim_win_close, s.code_win, true)
    if vim.api.nvim_win_is_valid(s.origin) then
      vim.api.nvim_win_set_buf(s.origin, buf)
      vim.api.nvim_win_call(s.origin, function()
        vim.fn.winrestview(view)
      end)
    end
  end
  if vim.api.nvim_win_is_valid(s.backdrop) then
    pcall(vim.api.nvim_win_close, s.backdrop, true)
  end

  if s.term and s.saved then
    s.term.opts.layout = s.saved.layout
    s.term.opts.float = s.saved.float
    if s.term:win_valid() then
      s.term:hide()
      if s.term_was_open then
        s.term:show()
      end
    end
  end

  if vim.api.nvim_win_is_valid(s.origin) then
    vim.api.nvim_set_current_win(s.origin)
  end
end

function M.toggle()
  if not initialized then
    M.setup()
  end
  if ws then
    M.exit()
  else
    enter()
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if initialized then
    return
  end
  initialized = true

  vim.api.nvim_create_user_command("SidekickZen", M.toggle, { desc = "Toggle the sidekick zen workspace" })

  -- Geometry is absolute, so track terminal resizes.
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if not ws then
        return
      end
      local g = geo()
      if vim.api.nvim_win_is_valid(ws.backdrop) then
        vim.api.nvim_win_set_config(ws.backdrop, {
          relative = "editor",
          row = 0,
          col = 0,
          width = vim.o.columns,
          height = math.max(editor_height(), 1),
        })
      end
      if vim.api.nvim_win_is_valid(ws.code_win) then
        vim.api.nvim_win_set_config(ws.code_win, float_cfg(g, ws.view == "code"))
      end
      local cwin = cli_win()
      if cwin then
        vim.api.nvim_win_set_config(cwin, float_cfg(g, ws.view == "cli"))
      end
    end,
  })
end

return M

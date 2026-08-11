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
  -- Backdrop colour. Defaults to the CLI's own background, falling back to
  -- Normal. Accepts anything nvim_set_hl takes for `bg`, e.g. "#0d1522".
  backdrop_bg = nil,
}

local Z = { top = 50, backdrop = 40, hidden = 30 }

-- Sidekick clamps its own floats to this minimum (cli/terminal.lua), so a
-- smaller request would leave the CLI float wider than the geometry we push
-- on every later swap -- and resize the PTY. Clamp to the same floor.
local MIN = { width = 80, height = 10 }

-- Never adopted as an origin when we're only guessing: cloning a sidebar or
-- quickfix buffer into the code float is wrong, and exit would write the zen
-- buffer back into that window.
local DENY_BUFTYPE = { nofile = true, quickfix = true, help = true, prompt = true, terminal = true }

---@class sidekick.zen.Workspace
---@field view "code"|"cli"
---@field tab integer tabpage the floats live in
---@field origin? integer window the code view mirrors (nil if none was usable)
---@field placeholder? integer scratch buffer of an origin window zen invented
---@field code_win integer
---@field backdrop integer
---@field last_buf integer buffer last seen in the code view
---@field term? sidekick.cli.Terminal
---@field term_was_open? boolean
---@field saved? { layout: string, float: vim.api.keyset.win_config }

---@type sidekick.zen.Workspace?
local ws = nil

local initialized = false
local group = vim.api.nvim_create_augroup("sidekick_zen", { clear = true })
-- Everything registered while a workspace is open lives here, so teardown is
-- a single clear instead of tracking ids.
local ws_group = vim.api.nvim_create_augroup("sidekick_zen_ws", { clear = true })

local function editor_height()
  return vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
end

local function geo()
  local width = M.config.width <= 1 and math.floor(vim.o.columns * M.config.width) or M.config.width
  width = math.min(math.max(width, MIN.width), vim.o.columns)
  local height = math.max(editor_height() - 2, MIN.height) -- minus the two solid border rows
  return {
    width = width,
    height = height,
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

-- The blank title overrides sidekick's default " Sidekick " (nvim rejects a
-- title without a border, so it can't simply be dropped).
local function cli_float_cfg(g, visible)
  return vim.tbl_extend("force", float_cfg(g, visible), { title = " " })
end

local function backdrop_cfg()
  return {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = math.max(editor_height(), 1),
  }
end

-- Recomputed on every enter, and again if the colorscheme changes mid-session.
-- An earlier version tried to detect a user-defined group and skip, but
-- nvim_get_hl reports no `default` field, so the check never fired and zen's
-- first definition stuck forever. `config.backdrop_bg` is the override now.
local function define_bg()
  local bg = M.config.backdrop_bg
  if not bg then
    local chat = vim.api.nvim_get_hl(0, { name = "SidekickChat", link = false })
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    bg = chat.bg or normal.bg
  end
  vim.api.nvim_set_hl(0, "SidekickZenBg", { bg = bg })
end

local function open_backdrop()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local cfg = vim.tbl_extend("force", backdrop_cfg(), {
    style = "minimal",
    focusable = false,
    zindex = Z.backdrop,
  })
  local win = vim.api.nvim_open_win(buf, false, cfg)
  vim.wo[win].winhighlight = "Normal:SidekickZenBg,NormalNC:SidekickZenBg,EndOfBuffer:SidekickZenBg"
  return win
end

-- A fresh float has no per-buffer view memory, so a restored cursor lands at
-- an arbitrary window row, often showing the file's tail.
local function center(win)
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! zvzz")
  end)
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

-- The terminal to adopt: the current window's session if we're in one,
-- otherwise the most recently used running session.
local function find_term()
  local ok, Terminal = pcall(require, "sidekick.cli.terminal")
  if not ok then
    return nil
  end
  local id = vim.w.sidekick_session_id
  local current = id and Terminal.get(id)
  if current then
    return current
  end
  local best ---@type sidekick.cli.Terminal?
  for _, t in ipairs(Terminal.sessions()) do
    if t:is_running() and t:buf_valid() and (not best or (t.atime or 0) > (best.atime or 0)) then
      best = t
    end
  end
  return best
end

local function code_win()
  return ws and vim.api.nvim_win_is_valid(ws.code_win) and ws.code_win or nil
end

local function cli_win()
  return ws and ws.term and ws.term:win_valid() and ws.term.win or nil
end

-- Switching to the CLI needs a live process too. Sidekick keeps the window
-- around for a few seconds after the job dies, and focusing it would re-run
-- jobstart against the dirty buffer (E5108).
local function cli_ready()
  return cli_win() ~= nil and ws.term:is_running()
end

-- zindex is a pure function of ws.view, applied in one place.
local function place()
  if not ws then
    return
  end
  local g = geo()
  for _, item in ipairs({ { code_win(), "code" }, { cli_win(), "cli" } }) do
    if item[1] then
      vim.api.nvim_win_set_config(item[1], float_cfg(g, ws.view == item[2]))
    end
  end
  -- Keep the terminal's own opts in sync, or a later show() would reopen the
  -- float at enter-time geometry.
  if ws.term and ws.saved then
    ws.term.opts.float = cli_float_cfg(g, ws.view == "cli")
  end
end

local function switch(view)
  if not ws or ws.view == view then
    return
  end
  if view == "cli" and not cli_ready() then
    vim.notify("No sidekick CLI session running", vim.log.levels.WARN, { title = "sidekick-zen" })
    return
  end
  local cw = code_win()
  if not cw then
    return -- teardown in flight; the WinClosed watcher owns it from here
  end
  ws.view = view
  place()
  if view == "cli" then
    ws.term:focus() -- also enters insert in the CLI's input box
  else
    vim.api.nvim_set_current_win(cw)
  end
end

-- Put the cursor back on whatever is currently on top. Every zen window is a
-- float, so any normal window the cursor reaches sits under the backdrop and
-- would be typed into blind.
local function focus_active()
  if not ws then
    return
  end
  if ws.view == "cli" then
    if cli_ready() then
      ws.term:focus()
    else
      switch("code") -- the CLI died out from under us; recover onto the code view
    end
    return
  end
  local cw = code_win()
  if cw then
    vim.api.nvim_set_current_win(cw)
  end
end

-- What the switch keys call. Unlike switch(), asking for the view you are
-- already on re-asserts focus, so the keys can rescue a stranded cursor.
local function show_view(view)
  if not ws then
    return
  end
  if ws.view == view then
    focus_active()
  else
    switch(view)
  end
end

local function watch(win)
  local mine = ws
  vim.api.nvim_create_autocmd("WinClosed", {
    group = ws_group,
    pattern = tostring(win),
    once = true,
    callback = function()
      -- A zen window closed behind our back (:q, process exit, plugin
      -- keymaps): tear the whole workspace down to stay consistent. Compare
      -- identity, or a queued callback can tear down a workspace opened
      -- after this one in the same tick.
      vim.schedule(function()
        if ws and ws == mine then
          M.exit()
        end
      end)
    end,
  })
end

-- A window the code view can safely mirror: real, not floating, not the CLI
-- terminal (cloning that buffer would show the PTY in a second window and
-- shrink it), and not a sidebar, quickfix or help window. Exit writes the
-- code view's buffer back into this window, which destroys anything whose
-- content is not a file. That applies to the focused window too: an earlier
-- version exempted it on the grounds that the user had chosen it, and that
-- ate quickfix and oil windows.
local function usable_origin(win, term_buf)
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if buf == term_buf then
    return false
  end
  return not DENY_BUFTYPE[vim.bo[buf].buftype]
end

local function pick_origin(term_buf)
  local candidates = { vim.api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#")) }
  vim.list_extend(candidates, vim.api.nvim_tabpage_list_wins(0))
  for _, win in ipairs(candidates) do
    if usable_origin(win, term_buf) then
      return win
    end
  end
  return nil
end

local function map_views(buf)
  for _, mode in ipairs({ "n", "t" }) do
    push_map(mode, M.config.keys.code, function()
      show_view("code")
    end, { buffer = buf, desc = "Zen: code view" })
    push_map(mode, M.config.keys.cli, function()
      show_view("cli")
    end, { buffer = buf, desc = "Zen: CLI view" })
  end
end

local function enter()
  vim.api.nvim_clear_autocmds({ group = ws_group })

  local term = find_term()
  local term_buf = term and term:buf_valid() and term.buf or nil
  local entry = (vim.w.sidekick_session_id and term) and "cli" or "code"

  -- The window the code view mirrors. It stays untouched behind the backdrop.
  local origin = pick_origin(term_buf)
  local placeholder
  if not origin then
    -- Nothing usable, e.g. zen from a lone CLI window. Invent a real window:
    -- the code view needs somewhere to sync back to, and sidekick's hide()
    -- needs one too, because nvim refuses to close the last non-floating
    -- window and would otherwise strand the old CLI split on the same buffer.
    vim.cmd("silent! botright new")
    origin = vim.api.nvim_get_current_win()
    placeholder = vim.api.nvim_win_get_buf(origin)
    vim.bo[placeholder].buflisted = false
    vim.bo[placeholder].bufhidden = "wipe"
  end

  define_bg()
  local g = geo()

  local cfg = float_cfg(g, entry == "code")
  cfg.style = "minimal"
  local code_buf = vim.api.nvim_win_get_buf(origin)
  local view = vim.api.nvim_win_call(origin, vim.fn.winsaveview)
  local code_win_id = vim.api.nvim_open_win(code_buf, false, cfg)
  -- Snacks pickers exclude floats when resolving their "main" window and
  -- would open files in the hidden origin split; this marker whitelists the
  -- zen float (same trick as Snacks.zen itself).
  vim.w[code_win_id].snacks_main = true
  vim.wo[code_win_id].winhighlight =
    "NormalFloat:SidekickZenBg,FloatBorder:SidekickZenBg,EndOfBuffer:SidekickZenBg,SignColumn:SidekickZenBg"
  vim.api.nvim_win_call(code_win_id, function()
    vim.fn.winrestview(view)
  end)

  ws = {
    view = entry,
    tab = vim.api.nvim_get_current_tabpage(),
    origin = origin,
    placeholder = placeholder,
    code_win = code_win_id,
    backdrop = open_backdrop(),
    term = term,
    last_buf = code_buf,
  }
  watch(code_win_id)

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = ws_group,
    callback = function(ev)
      local cw = code_win()
      if not cw then
        return
      end
      local cur = vim.api.nvim_get_current_win()
      if cur == cw then
        -- Center once the position settles; the schedule lets last-position
        -- autocmds (BufReadPost) move the cursor first.
        if ev.buf == ws.last_buf then
          return
        end
        ws.last_buf = ev.buf
        vim.schedule(function()
          local w = code_win()
          if w and vim.api.nvim_win_get_buf(w) == ev.buf then
            center(w)
          end
        end)
      elseif ws.origin and cur == ws.origin then
        -- Fallback for openers that still target a "real" window: adopt the
        -- buffer into the code view and pull focus back above the backdrop.
        -- The opener placed the cursor in the origin window, so carry it
        -- over; set_buf would otherwise clamp the float's stale cursor.
        local cursor = vim.api.nvim_win_get_cursor(ws.origin)
        vim.api.nvim_win_set_buf(cw, ev.buf)
        ws.last_buf = ev.buf
        pcall(vim.api.nvim_win_set_cursor, cw, cursor)
        center(cw)
        -- Focus has to move after the opening command finishes; changing the
        -- current window from inside BufWinEnter gets undone, which would
        -- leave the cursor typing into the window below the backdrop.
        vim.schedule(function()
          local w = code_win()
          if not w then
            return
          end
          if ws.view ~= "code" then
            switch("code")
          else
            vim.api.nvim_set_current_win(w)
          end
        end)
      end
    end,
  })

  -- CLI view: re-open the sidekick terminal as a zen float.
  if term then
    ws.term_was_open = term:is_open()
    ws.saved = { layout = term.opts.layout, float = vim.deepcopy(term.opts.float) }
    term.opts.layout = "float"
    term.opts.float = cli_float_cfg(g, entry == "cli")
    term:hide()
    term:show()
    -- The PTY follows the smallest window showing this buffer, so the zen
    -- float has to be the only one. sidekick's hide() leaves its split behind
    -- when it was the last non-floating window. Only this tabpage: closing a
    -- window elsewhere can be the last one in its tabpage and take the whole
    -- tabpage with it, which nothing restores.
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= term.win and vim.api.nvim_win_get_buf(w) == term.buf then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
    if term:win_valid() then
      vim.wo[term.win].winhighlight = vim.wo[term.win].winhighlight .. ",FloatBorder:SidekickZenBg"
      watch(term.win)
    end
  end

  -- Sidekick's own actions (send {this}/{file}/{selection}, prompt, focus,
  -- blur) show and focus its windows directly. During zen the focused window
  -- can be the float hidden below the backdrop, so follow focus with the view
  -- rather than leaving the cursor somewhere invisible.
  vim.api.nvim_create_autocmd("WinEnter", {
    group = ws_group,
    callback = function()
      if not ws or vim.api.nvim_get_current_tabpage() ~= ws.tab then
        return
      end
      local cur = vim.api.nvim_get_current_win()
      if cur == cli_win() then
        switch("cli")
      elseif cur == code_win() then
        switch("code")
      elseif vim.api.nvim_win_get_config(cur).relative == "" then
        -- A normal window, so it is underneath the backdrop: <c-w>w and
        -- friends land here and the cursor would be invisible. Bounce back.
        focus_active()
      end
    end,
  })

  -- The floats belong to this tabpage. Rather than leave global keys driving
  -- an invisible workspace from another tab, close it on the way out.
  vim.api.nvim_create_autocmd("TabLeave", {
    group = ws_group,
    callback = function()
      if ws and vim.api.nvim_get_current_tabpage() == ws.tab then
        vim.schedule(M.exit)
      end
    end,
  })

  -- Switch keys swap views instead of walking (hidden) splits.
  map_views(nil)
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
    map_views(term.buf)
  end

  if entry == "cli" then
    term:focus()
  else
    vim.api.nvim_set_current_win(code_win_id)
  end
end

function M.exit()
  if not ws then
    return
  end
  local s = ws
  ws = nil
  vim.api.nvim_clear_autocmds({ group = ws_group })
  pop_maps()

  -- Capture whatever the code view reached before tearing it down.
  local buf, view
  if vim.api.nvim_win_is_valid(s.code_win) then
    buf = vim.api.nvim_win_get_buf(s.code_win)
    view = vim.api.nvim_win_call(s.code_win, vim.fn.winsaveview)
    pcall(vim.api.nvim_win_close, s.code_win, true)
  end
  if vim.api.nvim_win_is_valid(s.backdrop) then
    pcall(vim.api.nvim_win_close, s.backdrop, true)
  end

  -- Restore the terminal before touching the origin, so a window always
  -- remains and closes below can't hit "last window".
  if s.saved then
    s.term.opts.layout = s.saved.layout
    s.term.opts.float = s.saved.float
    if s.term:win_valid() then
      s.term:hide()
      -- Only re-show a live session. sidekick's show() runs start(), which
      -- jobstarts the tool again when the job is dead, so exiting zen would
      -- silently spawn a second CLI process.
      if s.term_was_open and s.term:is_running() then
        s.term:show()
      end
    end
  end

  local origin = s.origin and vim.api.nvim_win_is_valid(s.origin) and s.origin or nil
  -- Nothing claimed the window zen invented, so drop it. `buf` is nil when the
  -- code float was closed externally, which must still count as unclaimed.
  local unclaimed = s.placeholder and (buf == nil or buf == s.placeholder)
  if origin and unclaimed then
    -- Unless it was typed into: closing would discard that text silently.
    if vim.bo[s.placeholder].modified then
      vim.bo[s.placeholder].bufhidden = ""
    else
      pcall(vim.api.nvim_win_close, origin, true)
      origin = vim.api.nvim_win_is_valid(origin) and origin or nil
    end
  elseif origin and buf then
    -- Whatever was reached inside the code view becomes the origin's state.
    vim.api.nvim_win_set_buf(origin, buf)
    vim.api.nvim_win_call(origin, function()
      vim.fn.winrestview(view)
    end)
  end
  if origin then
    vim.api.nvim_set_current_win(origin)
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
      if vim.api.nvim_win_is_valid(ws.backdrop) then
        vim.api.nvim_win_set_config(ws.backdrop, backdrop_cfg())
      end
      place()
    end,
  })
end

return M

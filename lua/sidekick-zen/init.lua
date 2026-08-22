-- sidekick-zen.nvim: a zen workspace for code + your sidekick.nvim CLI tool.
--
-- One toggle opens a distraction-free workspace: your code and your AI CLI
-- session as centered floats over an opaque backdrop, one visible at a time.
-- Switch keys flip between them from normal AND terminal mode, so you never
-- leave the flow to juggle windows.
--
-- Why views swap in place instead of opening or closing windows: nvim sizes
-- a terminal's PTY to the LARGEST window showing its buffer. A second, wider
-- view of the CLI makes its TUI render wider than the float it lives in, and
-- clip. So the terminal float is kept as the only window on its buffer, and
-- swapping raises one float and puts the other away. Neither window is ever
-- resized or reopened, so the TUI never reflows.
--
-- Scope, deliberately small: zen owns its own three floats and nothing else.
-- It does not restructure, adopt, or write into your windows. Earlier
-- versions mirrored a window and synced back on exit, which is where nearly
-- every bug in this plugin's history lived. Anything zen cannot represent,
-- such as a new split or another tabpage, closes the workspace instead of
-- being absorbed.

local M = {}

M.config = {
  -- Fraction of the editor width (absolute columns if > 1).
  width = 0.8,
  -- View-switch keys, active in normal and terminal mode only while zen is
  -- active. Whatever they shadowed is restored on exit.
  keys = {
    code = "<C-h>", -- show the code view
    -- Show the CLI view. Pressed again while typing in the CLI, the key is
    -- passed through to the TUI, so <C-l> still reaches Claude Code's
    -- repaint when its input box drifts.
    cli = "<C-l>",
    -- Exit zen from normal mode in either view. Shadows macro recording
    -- while zen is active; set to false if you record macros in zen.
    exit = "q",
  },
  -- Remap sidekick's hide keys (`q` and `<c-.>`) on the CLI buffer to
  -- "switch to code view" while zen is active, so they don't tear the
  -- workspace down. Set to false if you rebound sidekick's hide keys.
  hijack_hide_keys = true,
  -- Backdrop colour. Defaults to the CLI's own background, falling back to
  -- Normal. Anything nvim_set_hl accepts for `bg`, e.g. "#0d1522".
  backdrop_bg = nil,
}

-- Zen deliberately sits at the BOTTOM of the float stack, not the top.
--
-- It used to sit at 50, which is nvim_open_win()'s default and where most
-- popups land, and zen won the tie: LSP hover, signature help and picker
-- previews all opened underneath the code view, invisible. Nothing you can
-- read is worth covering, so the fix is not a bigger number but a smaller
-- one. Surveying the popups in the wild, the whole cluster starts at 30
-- (snacks layout 30, snacks picker preview 40, mason 44, noice hover 45,
-- oil 45, nui 50, nvim's own default 50, notify 65, blink 1001). A top float
-- at 25 slides under all of it, so every popup shows over zen without any of
-- them needing to know zen exists.
--
-- The backdrop loses nothing by going down with it: floats always draw above
-- ordinary windows whatever their zindex, and hiding ordinary windows is the
-- only job the backdrop has.
--
-- `hidden` is where an inactive float rests: below the backdrop, so it is
-- covered whether or not it is also `hide`d, and so revealing it never
-- flashes it under the backdrop first.
local Z = { top = 25, backdrop = 15, hidden = 5 }

-- Sidekick clamps its own floats to this minimum (cli/terminal.lua). Asking
-- for less leaves its float wider than the geometry we push on later swaps,
-- which resizes the PTY, so we never ask for less.
local MIN = { width = 80, height = 10 }

---@class sidekick.zen.Workspace
---@field view "code"|"cli"
---@field tab integer tabpage the floats live in
---@field code_win integer
---@field code_scratch? integer buffer zen created because nothing was suitable
---@field gutter table<string, any> mirrored gutter, re-applied on every buffer swap
---@field entry_win? integer window to refocus on exit; never written into blindly
---@field entry_buf integer buffer the code view opened on
---@field backdrop integer
---@field normal_wins integer non-floating window count when the workspace opened
---@field borrowed { win: integer, buf: integer }[] windows whose buffer zen swapped out
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
  return math.max(vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0), 1)
end

-- Geometry for both floats. Clamped up to sidekick's minimum and back down to
-- what fits, so a small editor cannot produce a float that overhangs the
-- screen or one that sidekick silently re-clamps to a different size.
local function geo()
  local avail = editor_height()
  local width = M.config.width <= 1 and math.floor(vim.o.columns * M.config.width) or M.config.width
  width = math.min(math.max(width, MIN.width), vim.o.columns)
  -- Minus two solid border rows, minus one more so a row of bare backdrop
  -- separates the float from the statusline.
  local height = math.min(math.max(avail - 3, MIN.height), avail)
  return {
    width = width,
    height = height,
    -- Sidekick reads row/col <= 1 as a fraction of the screen, so keep both
    -- above that and centre by hand. Centre the BORDERED extent (+2 each
    -- axis): centring the text area alone pushed the float down a row, and
    -- its bottom border row painted over the statusline.
    row = math.max(math.floor((avail - height - 2) / 2), 0),
    col = math.max(math.floor((vim.o.columns - width - 2) / 2), 0),
  }
end

-- "solid" border = one cell of bg-colored padding all around.
--
-- An inactive float is dropped below the backdrop, where it is invisible but
-- still an ordinary window. Only the CLI is also `hide`d, and only the CLI:
-- see cli_float_cfg.
local function float_cfg(g, visible)
  return {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
    border = "solid",
    zindex = visible and Z.top or Z.hidden,
    hide = false,
  }
end

-- The blank title overrides sidekick's default " Sidekick " (nvim rejects a
-- title without a border, so it can't simply be dropped).
--
-- The inactive CLI is `hide`d rather than merely covered. A covered-but-open
-- terminal float still forces a full redraw on every byte its TUI emits, and
-- every redraw hides, repositions and re-shows the real cursor, so an AI CLI
-- streaming in the background makes the cursor flicker around the screen.
-- Hiding the window stops the redraws outright. nvim keeps a hidden window's
-- dimensions, so the PTY still never resizes; zindex is kept in step so
-- layering is already right the moment the float is revealed.
--
-- The code float is deliberately NOT hidden, because nothing is gained and
-- something is lost. A static file emits no bytes, so there are no redraws to
-- suppress, while `wincmd p` skips hidden windows entirely. Sidekick's blur()
-- IS `wincmd p`: with the code float hidden, blurring the CLI could not reach
-- it, so the cursor stayed put, no WinEnter fired, and zen never swapped the
-- view. Covered-but-open leaves it a legal window to jump into.
local function cli_float_cfg(g, visible)
  return vim.tbl_extend("force", float_cfg(g, visible), { title = " ", hide = not visible })
end

local function backdrop_cfg()
  return {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = editor_height(),
  }
end

-- Recomputed on every enter, so it follows the colorscheme.
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

local function is_float(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= ""
end

local function count_normal_wins()
  local n = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not is_float(w) then
      n = n + 1
    end
  end
  return n
end

-- Keymap overrides live only while zen is active, and must restore exactly
-- what they shadowed.
--
-- vim.fn.maparg() returns the BUFFER-LOCAL mapping whenever the current
-- buffer has one, so using it to snapshot a global map captured the wrong
-- entry. Exit then deleted the user's real global mapping and stamped a
-- foreign buffer-local one onto whatever buffer happened to be current.
-- Query the two scopes through APIs that cannot conflate them.
local saved_maps = {} ---@type { mode: string, lhs: string, dict?: table, buf?: integer }[]

local function same_lhs(a, b)
  return vim.api.nvim_replace_termcodes(a, true, true, true) == vim.api.nvim_replace_termcodes(b, true, true, true)
end

local function find_map(mode, lhs, buf)
  local maps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
  for _, m in ipairs(maps) do
    if m.lhs and same_lhs(m.lhs, lhs) then
      return m
    end
  end
end

local function push_map(mode, lhs, rhs, opts)
  opts = opts or {}
  table.insert(saved_maps, { mode = mode, lhs = lhs, dict = find_map(mode, lhs, opts.buffer), buf = opts.buffer })
  vim.keymap.set(mode, lhs, rhs, opts)
end

local function pop_maps()
  for i = #saved_maps, 1, -1 do
    local m = saved_maps[i]
    if not m.buf or vim.api.nvim_buf_is_valid(m.buf) then
      pcall(vim.keymap.del, m.mode, m.lhs, m.buf and { buffer = m.buf } or nil)
      if m.dict then
        -- mapset honours the dict's own `buffer` field, so restore each one
        -- with its original buffer current.
        local restore = function()
          pcall(vim.fn.mapset, m.mode, false, m.dict)
        end
        if m.buf then
          vim.api.nvim_buf_call(m.buf, restore)
        else
          restore()
        end
      end
    end
  end
  saved_maps = {}
end

-- The terminal to adopt: the current window's session if we're in one,
-- otherwise the most recently used running session. Liveness is checked on
-- BOTH paths, because enter() shows the terminal and sidekick's show() runs
-- start(), which jobstarts a dead job into a brand new process.
local function find_term()
  local ok, Terminal = pcall(require, "sidekick.cli.terminal")
  if not ok then
    return nil
  end
  local id = vim.w.sidekick_session_id
  local current = id and Terminal.get(id)
  if current and current:is_running() and current:buf_valid() then
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

-- Visibility is a pure function of ws.view, applied in one place.
local function place()
  if not ws then
    return
  end
  local g = geo()
  local wins = { code = code_win(), cli = cli_win() }
  -- Reveal the active float before hiding the other. Hiding the window the
  -- cursor is in hands focus to whatever nvim picks next, and in zen that is
  -- a window under the backdrop.
  local order = ws.view == "code" and { "code", "cli" } or { "cli", "code" }
  for _, view in ipairs(order) do
    if wins[view] then
      local cfg = view == "cli" and cli_float_cfg or float_cfg
      vim.api.nvim_win_set_config(wins[view], cfg(g, view == ws.view))
    end
  end
  if vim.api.nvim_win_is_valid(ws.backdrop) then
    vim.api.nvim_win_set_config(ws.backdrop, backdrop_cfg())
  end
  -- Keep the terminal's own opts in sync, or a later show() reopens the float
  -- at stale geometry.
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
--
-- One exception: the CLI key, pressed while already typing in the CLI, goes
-- through to the TUI instead of being swallowed. <C-l> is Claude Code's
-- repaint command and the one reliable fix for its shifted/ghosted input
-- box, and the zen override used to eat it.
local function show_view(view)
  if not ws then
    return
  end
  if ws.view ~= view then
    switch(view)
    return
  end
  if view == "cli" and cli_ready() and ws.term:is_focused() and vim.api.nvim_get_mode().mode == "t" then
    local key = vim.api.nvim_replace_termcodes(M.config.keys.cli, true, true, true)
    -- Unmapped keys fed in terminal mode land in the PTY, encoded the way a
    -- real keypress would be.
    vim.api.nvim_feedkeys(key, "n", false)
    return
  end
  focus_active()
end

local function watch(win)
  local mine = ws
  vim.api.nvim_create_autocmd("WinClosed", {
    group = ws_group,
    pattern = tostring(win),
    once = true,
    callback = function()
      -- A zen window closed behind our back (:q, process exit, a "close every
      -- float" mapping): tear the whole workspace down to stay consistent.
      -- Compare identity, or a queued callback can tear down a workspace
      -- opened after this one in the same tick.
      vim.schedule(function()
        if ws and ws == mine then
          M.exit()
        end
      end)
    end,
  })
end

-- Global scope is normal mode only: the code float swaps buffers as you
-- navigate, so its switch keys cannot live on any one buffer. Terminal mode
-- is scoped to the CLI buffer alone -- a global t-map would eat <C-h>/<C-l>
-- inside every other terminal open in the tabpage, and those keystrokes
-- belong to whatever TUI the user is typing into.
local function map_views(buf)
  for _, mode in ipairs(buf and { "n", "t" } or { "n" }) do
    push_map(mode, M.config.keys.code, function()
      show_view("code")
    end, { buffer = buf, desc = "Zen: code view" })
    push_map(mode, M.config.keys.cli, function()
      show_view("cli")
    end, { buffer = buf, desc = "Zen: CLI view" })
  end
end

-- The buffer the code view opens on: the current window's when it holds a
-- real file, otherwise the nearest normal window's. Nothing is written into
-- these windows during zen, so this only decides what you see first.
local function entry_buffer(term_buf)
  local function usable(win, files_only)
    if not win or win == 0 or not vim.api.nvim_win_is_valid(win) or is_float(win) then
      return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == term_buf or vim.bo[buf].buftype == "terminal" then
      return false
    end
    return not files_only or vim.bo[buf].buftype == ""
  end
  local candidates = { vim.api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#")) }
  vim.list_extend(candidates, vim.api.nvim_tabpage_list_wins(0))
  -- Prefer a real file. Toggling from a sidebar or quickfix is far more
  -- likely to mean "zen my code" than "zen this sidebar".
  for _, files_only in ipairs({ true, false }) do
    for _, win in ipairs(candidates) do
      if usable(win, files_only) then
        return vim.api.nvim_win_get_buf(win), win
      end
    end
  end
  return nil, nil
end

-- Any other window showing the CLI buffer makes the PTY follow whichever is
-- larger, so the TUI renders at a size its float does not match. Swap those
-- windows onto a scratch buffer rather than closing them: closing the last
-- window of another tabpage destroys that tabpage, and closing a window the
-- user opened themselves loses it for good. Handed back on exit.
local function borrow_cli_windows(term, stale)
  local borrowed = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= term.win and vim.api.nvim_win_get_buf(w) == term.buf then
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.bo[scratch].bufhidden = "wipe"
      if pcall(vim.api.nvim_win_set_buf, w, scratch) then
        -- `stale` is sidekick's own split, left behind because nvim refuses
        -- to close the last non-floating window. It is not the user's, so it
        -- is closed on exit rather than handed back.
        table.insert(borrowed, { win = w, buf = term.buf, stale = w == stale })
      end
    end
  end
  return borrowed
end

-- `style = "minimal"` does not merely blank the gutter, it forces 'signcolumn'
-- to `auto`: no reserved column until a sign exists, so the first gitsign or
-- diagnostic shoves every line one column right. In a view whose whole selling
-- point is stillness, that shove is the loudest thing on screen.
--
-- So the code float mirrors the gutter of the window zen was opened from,
-- which is the one the user already tuned, instead of minimal's opinion.
local GUTTER = { "number", "relativenumber", "numberwidth", "signcolumn", "foldcolumn", "statuscolumn" }

-- `auto` widths are the shift itself: the column exists only while it has
-- something to show. Pin them open at the widest they could ever grow, so the
-- signs arrive into space that was already there.
local function reserve(opt, value)
  if type(value) ~= "string" or not value:find("^auto") then
    return value
  end
  -- The trailing digit of "auto:2" or "auto:1-3" is its maximum.
  local width = value:match("(%d)$")
  if opt == "signcolumn" then
    return width and ("yes:" .. width) or "yes"
  end
  -- 'foldcolumn' has no "yes", only a count.
  return width or "1"
end

-- Snapshot rather than read on demand: the window zen was opened from is under
-- the backdrop for the whole session and may be gone by the time a second file
-- lands in the float.
local function gutter_of(src)
  -- Zen from a lone CLI has no source window, so fall back to the globals a
  -- fresh split would have inherited.
  local from = (src and vim.api.nvim_win_is_valid(src)) and vim.wo[src] or vim.go
  local out = {}
  for _, opt in ipairs(GUTTER) do
    local ok, value = pcall(function()
      return from[opt]
    end)
    if ok then
      out[opt] = reserve(opt, value)
    end
  end
  return out
end

-- `style = "minimal"` is sticky, not a one-time stamp: nvim re-derives the
-- whole gutter from it every time a buffer enters the window, so applying the
-- mirror once at open lasts exactly until you jump to a second file, and the
-- shift comes back. Nothing survives that reset -- not `vim.wo`, not `:set` in
-- the window, not `nvim_set_option_value` -- so the mirror is re-applied on
-- every buffer swap instead.
local function apply_gutter(win, gutter)
  if not (gutter and win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  for opt, value in pairs(gutter) do
    pcall(function()
      vim.wo[win][opt] = value
    end)
  end
end

local function enter()
  vim.api.nvim_clear_autocmds({ group = ws_group })

  local term = find_term()
  local term_buf = term and term:buf_valid() and term.buf or nil
  local entry = (vim.w.sidekick_session_id and term) and "cli" or "code"

  -- Fail before anything exists rather than half way through: a bad
  -- backdrop_bg used to throw after a window had already been created,
  -- leaving it orphaned with no workspace to clean it up.
  local ok, err = pcall(define_bg)
  if not ok then
    vim.notify("sidekick-zen: " .. tostring(err), vim.log.levels.ERROR, { title = "sidekick-zen" })
    return
  end

  local code_buf, entry_win = entry_buffer(term_buf)
  local code_scratch
  if not code_buf then
    -- Nothing worth mirroring, e.g. zen from a lone CLI window. An empty
    -- canvas, discarded on exit. `nofile` so it can never block :qall.
    code_scratch = vim.api.nvim_create_buf(false, true)
    vim.bo[code_scratch].buftype = "nofile"
    vim.bo[code_scratch].bufhidden = "wipe"
    code_buf = code_scratch
  end

  local g = geo()
  local cfg = float_cfg(g, entry == "code")
  cfg.style = "minimal"
  local code_win_id = vim.api.nvim_open_win(code_buf, false, cfg)
  -- Snacks pickers exclude floats when resolving their "main" window and
  -- would open files in a window under the backdrop; this marker whitelists
  -- the zen float, the same trick Snacks.zen uses.
  vim.w[code_win_id].snacks_main = true
  local gutter = gutter_of(entry_win)
  apply_gutter(code_win_id, gutter)
  vim.wo[code_win_id].winhighlight =
    "NormalFloat:SidekickZenBg,FloatBorder:SidekickZenBg,EndOfBuffer:SidekickZenBg,SignColumn:SidekickZenBg"
  if entry_win then
    local saved_view = vim.api.nvim_win_call(entry_win, vim.fn.winsaveview)
    vim.api.nvim_win_call(code_win_id, function()
      vim.fn.winrestview(saved_view)
    end)
  end

  ws = {
    view = entry,
    tab = vim.api.nvim_get_current_tabpage(),
    code_win = code_win_id,
    code_scratch = code_scratch,
    gutter = gutter,
    entry_win = entry_win,
    entry_buf = code_buf,
    backdrop = open_backdrop(),
    term = term,
    borrowed = {},
    normal_wins = 0,
  }
  watch(code_win_id)
  watch(ws.backdrop)

  -- CLI view: re-open the sidekick terminal as a zen float.
  if term then
    ws.term_was_open = term:is_open()
    ws.saved = { layout = term.opts.layout, float = vim.deepcopy(term.opts.float) }
    term.opts.layout = "float"
    term.opts.float = cli_float_cfg(g, entry == "cli")
    local prev_win = term:win_valid() and term.win or nil
    term:hide()
    term:show()
    ws.borrowed = borrow_cli_windows(term, prev_win)
    if term:win_valid() then
      vim.wo[term.win].winhighlight = vim.wo[term.win].winhighlight .. ",FloatBorder:SidekickZenBg"
      watch(term.win)
    end
  end
  ws.normal_wins = count_normal_wins()
  place()

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = ws_group,
    callback = function(ev)
      local cw = code_win()
      if not cw then
        return
      end
      local cur = vim.api.nvim_get_current_win()
      if cur == cw then
        -- Before the early return: minimal has already reset the gutter by the
        -- time this fires, whether or not the buffer is one we have seen.
        apply_gutter(cw, ws.gutter)
        if ev.buf == ws.entry_buf then
          return
        end
        -- Centre once the position settles; the schedule lets last-position
        -- autocmds (BufReadPost) move the cursor first.
        ws.entry_buf = ev.buf
        vim.schedule(function()
          local w = code_win()
          if w and vim.api.nvim_win_get_buf(w) == ev.buf then
            center(w)
          end
        end)
      elseif ws.entry_win and cur == ws.entry_win then
        -- An opener that ignores the snacks_main marker and targets the
        -- window we came from. That window is under the backdrop, so show the
        -- buffer here instead of letting it open invisibly. Scoped to that
        -- one window: anything newly created is handled by WinNew instead.
        local cursor = vim.api.nvim_win_get_cursor(cur)
        vim.api.nvim_win_set_buf(cw, ev.buf)
        -- Our own swap, so no nested BufWinEnter reaches the branch above.
        apply_gutter(cw, ws.gutter)
        ws.entry_buf = ev.buf
        pcall(vim.api.nvim_win_set_cursor, cw, cursor)
        center(cw)
        -- Focus has to move after the opening command finishes; changing the
        -- current window from inside BufWinEnter gets undone.
        vim.schedule(function()
          if ws then
            focus_active()
          end
        end)
      end
    end,
  })

  -- Sidekick's own actions (send, prompt, focus, blur) move focus directly,
  -- and the cursor can also be walked into a window under the backdrop with
  -- <c-w>w. Follow focus so the visible view always matches the cursor.
  -- The bounce is deferred: doing it synchronously hijacks the second half
  -- of a compound command such as `:split | edit foo`.
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
      else
        vim.schedule(function()
          if ws and not is_float(vim.api.nvim_get_current_win()) then
            focus_active()
          end
        end)
      end
    end,
  })

  -- A new normal window is something zen cannot show: it would sit under the
  -- backdrop, unreachable, and survive exit as clutter. Step aside instead of
  -- swallowing it.
  vim.api.nvim_create_autocmd("WinNew", {
    group = ws_group,
    callback = function()
      vim.schedule(function()
        if ws and count_normal_wins() > ws.normal_wins then
          M.exit()
        end
      end)
    end,
  })

  -- The floats belong to this tabpage, so leaving it closes the workspace
  -- rather than leaving global keys driving something invisible.
  vim.api.nvim_create_autocmd("TabLeave", {
    group = ws_group,
    callback = function()
      if ws and vim.api.nvim_get_current_tabpage() == ws.tab then
        vim.schedule(M.exit)
      end
    end,
  })

  -- Both change the usable editor height. A stale backdrop leaves a strip of
  -- the hidden view showing, and the next swap silently resizes the PTY.
  vim.api.nvim_create_autocmd("OptionSet", {
    group = ws_group,
    pattern = { "cmdheight", "laststatus" },
    callback = function()
      vim.schedule(place)
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
    -- Sidekick's hide keys exit zen or switch views instead of hiding the
    -- terminal mid-workspace. q needs the buffer-local override because
    -- sidekick's own buffer-local q (hide) shadows the global exit map.
    if M.config.hijack_hide_keys then
      push_map("n", "q", function()
        M.exit()
      end, { buffer = term.buf, desc = "Zen: exit" })
      for _, mode in ipairs({ "n", "t" }) do
        push_map(mode, "<c-.>", function()
          show_view("code")
        end, { buffer = term.buf, desc = "Zen: code view" })
      end
    end
    -- Sidekick's own buffer-local terminal-mode nav maps (<c-h>/<c-l> by
    -- default) shadow the global zen overrides and no-op in float layouts,
    -- sending the key into the TUI. Shadow them right back.
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

  -- The scratch canvas is wiped when its window closes, so rescue it first if
  -- it holds anything, rather than discarding the text silently. Keyed on
  -- content, not on 'modified': a `nofile` buffer does not track that.
  local function canvas_has_text()
    local b = s.code_scratch
    if not b or not vim.api.nvim_buf_is_valid(b) then
      return false
    end
    local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
    return #lines > 1 or (lines[1] or "") ~= ""
  end
  if canvas_has_text() then
    vim.bo[s.code_scratch].bufhidden = "hide"
    vim.bo[s.code_scratch].buflisted = true
    vim.notify(
      ("kept your unsaved zen scratch buffer as #%d"):format(s.code_scratch),
      vim.log.levels.WARN,
      { title = "sidekick-zen" }
    )
  end

  local reached, saved_view
  if vim.api.nvim_win_is_valid(s.code_win) then
    reached = vim.api.nvim_win_get_buf(s.code_win)
    saved_view = vim.api.nvim_win_call(s.code_win, vim.fn.winsaveview)
    pcall(vim.api.nvim_win_close, s.code_win, true)
  end
  if vim.api.nvim_win_is_valid(s.backdrop) then
    pcall(vim.api.nvim_win_close, s.backdrop, true)
  end

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

  -- Hand back any window whose CLI buffer was swapped out on the way in, and
  -- drop sidekick's own leftover split. This runs after the terminal has been
  -- restored, so another normal window exists and the close can succeed.
  for _, b in ipairs(s.borrowed) do
    if vim.api.nvim_win_is_valid(b.win) then
      if b.stale then
        pcall(vim.api.nvim_win_close, b.win, true)
      elseif vim.api.nvim_buf_is_valid(b.buf) then
        pcall(vim.api.nvim_win_set_buf, b.win, b.buf)
      end
    end
  end

  -- Carry the file you navigated to back to the window you came from, but
  -- only while that is still an ordinary file window showing exactly what it
  -- showed when zen opened. Anything else belongs to the user, and writing
  -- into it is how earlier versions destroyed quickfix and explorer windows.
  local entry_win = s.entry_win
  local same_tab = vim.api.nvim_get_current_tabpage() == s.tab
  if
    entry_win
    and reached
    and reached ~= s.code_scratch
    and vim.api.nvim_win_is_valid(entry_win)
    and not is_float(entry_win)
    and vim.api.nvim_buf_is_valid(reached)
    and vim.api.nvim_win_get_buf(entry_win) == s.entry_buf
    and vim.bo[s.entry_buf].buftype == ""
  then
    vim.api.nvim_win_set_buf(entry_win, reached)
    vim.api.nvim_win_call(entry_win, function()
      vim.fn.winrestview(saved_view)
    end)
  end

  -- Refocus only when still on the workspace's tabpage. Focusing a window in
  -- another tab would drag the user out of the tab they just asked for.
  if same_tab and entry_win and vim.api.nvim_win_is_valid(entry_win) then
    pcall(vim.api.nvim_set_current_win, entry_win)
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

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      place()
    end,
  })
end

return M

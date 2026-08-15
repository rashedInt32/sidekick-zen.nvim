# 🧘 sidekick-zen.nvim

Zen mode that takes your AI along.

One key drops your code and your [sidekick.nvim](https://github.com/folke/sidekick.nvim) CLI (Claude Code, Codex, Gemini, …) into a clean, centered, distraction-free view. `<C-h>` and `<C-l>` flip between them, and they work straight from the CLI's input box. No double-escape, no window juggling.

https://github.com/user-attachments/assets/d3b49d0d-c8cb-4ed0-8b4d-e44eb7f6fc1c

## Why another zen plugin?

Because the usual ones break terminals. Neovim sizes a terminal's PTY to the *largest* window showing its buffer. Wrap your AI CLI in a zen plugin that opens a second view and the TUI renders at the wrong width and clips, inside an otherwise empty float.

sidekick-zen never shows the terminal twice. It re-opens the sidekick terminal itself as a zen float, and switching views only raises one float above the backdrop and drops the other below it. Nothing resizes, so the TUI never reflows or flickers. The test suite asks the CLI process directly what size its terminal is, rather than trusting window widths.

The scope is deliberately small: zen owns its own three floats and nothing else. It does not restructure your windows or write into them uninvited. Anything it cannot represent, such as a new split or another tabpage, closes the workspace rather than swallowing it.

## Install

Needs Neovim 0.10+ and sidekick.nvim (works without it too, you just get code-only zen). With lazy.nvim:

```lua
{
  "rashedInt32/sidekick-zen.nvim",
  dependencies = { "folke/sidekick.nvim" },
  cmd = "SidekickZen",
  keys = {
    {
      "<leader>z",
      function()
        require("sidekick-zen").toggle()
      end,
      desc = "Toggle Zen Workspace",
    },
  },
  opts = {},
}
```

## Keys

| Key | Where | What |
| --- | --- | --- |
| your toggle | anywhere | enter / exit zen |
| `<C-h>` | zen, normal + terminal mode | show code |
| `<C-l>` | zen, normal + terminal mode | show the CLI |
| `<C-l>` again | zen, typing in the CLI | passed through to the TUI |
| `q` | zen, normal mode | exit zen |
| `<c-.>` | zen, CLI view | switch to code instead of hiding |

Enter from code and you see code first. Enter from the sidekick window and you land on the CLI, cursor in its input box. `:SidekickZen` toggles too.

The pass-through matters for Claude Code: its input box sometimes drifts and leaves a ghost copy of itself behind, and `<C-l>` is its repaint command. Since the switch key only *switches* when you are elsewhere, pressing it once more inside the CLI hands the real `<C-l>` to Claude and cleans the screen up.

Sidekick's own keymaps play along: sending `{this}`, `{file}`, or a selection, picking a prompt, or focusing the CLI all raise the CLI view automatically, so the context lands where you can see it.

## Config

These are the defaults:

```lua
require("sidekick-zen").setup({
  width = 0.8, -- fraction of the editor, or absolute columns if > 1
  keys = {
    code = "<C-h>",
    -- Pressed again while typing in the CLI, this key goes to the TUI
    -- itself (Claude Code repaints on <C-l>).
    cli = "<C-l>",
    -- q exits from normal mode in either view. It shadows macro recording
    -- while zen is active, so set it to false if you record macros there.
    exit = "q",
  },
  -- q and <c-.> switch to code during zen instead of hiding the CLI.
  -- Set false if you rebound sidekick's hide keys.
  hijack_hide_keys = true,
  -- Backdrop colour. Defaults to the CLI's own background, falling back
  -- to Normal. It is recomputed on every toggle so it tracks your theme.
  backdrop_bg = nil, -- e.g. "#0d1522"
})
```

### Behaviour worth knowing

Zen steps aside rather than hiding things from you. It closes itself when you leave its tabpage, and when anything opens a new ordinary window, because that window would sit under the backdrop where you could never reach it. Reopening is one keystroke.

It prefers a real file to mirror. Toggle from a sidebar or quickfix window and you get the nearest file window instead, or an empty scratch canvas if there is none. That canvas is discarded on exit unless you typed in it, in which case it is kept and listed.

Popups stay on top. Zen sits at the bottom of the float stack, under every zindex popups are known to use, so LSP hover, signature help, completion menus and pickers render over the workspace instead of behind it. The backdrop loses nothing by going down there too: floats always draw above ordinary windows whatever their zindex, and hiding ordinary windows is the only job it has.

Navigating inside zen carries back to the window you came from, but only while that window is still an ordinary file window showing what it showed when zen opened. Anything else is yours, and zen leaves it alone.

> [!NOTE]
> The CLI view leans on sidekick internals, tested against sidekick.nvim `208e1c5`. If an update breaks something, open an issue.

## Tests

```bash
tests/run.sh            # everything
tests/run.sh lone_cli   # one spec
```

The suite runs neovim inside tmux and drives it over RPC, because a real terminal is the only place the PTY sizing above actually happens. The fake CLI it drives reports its own `stty size`, so the specs assert what the process believes rather than what the window claims. Nothing hits the network. sidekick.nvim is cloned into `tests/.deps` on first run; set `SIDEKICK_REF` to test against a specific revision.

Every spec guards a bug that was once real, so please add one alongside a fix. The suite is itself checked by mutation: deliberately reintroducing each historic bug must turn it red. An earlier version passed 18/18 with nine live defects, which is the failure mode this guards against.

## Credits

[folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) for the sidekick, [folke/zen-mode.nvim](https://github.com/folke/zen-mode.nvim) for the look.

MIT licensed.

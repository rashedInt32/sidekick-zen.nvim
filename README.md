# 🧘 sidekick-zen.nvim

Zen mode that takes your AI along.

One key drops your code and your [sidekick.nvim](https://github.com/folke/sidekick.nvim) CLI (Claude Code, Codex, Gemini, …) into a clean, centered, distraction-free view. `<C-h>` and `<C-l>` flip between them, and they work straight from the CLI's input box. No double-escape, no window juggling.

https://github.com/user-attachments/assets/d3b49d0d-c8cb-4ed0-8b4d-e44eb7f6fc1c

## Why another zen plugin?

Because the usual ones break terminals. Neovim sizes a terminal to the *smallest* window showing it, so wrapping your AI CLI in zen-mode.nvim or Snacks.zen leaves the TUI rendering at its old split width inside a big empty float.

sidekick-zen never shows the terminal twice. It re-opens the sidekick terminal itself as a zen float, and switching views just raises one float above the backdrop and lowers the other beneath it. Nothing resizes, so the TUI never reflows or flickers.

A few things it gets right along the way: the code view is a real window, so pickers and file browsers work inside it and everything syncs back when you leave. The switch keys only exist while zen is active, and whatever they shadowed comes back on exit. And if the CLI dies or something closes a window behind its back, the whole thing tears down cleanly.

## Install

Needs Neovim 0.10+ and sidekick.nvim (works without it too, you just get code-only zen). With lazy.nvim:

```lua
{
  "rashedInt32/sidekick-zen.nvim",
  dependencies = { "folke/sidekick.nvim" },
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
| `q` | zen, normal mode | exit zen |
| `<c-.>` | zen, CLI view | switch to code instead of hiding |

Enter from code and you see code first. Enter from the sidekick window and you land on the CLI, cursor in its input box. `:SidekickZen` toggles too.

Sidekick's own keymaps play along: sending `{this}`, `{file}`, or a selection, picking a prompt, or focusing the CLI all raise the CLI view automatically, so the context lands where you can see it.

## Config

These are the defaults:

```lua
require("sidekick-zen").setup({
  width = 0.8, -- fraction of the editor, or absolute columns if > 1
  keys = {
    code = "<C-h>",
    cli = "<C-l>",
    -- q exits from normal mode in either view. It shadows macro recording
    -- while zen is active, so set it to false if you record macros there.
    exit = "q",
  },
  -- q and <c-.> switch to code during zen instead of hiding the CLI.
  -- Set false if you rebound sidekick's hide keys.
  hijack_hide_keys = true,
})
```

The backdrop color comes from the `SidekickZenBg` highlight. Override it if you want a different shade:

```lua
vim.api.nvim_set_hl(0, "SidekickZenBg", { bg = "#0d1522" })
```

> [!NOTE]
> The CLI view leans on sidekick internals, tested against sidekick.nvim `208e1c5`. If an update breaks something, open an issue.

## Credits

[folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) for the sidekick, [folke/zen-mode.nvim](https://github.com/folke/zen-mode.nvim) for the look.

MIT licensed.

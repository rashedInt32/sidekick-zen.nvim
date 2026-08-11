-- Minimal init for the e2e suite: plugin + sidekick.nvim on the runtimepath,
-- nothing else. Dependencies are cloned into tests/.deps on first run.
local here = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":p:h")
local root = vim.fn.fnamemodify(here, ":h")
local deps = here .. "/.deps"

local function dep(name, url, ref)
  local path = deps .. "/" .. name
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(deps, "p")
    vim.fn.system({ "git", "clone", "--filter=blob:none", url, path })
    if ref and ref ~= "" then
      vim.fn.system({ "git", "-C", path, "checkout", "--detach", ref })
    end
  end
  vim.opt.runtimepath:append(path)
  return path
end

dep("sidekick.nvim", "https://github.com/folke/sidekick.nvim", vim.env.SIDEKICK_REF)
vim.opt.runtimepath:append(root)

vim.o.swapfile = false
vim.o.confirm = false
vim.o.laststatus = 2
vim.o.scrolloff = 8 -- the setting that made the CLI input box drift

require("sidekick").setup({ nes = { enabled = false } })
require("sidekick-zen").setup({})

-- The RPC server answers while this file is still being sourced, because
-- vim.fn.system() pumps the event loop during the clone above. The runner
-- waits on this flag rather than on the socket.
vim.g.zen_test_ready = 1

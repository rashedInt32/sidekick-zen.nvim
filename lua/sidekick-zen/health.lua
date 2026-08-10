local M = {}

function M.check()
  vim.health.start("sidekick-zen.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 is required")
  end

  local ok = pcall(require, "sidekick.cli.terminal")
  if ok then
    vim.health.ok("sidekick.nvim is installed")
  else
    vim.health.warn("sidekick.nvim not found: only the code-only zen view will work", {
      "Install folke/sidekick.nvim to get the CLI view",
    })
  end
end

return M

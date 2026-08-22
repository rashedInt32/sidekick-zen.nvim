-- Matches the runtime sidekick-zen targets: nvim's LuaJIT with the `vim` API.
std = "luajit"
globals = { "vim" }
max_line_length = 120
cache = true

-- The sidekick.nvim clone the suite tests against. Third-party code.
exclude_files = { "tests/.deps" }

files["tests"] = {
  -- The runner exposes helpers.lua as a global before each spec runs.
  read_globals = { "H" },
}

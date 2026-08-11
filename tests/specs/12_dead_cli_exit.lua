-- Regression: exit called sidekick's show() unconditionally, and show() runs
-- start(), which jobstarts the tool again when the job is dead. Leaving zen
-- silently spawned a second CLI process.
local H = _G.H
H.reset()
local Z = H.zen()

H.layout()
Z.toggle()
vim.wait(400)
local t = H.term()
local job_before, buf_before = t.job, t.buf

vim.fn.jobstop(t.job)
vim.wait(900)
H.check("cli process is dead", not t:is_running())

Z.toggle()
vim.wait(900)

local after = H.term()
H.check(
  "no cli process was respawned",
  after == nil or not after:is_running(),
  "running=" .. tostring(after and after:is_running())
)
H.check(
  "no second terminal job",
  after == nil or after.job == job_before,
  "before=" .. tostring(job_before) .. " after=" .. tostring(after and after.job)
)
H.check(
  "no second terminal buffer",
  after == nil or after.buf == buf_before,
  "before=" .. tostring(buf_before) .. " after=" .. tostring(after and after.buf)
)
H.no_workspace_left()

-- The same hole exists on the way IN. find_term's fast path returns the
-- current window's session, and enter() calls show(), which jobstarts a dead
-- job. Toggling zen from a dead CLI window must not spawn a replacement.
H.layout()
local t2 = H.term()
local job2, buf2 = t2.job, t2.buf
if H.term_win() then
  vim.api.nvim_set_current_win(H.term_win())
end
vim.fn.jobstop(t2.job)
vim.wait(700)
H.check("cli is dead before entering", not t2:is_running())
Z.toggle()
vim.wait(900)
local live = H.term()
H.check(
  "entering zen did not respawn the cli",
  live == nil or (live.job == job2 and live.buf == buf2),
  "job "
    .. tostring(job2)
    .. " -> "
    .. tostring(live and live.job)
    .. ", buf "
    .. tostring(buf2)
    .. " -> "
    .. tostring(live and live.buf)
)
H.check("entered code-only", H.code_win() ~= nil)
Z.toggle()
vim.wait(600)
H.no_workspace_left()

return H.report()

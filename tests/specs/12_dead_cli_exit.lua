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

return H.report()

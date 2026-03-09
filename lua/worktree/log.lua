local config = require("worktree.config")

local M = {}

---@type string[]
M._entries = {}

local MAX_ENTRIES = 500

--- Format a timestamp for log entries.
---@return string
local function timestamp()
  return os.date("%H:%M:%S")
end

--- Add a log entry. Only stores if debug mode is enabled.
---@param level string Log level: CMD, STDOUT, STDERR, EXIT, INFO, ERROR
---@param msg string Log message
function M.log(level, msg)
  if not config.get().debug then
    return
  end

  local entry = string.format("[%s] %s: %s", timestamp(), level, msg)
  table.insert(M._entries, entry)

  -- Trim ring buffer
  if #M._entries > MAX_ENTRIES then
    local overflow = #M._entries - MAX_ENTRIES
    for _ = 1, overflow do
      table.remove(M._entries, 1)
    end
  end
end

--- Log a git command and its result.
---@param cmd string[] The command as a list of args
---@param result { code: integer, stdout: string, stderr: string }
function M.cmd(cmd, result)
  if not config.get().debug then
    return
  end

  M.log("CMD", table.concat(cmd, " "))
  M.log("EXIT", tostring(result.code))

  local stdout = result.stdout or ""
  if stdout ~= "" then
    M.log("STDOUT", stdout)
  end

  local stderr = result.stderr or ""
  if stderr ~= "" then
    M.log("STDERR", stderr)
  end
end

--- Get all log entries.
---@return string[]
function M.get_entries()
  return M._entries
end

--- Clear the log.
function M.clear()
  M._entries = {}
end

--- Open the log in a new split buffer.
function M.open()
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "worktree-log"

  local lines = M._entries
  if #lines == 0 then
    lines = { "(no log entries -- is debug mode enabled?)" }
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- q to close
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, nowait = true })
end

return M

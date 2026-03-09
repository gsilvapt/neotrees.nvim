local log = require("worktree.log")

local M = {}

---@class GitResult
---@field ok boolean Whether the command succeeded (exit code 0)
---@field stdout string Standard output
---@field stderr string Standard error
---@field code integer Exit code

---@class WorktreeEntry
---@field path string Absolute path to the worktree
---@field branch string Branch name (or "HEAD detached" for detached)
---@field head string Short commit hash
---@field bare boolean Whether this is the bare repo entry

--- Execute a git command synchronously.
--- All git commands go through this function for consistent logging and error handling.
---@param args string[] Arguments to pass to git (without "git" itself)
---@param opts? { cwd?: string, timeout?: integer } Optional cwd and timeout
---@return GitResult
function M.exec(args, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ "git" }, args)
  local timeout = opts.timeout or 30000

  local result = vim.system(cmd, {
    text = true,
    cwd = opts.cwd,
    timeout = timeout,
  }):wait()

  local git_result = {
    ok = result.code == 0,
    stdout = vim.trim(result.stdout or ""),
    stderr = vim.trim(result.stderr or ""),
    code = result.code,
  }

  log.cmd(cmd, git_result)
  return git_result
end

--- Get the toplevel directory of the current git repo.
---@return string? path Absolute path, or nil on failure
function M.toplevel()
  local result = M.exec({ "rev-parse", "--show-toplevel" })
  if result.ok then
    return result.stdout
  end
  return nil
end

--- Get the git common directory (works for both bare and non-bare repos).
---@return string? path Absolute path, or nil on failure
function M.common_dir()
  local result = M.exec({ "rev-parse", "--path-format=absolute", "--git-common-dir" })
  if result.ok then
    return result.stdout
  end
  return nil
end

--- Parse `git worktree list --porcelain` output into structured entries.
---@param raw string The raw porcelain output
---@return WorktreeEntry[]
local function parse_porcelain(raw)
  local entries = {}
  local current = {}

  for line in raw:gmatch("[^\n]+") do
    if line:match("^worktree ") then
      current = { path = line:sub(10) }
    elseif line:match("^HEAD ") then
      current.head = line:sub(6, 12) -- short hash (7 chars)
    elseif line:match("^branch ") then
      -- "refs/heads/main" -> "main"
      local branch = line:sub(8)
      branch = branch:gsub("^refs/heads/", "")
      current.branch = branch
    elseif line == "bare" then
      current.bare = true
      current.branch = current.branch or "(bare)"
    elseif line == "detached" then
      current.branch = "(detached)"
    elseif line == "" then
      -- Empty line separates entries
      if current.path then
        current.bare = current.bare or false
        table.insert(entries, current)
      end
      current = {}
    end
  end

  -- Handle last entry if no trailing newline
  if current.path then
    current.bare = current.bare or false
    table.insert(entries, current)
  end

  return entries
end

--- List all worktrees.
---@return WorktreeEntry[]
function M.list()
  local result = M.exec({ "worktree", "list", "--porcelain" })
  if not result.ok then
    log.log("ERROR", "Failed to list worktrees: " .. result.stderr)
    return {}
  end
  return parse_porcelain(result.stdout)
end

--- Add a new worktree.
---@param path string Filesystem path for the new worktree
---@param branch string Branch name
---@param create_branch boolean Whether to create a new branch (-b flag)
---@return GitResult
function M.add(path, branch, create_branch)
  local args = { "worktree", "add" }
  if create_branch then
    vim.list_extend(args, { "-b", branch, path })
  else
    vim.list_extend(args, { path, branch })
  end
  return M.exec(args)
end

--- Remove a worktree.
---@param path string Filesystem path of the worktree to remove
---@param force? boolean Whether to force removal (--force)
---@return GitResult
function M.remove(path, force)
  local args = { "worktree", "remove", path }
  if force then
    table.insert(args, 3, "--force")
  end
  return M.exec(args)
end

--- Fetch from remote.
---@param remote? string Remote name (defaults to "origin")
---@return GitResult
function M.fetch(remote)
  return M.exec({ "fetch", remote or "origin" })
end

--- Pull a specific branch from origin.
---@param branch string Branch to pull
---@return GitResult
function M.pull(branch)
  return M.exec({ "pull", "origin", branch })
end

--- Check if a local branch exists.
---@param name string Branch name
---@return boolean
function M.branch_exists(name)
  local result = M.exec({ "branch", "--list", name })
  return result.ok and result.stdout ~= ""
end

--- Check if a remote branch exists.
---@param name string Branch name (without remote prefix)
---@param remote? string Remote name (defaults to "origin")
---@return boolean
function M.remote_branch_exists(name, remote)
  remote = remote or "origin"
  local result = M.exec({ "branch", "-r", "--list", remote .. "/" .. name })
  return result.ok and result.stdout ~= ""
end

--- Get short status for a worktree path.
---@param path string Worktree path
---@return string status Human-readable status ("clean", "N modified", etc.)
function M.status(path)
  local result = M.exec({ "-C", path, "status", "--porcelain" })
  if not result.ok then
    return "unknown"
  end
  if result.stdout == "" then
    return "clean"
  end

  local count = 0
  for _ in result.stdout:gmatch("[^\n]+") do
    count = count + 1
  end
  return tostring(count) .. " modified"
end

--- Get the last commit summary for a worktree path.
---@param path string Worktree path
---@return string summary One-line commit summary, or empty string
function M.log_short(path)
  local result = M.exec({ "-C", path, "log", "--oneline", "-1" })
  if result.ok then
    return result.stdout
  end
  return ""
end

--- Get the current branch name.
---@return string? branch Current branch name, or nil if detached/error
function M.current_branch()
  local result = M.exec({ "rev-parse", "--abbrev-ref", "HEAD" })
  if result.ok and result.stdout ~= "HEAD" then
    return result.stdout
  end
  return nil
end

--- Get the current worktree path (the one neovim is inside of).
---@return string? path Absolute path, or nil on failure
function M.current_worktree_path()
  local result = M.exec({ "rev-parse", "--show-toplevel" })
  if result.ok then
    return result.stdout
  end
  return nil
end

return M

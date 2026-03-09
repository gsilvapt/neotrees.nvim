local config = require("worktree.config")
local git = require("worktree.git")
local ui = require("worktree.ui")
local log = require("worktree.log")

local M = {}

--- Get the repository directory name (e.g., "worktrees.nvim" from "/home/user/worktrees.nvim").
--- Uses the first worktree's path (the main checkout) as the canonical repo name.
---@return string repo_name
local function repo_name()
  local toplevel = git.toplevel()
  if toplevel then
    return vim.fn.fnamemodify(toplevel, ":t")
  end
  -- Fallback: use cwd basename
  return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
end

--- Run the after_create hook in the new worktree directory.
---@param path string Worktree path
---@param branch string Branch name
local function run_after_create(path, branch)
  local after = config.get().after_create
  if not after then
    return
  end

  log.log("INFO", "Running after_create hook in " .. path)

  if type(after) == "function" then
    local ok, err = pcall(after, path, branch)
    if not ok then
      log.log("ERROR", "after_create function failed: " .. tostring(err))
      vim.notify("worktree: after_create hook failed: " .. tostring(err), vim.log.levels.ERROR)
    end
    return
  end

  -- String or list of strings: execute as shell commands
  local commands = type(after) == "table" and after or { after }
  for _, cmd in ipairs(commands) do
    log.log("INFO", "Running: " .. cmd)
    local result = vim.system({ "sh", "-c", cmd }, {
      text = true,
      cwd = path,
    }):wait()

    log.cmd({ "sh", "-c", cmd }, {
      code = result.code,
      stdout = result.stdout or "",
      stderr = result.stderr or "",
    })

    if result.code ~= 0 then
      vim.notify(
        string.format("worktree: after_create command failed: %s\n%s", cmd, result.stderr or ""),
        vim.log.levels.WARN
      )
    end
  end
end

--- Switch to a worktree: change directory, wipe old buffers, open new root.
---@param entry WorktreeEntry
local function do_switch(entry)
  local old_path = git.current_worktree_path()

  log.log("INFO", "Switching to worktree: " .. entry.path)

  -- Change working directory
  vim.cmd("cd " .. vim.fn.fnameescape(entry.path))

  -- Wipe buffers that belong to the old worktree
  if old_path then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname ~= "" and bufname:find(old_path, 1, true) == 1 then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
    end
  end

  -- Open netrw at new root
  vim.cmd.edit(entry.path)

  vim.notify("worktree: switched to " .. entry.branch, vim.log.levels.INFO)
end

--- Prompt user to create a new worktree.
local function do_add()
  vim.ui.input({ prompt = "Branch name: " }, function(branch)
    if not branch or branch == "" then
      return
    end

    local cfg = config.get()
    local path

    local rname = repo_name()

    if cfg.prompt_for_path then
      -- Synchronous second prompt
      vim.ui.input({
        prompt = "Worktree path: ",
        default = cfg.path_from_branch(branch, rname),
      }, function(input_path)
        if not input_path or input_path == "" then
          return
        end
        path = input_path
      end)

      if not path then
        return
      end
    else
      path = cfg.path_from_branch(branch, rname)
    end

    -- Resolve path relative to the git common dir's parent
    if not path:match("^/") then
      local common = git.common_dir()
      if common then
        -- Common dir is usually .git or the bare repo dir; go up one level
        local parent = vim.fn.fnamemodify(common, ":h")
        path = parent .. "/" .. path
      end
    end

    vim.notify("worktree: creating worktree for branch '" .. branch .. "'...", vim.log.levels.INFO)

    -- Fetch + pull base branch if configured
    if cfg.fetch_before_create then
      log.log("INFO", "Fetching before create (base_branch=" .. cfg.base_branch .. ")")
      local fetch_result = git.fetch()
      if not fetch_result.ok then
        vim.notify("worktree: fetch failed: " .. fetch_result.stderr, vim.log.levels.WARN)
        -- Continue anyway; the branch might exist locally
      end
    end

    -- Determine whether to create new branch or use existing
    local create_branch = not git.branch_exists(branch) and not git.remote_branch_exists(branch)

    local result = git.add(path, branch, create_branch)
    if not result.ok then
      vim.notify("worktree: failed to add worktree: " .. result.stderr, vim.log.levels.ERROR)
      return
    end

    vim.notify("worktree: created worktree at " .. path, vim.log.levels.INFO)

    -- Run after_create hook
    run_after_create(path, branch)

    -- Refresh the UI if still open
    ui.refresh()
  end)
end

--- Prompt user to confirm and delete a worktree.
---@param entry WorktreeEntry
local function do_delete(entry)
  local current_path = git.current_worktree_path()
  if current_path and entry.path == current_path then
    vim.notify("worktree: cannot delete the current worktree (switch first)", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({
    prompt = string.format("Delete worktree '%s' at %s? (y/N): ", entry.branch, entry.path),
  }, function(answer)
    if not answer or answer:lower() ~= "y" then
      vim.notify("worktree: deletion cancelled", vim.log.levels.INFO)
      return
    end

    log.log("INFO", "Deleting worktree: " .. entry.path)

    local result = git.remove(entry.path, false)
    if not result.ok then
      -- Offer force deletion
      vim.ui.input({
        prompt = "Removal failed (" .. result.stderr .. "). Force delete? (y/N): ",
      }, function(force_answer)
        if not force_answer or force_answer:lower() ~= "y" then
          return
        end

        local force_result = git.remove(entry.path, true)
        if not force_result.ok then
          vim.notify("worktree: force delete failed: " .. force_result.stderr, vim.log.levels.ERROR)
          return
        end

        vim.notify("worktree: deleted (forced) " .. entry.path, vim.log.levels.INFO)
        ui.refresh()
      end)
      return
    end

    vim.notify("worktree: deleted " .. entry.path, vim.log.levels.INFO)
    ui.refresh()
  end)
end

--- Set up the plugin with user options.
---@param opts? table User configuration (see WorktreeConfig)
function M.setup(opts)
  config.setup(opts)
  log.log("INFO", "worktree.nvim loaded")
end

--- Open the worktree manager floating window.
function M.open()
  ui.open(function(entry)
    ui.close()
    do_switch(entry)
  end, function()
    do_add()
  end, function(entry)
    do_delete(entry)
  end)
end

--- Programmatic API: create a worktree.
---@param branch string Branch name
---@param path? string Filesystem path (auto-derived if nil)
function M.create(branch, path)
  if not branch or branch == "" then
    vim.notify("worktree: branch name is required", vim.log.levels.ERROR)
    return
  end

  local cfg = config.get()
  path = path or cfg.path_from_branch(branch, repo_name())

  -- Resolve relative path
  if not path:match("^/") then
    local common = git.common_dir()
    if common then
      local parent = vim.fn.fnamemodify(common, ":h")
      path = parent .. "/" .. path
    end
  end

  if cfg.fetch_before_create then
    git.fetch()
  end

  local create_branch = not git.branch_exists(branch) and not git.remote_branch_exists(branch)
  local result = git.add(path, branch, create_branch)
  if not result.ok then
    vim.notify("worktree: failed to add worktree: " .. result.stderr, vim.log.levels.ERROR)
    return
  end

  vim.notify("worktree: created worktree at " .. path, vim.log.levels.INFO)
  run_after_create(path, branch)
end

--- Programmatic API: delete a worktree by path.
---@param path string Worktree path
function M.delete(path)
  if not path or path == "" then
    vim.notify("worktree: path is required", vim.log.levels.ERROR)
    return
  end

  local result = git.remove(path, false)
  if not result.ok then
    vim.notify("worktree: failed to delete: " .. result.stderr, vim.log.levels.ERROR)
    return
  end

  vim.notify("worktree: deleted " .. path, vim.log.levels.INFO)
end

--- Programmatic API: switch to a worktree by path.
---@param path string Worktree path
function M.switch(path)
  if not path or path == "" then
    vim.notify("worktree: path is required", vim.log.levels.ERROR)
    return
  end

  do_switch({ path = path, branch = "(direct)", head = "", bare = false })
end

--- Programmatic API: list all worktrees.
---@return WorktreeEntry[]
function M.list()
  return git.list()
end

return M

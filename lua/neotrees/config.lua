---@class NeotreesUiConfig
---@field width number Floating window width relative to editor (0.0-1.0)
---@field height number Floating window height relative to editor (0.0-1.0)
---@field border string Border style for the floating window

---@class NeotreesConfig
---@field path_from_branch fun(branch: string, repo_name: string): string Derive worktree path from branch name
---@field after_create? string|string[]|fun(path: string, branch: string) Commands to run after worktree creation
---@field fetch_before_create boolean Whether to fetch+pull before creating a worktree
---@field base_branch string Base branch to fetch/pull from before creation
---@field prompt_for_path boolean Whether to prompt for a custom path instead of auto-deriving
---@field debug boolean Debug mode: log all git commands and output
---@field ui NeotreesUiConfig Floating window configuration

local M = {}

---@type NeotreesConfig
local defaults = {
  path_from_branch = function(branch, repo_name)
    -- "feature/foo" with repo "worktrees.nvim" -> "../worktrees.nvim-foo"
    local name = branch:match("[^/]+$") or branch
    return "../" .. repo_name .. "-" .. name
  end,

  after_create = nil,
  fetch_before_create = true,
  base_branch = "main",
  prompt_for_path = false,
  debug = false,

  ui = {
    width = 0.6,
    height = 0.4,
    border = "rounded",
  },
}

---@type NeotreesConfig
M._config = vim.deepcopy(defaults)

--- Merge user options into the config.
---@param opts? table
function M.setup(opts)
  opts = opts or {}

  -- Handle vim.g.neotrees as an alternative config source
  local g_opts = vim.g.neotrees or {}
  local merged = vim.tbl_deep_extend("force", defaults, g_opts, opts)

  -- Preserve function values that vim.g can't store
  if type(opts.path_from_branch) == "function" then
    merged.path_from_branch = opts.path_from_branch
  elseif type(g_opts.path_from_branch) == "function" then
    merged.path_from_branch = g_opts.path_from_branch
  end

  if type(opts.after_create) == "function" then
    merged.after_create = opts.after_create
  elseif type(g_opts.after_create) == "function" then
    merged.after_create = g_opts.after_create
  end

  M._config = merged
end

--- Get the current config. Returns the merged config table.
---@return NeotreesConfig
function M.get()
  return M._config
end

return M

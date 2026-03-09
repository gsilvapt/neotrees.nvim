if vim.g.loaded_worktree then
  return
end
vim.g.loaded_worktree = true

vim.api.nvim_create_user_command("Neotree", function()
  require("worktree").open()
end, { desc = "Open the worktree manager" })

vim.api.nvim_create_user_command("NeotreeAdd", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local branch = args[1]
  local path = args[2]

  if not branch then
    vim.notify("worktree: branch name is required. Usage: :NeotreeAdd <branch> [path]", vim.log.levels.ERROR)
    return
  end

  require("worktree").create(branch, path)
end, {
  nargs = "+",
  desc = "Add a new git worktree",
  complete = function()
    -- Offer branch name completion from local + remote branches
    local result = vim.system(
      { "git", "branch", "-a", "--format=%(refname:short)" },
      { text = true }
    ):wait()

    if result.code ~= 0 then
      return {}
    end

    local branches = {}
    for line in result.stdout:gmatch("[^\n]+") do
      -- Strip "origin/" prefix for remote branches
      local name = line:gsub("^origin/", "")
      if name ~= "HEAD" then
        table.insert(branches, name)
      end
    end
    return branches
  end,
})

vim.api.nvim_create_user_command("NeotreeDelete", function(opts)
  local path = opts.args

  if not path or path == "" then
    vim.notify("worktree: path is required. Usage: :NeotreeDelete <path>", vim.log.levels.ERROR)
    return
  end

  require("worktree").delete(path)
end, {
  nargs = 1,
  desc = "Delete a git worktree",
  complete = function()
    -- Offer worktree path completion
    local result = vim.system(
      { "git", "worktree", "list", "--porcelain" },
      { text = true }
    ):wait()

    if result.code ~= 0 then
      return {}
    end

    local paths = {}
    for line in result.stdout:gmatch("[^\n]+") do
      if line:match("^worktree ") then
        table.insert(paths, line:sub(10))
      end
    end
    return paths
  end,
})

vim.api.nvim_create_user_command("NeotreeLog", function()
  require("worktree.log").open()
end, { desc = "Open the worktree debug log" })

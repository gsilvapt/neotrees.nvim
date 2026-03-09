# worktree.nvim

A zero-dependency Neovim plugin for managing git worktrees through a floating window interface.

Uses `vim.system()` for all git operations. No plenary.nvim, no telescope.nvim required.

## Requirements

- Neovim >= 0.10
- git >= 2.17

## Installation

### lazy.nvim

```lua
{
  "gsilvapt/worktree.nvim",
  keys = {
    { "<leader>gw", function() require("worktree").open() end, desc = "Git worktrees" },
  },
  opts = {},
}
```

### packer.nvim

```lua
use {
  "gsilvapt/worktree.nvim",
  config = function()
    require("worktree").setup()
    vim.keymap.set("n", "<leader>gw", function() require("worktree").open() end)
  end,
}
```

### Manual

Clone the repository and add it to your runtimepath:

```sh
git clone https://github.com/gsilvapt/worktree.nvim ~/.local/share/nvim/site/pack/plugins/start/worktree.nvim
```

## Usage

Open the worktree manager with `:Neotree` or your configured keymap. A floating window displays all worktrees in the current repository:

```
 Git Worktrees
 --------------------------------------------------
 * main         /home/user/project              [abc1234] clean
   feature/foo  /home/user/project-foo          [def5678] 2 modified
   fix/bar      /home/user/project-bar          [ghi9012] clean

 [a]dd  [d]elete  [Enter] switch  [r]efresh  [q]uit
```

### Window keymaps

| Key | Action |
|---|---|
| `Enter`, `l` | Switch to worktree under cursor |
| `a` | Add a new worktree (prompts for branch name) |
| `d` | Delete worktree under cursor (with confirmation) |
| `r` | Refresh the list |
| `q`, `Esc` | Close the window |

### Commands

| Command | Description |
|---|---|
| `:Neotree` | Open the worktree manager |
| `:NeotreeAdd <branch> [path]` | Create a worktree (supports tab-completion) |
| `:NeotreeDelete <path>` | Delete a worktree (supports tab-completion) |
| `:NeotreeLog` | Open the debug log buffer |

## Configuration

All options are optional. Pass them to `setup()` or set `vim.g.worktree` before the plugin loads.

```lua
require("worktree").setup({
  -- Derive worktree filesystem path from branch name.
  -- Default: "feature/foo" -> "../foo"
  path_from_branch = function(branch)
    local name = branch:match("[^/]+$") or branch
    return "../" .. name
  end,

  -- Commands to run after creating a worktree (in the new worktree directory).
  -- Accepts a string, a list of strings, or a function(path, branch).
  after_create = nil,

  -- Fetch from origin before creating a worktree.
  fetch_before_create = true,

  -- Base branch to fetch from before creation.
  base_branch = "main",

  -- Prompt for a custom path instead of auto-deriving from the branch name.
  prompt_for_path = false,

  -- Log all git commands and their output.
  debug = false,

  -- Floating window appearance.
  ui = {
    width = 0.6,    -- Relative to editor width (0.0 - 1.0)
    height = 0.4,   -- Relative to editor height (0.0 - 1.0)
    border = "rounded",
  },
})
```

### after_create examples

Run a shell command:

```lua
opts = {
  after_create = "npm install",
}
```

Run multiple commands sequentially:

```lua
opts = {
  after_create = { "go mod download", "make generate" },
}
```

Run a Lua function:

```lua
opts = {
  after_create = function(path, branch)
    vim.system({ "npm", "install" }, { cwd = path }):wait()
    vim.notify("Dependencies installed for " .. branch)
  end,
}
```

## Programmatic API

```lua
local wt = require("worktree")

wt.open()                          -- Open the floating window
wt.create("feature/foo")           -- Create worktree (path auto-derived)
wt.create("fix/bar", "../bar")     -- Create worktree at specific path
wt.delete("/home/user/project-foo") -- Delete a worktree
wt.switch("/home/user/project-foo") -- Switch to a worktree
wt.list()                          -- Returns a list of WorktreeEntry tables
```

## Debug mode

Set `debug = true` to log every git command, its exit code, stdout, and stderr. View the log with `:NeotreeLog`:

```
[12:34:56] CMD: git worktree list --porcelain
[12:34:56] EXIT: 0
[12:34:56] STDOUT: worktree /home/user/project ...
```

## License

MIT

local config = require("worktree.config")
local git = require("worktree.git")
local log = require("worktree.log")

local M = {}

---@type integer? Buffer handle for the floating window
M._buf = nil
---@type integer? Window handle for the floating window
M._win = nil
---@type WorktreeEntry[] Cached worktree entries displayed in the window
M._entries = {}
---@type integer First buffer line (0-indexed) where worktree entries start
M._entry_offset = 0

--- Calculate floating window dimensions from config ratios.
---@return { width: integer, height: integer, row: integer, col: integer }
local function window_dimensions()
  local cfg = config.get().ui
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines

  local width = math.floor(editor_w * cfg.width)
  local height = math.floor(editor_h * cfg.height)

  -- Enforce minimums
  width = math.max(width, 40)
  height = math.max(height, 8)

  local row = math.floor((editor_h - height) / 2)
  local col = math.floor((editor_w - width) / 2)

  return { width = width, height = height, row = row, col = col }
end

--- Render the worktree list into the buffer.
---@param entries WorktreeEntry[]
---@param current_path? string Path of the worktree neovim is currently inside
local function render(entries, current_path)
  if not M._buf or not vim.api.nvim_buf_is_valid(M._buf) then
    return
  end

  vim.bo[M._buf].modifiable = true

  local lines = {}
  local highlights = {}

  -- Header
  table.insert(lines, " Git Worktrees")
  table.insert(lines, " " .. string.rep("-", 50))

  M._entry_offset = #lines -- entries start after header lines

  if #entries == 0 then
    table.insert(lines, "  (no worktrees found)")
  else
    -- Calculate column widths for alignment
    local max_branch = 0
    local max_path = 0
    for _, entry in ipairs(entries) do
      if not entry.bare then
        max_branch = math.max(max_branch, #(entry.branch or ""))
        max_path = math.max(max_path, #(entry.path or ""))
      end
    end

    for i, entry in ipairs(entries) do
      if not entry.bare then
        local marker = "  "
        if current_path and entry.path == current_path then
          marker = "* "
        end

        local branch = entry.branch or "(unknown)"
        local path = entry.path or ""
        local head = entry.head or ""

        -- Fetch status for non-bare entries
        local status = git.status(entry.path)

        local line = string.format(
          " %s%-" .. max_branch .. "s  %-" .. max_path .. "s  [%s] %s",
          marker,
          branch,
          path,
          head,
          status
        )
        table.insert(lines, line)

        -- Track highlights for current worktree marker
        if marker == "* " then
          table.insert(highlights, {
            line = M._entry_offset + i - 1, -- 0-indexed
            col_start = 1,
            col_end = 2,
            hl_group = "WarningMsg",
          })
        end
      end
    end
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, " [a]dd  [d]elete  [Enter] switch  [r]efresh  [q]uit")

  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("worktree")
  vim.api.nvim_buf_clear_namespace(M._buf, ns, 0, -1)

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(M._buf, ns, hl.hl_group, hl.line, hl.col_start, hl.col_end)
  end

  -- Highlight the header
  vim.api.nvim_buf_add_highlight(M._buf, ns, "Title", 0, 0, -1)

  -- Highlight the footer keybindings
  local footer_line = #lines - 1
  vim.api.nvim_buf_add_highlight(M._buf, ns, "Comment", footer_line, 0, -1)
end

--- Get the worktree entry under the cursor.
---@return WorktreeEntry?
local function entry_under_cursor()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(M._win)
  local line = cursor[1] -- 1-indexed

  -- Non-bare entries are stored sequentially after the header offset
  local entry_idx = line - M._entry_offset
  local non_bare = {}
  for _, entry in ipairs(M._entries) do
    if not entry.bare then
      table.insert(non_bare, entry)
    end
  end

  if entry_idx >= 1 and entry_idx <= #non_bare then
    return non_bare[entry_idx]
  end
  return nil
end

--- Close the floating window.
function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
  end
  if M._buf and vim.api.nvim_buf_is_valid(M._buf) then
    vim.api.nvim_buf_delete(M._buf, { force = true })
  end
  M._win = nil
  M._buf = nil
  M._entries = {}
end

--- Refresh the worktree list in the existing window.
function M.refresh()
  M._entries = git.list()
  local current_path = git.current_worktree_path()
  render(M._entries, current_path)

  -- Place cursor on first entry line
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    local first_entry_line = M._entry_offset + 1
    local line_count = vim.api.nvim_buf_line_count(M._buf)
    if first_entry_line <= line_count then
      vim.api.nvim_win_set_cursor(M._win, { first_entry_line, 0 })
    end
  end
end

--- Clamp the cursor to only worktree entry lines.
local function clamp_cursor()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(M._win)
  local line = cursor[1]

  local non_bare_count = 0
  for _, entry in ipairs(M._entries) do
    if not entry.bare then
      non_bare_count = non_bare_count + 1
    end
  end

  local first = M._entry_offset + 1
  local last = M._entry_offset + non_bare_count

  if non_bare_count == 0 then
    return
  end

  if line < first then
    vim.api.nvim_win_set_cursor(M._win, { first, 0 })
  elseif line > last then
    vim.api.nvim_win_set_cursor(M._win, { last, 0 })
  end
end

--- Set up buffer-local keymaps for the floating window.
---@param on_switch fun(entry: WorktreeEntry) Callback when user switches worktree
---@param on_add fun() Callback when user wants to add a worktree
---@param on_delete fun(entry: WorktreeEntry) Callback when user wants to delete a worktree
local function set_keymaps(on_switch, on_add, on_delete)
  local buf = M._buf
  local map_opts = { buffer = buf, nowait = true, silent = true }

  -- Close
  vim.keymap.set("n", "q", M.close, map_opts)
  vim.keymap.set("n", "<Esc>", M.close, map_opts)

  -- Switch to worktree under cursor
  vim.keymap.set("n", "<CR>", function()
    local entry = entry_under_cursor()
    if entry then
      on_switch(entry)
    end
  end, map_opts)

  vim.keymap.set("n", "l", function()
    local entry = entry_under_cursor()
    if entry then
      on_switch(entry)
    end
  end, map_opts)

  -- Add worktree
  vim.keymap.set("n", "a", function()
    on_add()
  end, map_opts)

  -- Delete worktree under cursor
  vim.keymap.set("n", "d", function()
    local entry = entry_under_cursor()
    if entry then
      on_delete(entry)
    end
  end, map_opts)

  -- Refresh
  vim.keymap.set("n", "r", function()
    M.refresh()
  end, map_opts)

  -- Clamp cursor on movement so it stays within entry lines
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = clamp_cursor,
  })
end

--- Open the floating worktree window.
---@param on_switch fun(entry: WorktreeEntry) Callback when user switches worktree
---@param on_add fun() Callback when user wants to add a worktree
---@param on_delete fun(entry: WorktreeEntry) Callback when user wants to delete a worktree
function M.open(on_switch, on_add, on_delete)
  -- Close existing window if open
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M.close()
  end

  local dim = window_dimensions()

  -- Create scratch buffer
  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].buftype = "nofile"
  vim.bo[M._buf].bufhidden = "wipe"
  vim.bo[M._buf].swapfile = false
  vim.bo[M._buf].filetype = "worktree"

  -- Open floating window
  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative = "editor",
    width = dim.width,
    height = dim.height,
    row = dim.row,
    col = dim.col,
    style = "minimal",
    border = config.get().ui.border,
    title = " Worktrees ",
    title_pos = "center",
  })

  -- Window-local options
  vim.wo[M._win].cursorline = true
  vim.wo[M._win].number = false
  vim.wo[M._win].relativenumber = false
  vim.wo[M._win].signcolumn = "no"

  -- Set up keymaps
  set_keymaps(on_switch, on_add, on_delete)

  -- Close window when buffer is left
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = M._buf,
    once = true,
    callback = function()
      -- Schedule to avoid issues with closing during event processing
      vim.schedule(M.close)
    end,
  })

  -- Populate the list
  M.refresh()

  log.log("INFO", "Worktree window opened")
end

return M

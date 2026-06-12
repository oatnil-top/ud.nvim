local M = {}

--- Default configuration
M.defaults = {
  -- Path to ud binary (default: finds in $PATH)
  ud_bin = "ud",

  -- Local sync directory (required — user must set this)
  sync_dir = nil,

  -- Auto-sync on save for files in sync_dir
  auto_sync = true,

  -- Start watch mode on setup
  watch = false,

  -- Poll interval for watch mode
  watch_interval = "30s",

  -- Create sync dir if it doesn't exist
  create_dir = true,

  -- Default frontmatter fields for new tasks
  defaults = {
    status = "todo",
    tags = {},
    board = nil,
    project = nil,
  },

  -- Key mappings (set to false to disable)
  keymaps = {
    sync = "<leader>us",
    new_task = "<leader>ut",
    new_note = "<leader>un",
    browse = "<leader>uo",
  },
}

--- Active configuration (merged with user overrides)
M.options = {}

--- Merge user config with defaults
---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- Expand ~ in sync_dir
  if M.options.sync_dir then
    M.options.sync_dir = vim.fn.expand(M.options.sync_dir)
  end
end

--- Get the resolved sync directory path.
--- Returns nil with a warning if not configured.
---@return string|nil
function M.get_sync_dir()
  local dir = M.options.sync_dir
  if not dir or dir == "" then
    vim.notify("ud: sync_dir not configured. Call require('ud').setup({ sync_dir = '~/ud-sync' })", vim.log.levels.ERROR)
    return nil
  end
  return dir
end

return M

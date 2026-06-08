local M = {}

--- Default configuration
M.defaults = {
  -- Path to ud binary (default: finds in $PATH)
  ud_bin = "ud",

  -- Default frontmatter fields for new tasks
  defaults = {
    status = "todo",
    tags = {},
    board = nil,
    project = nil,
  },

  -- Key mappings (set to false to disable)
  keymaps = {
    apply_task = "<leader>ut",
    apply_note = "<leader>un",
  },
}

--- Active configuration (merged with user overrides)
M.options = {}

--- Merge user config with defaults
---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M

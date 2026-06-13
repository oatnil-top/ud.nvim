local config = require("ud.config")
local health = require("ud.health")
local sync = require("ud.sync")
local files = require("ud.files")

local M = {}

-- Autocmd group for auto-sync
local augroup = vim.api.nvim_create_augroup("ud_nvim", { clear = true })

--- Setup the ud.nvim plugin.
---@param opts table|nil User configuration overrides (sync_dir is required)
function M.setup(opts)
  config.setup(opts)

  -- Check CLI availability
  if not health.check_cli() then
    return
  end

  -- Register commands
  vim.api.nvim_create_user_command("UdSync", function(cmd_opts)
    local arg = cmd_opts.args
    if arg == "full" then
      sync.sync({ full = true })
    elseif arg == "push" then
      sync.sync({ push = true })
    else
      sync.sync()
    end
  end, {
    desc = "Run ud local-sync (args: full, push)",
    nargs = "?",
    complete = function()
      return { "full", "push" }
    end,
  })

  vim.api.nvim_create_user_command("UdSyncWatch", function()
    sync.watch_start()
  end, {
    desc = "Start ud local-sync watch mode",
  })

  vim.api.nvim_create_user_command("UdSyncStop", function()
    sync.watch_stop()
  end, {
    desc = "Stop ud local-sync watch mode",
  })

  vim.api.nvim_create_user_command("UdList", function(cmd_opts)
    local status = cmd_opts.args
    if status == "" then
      status = nil
    end
    files.browse({ status = status })
  end, {
    desc = "Browse tasks in sync dir",
    nargs = "?",
    complete = function()
      return { "todo", "in-progress", "pending", "done" }
    end,
  })

  vim.api.nvim_create_user_command("UdOpen", function(cmd_opts)
    local task_id = cmd_opts.args
    if task_id and task_id ~= "" then
      files.open(task_id)
    else
      files.browse()
    end
  end, {
    desc = "Open a task by ID or browse",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("UdNewTask", function(cmd_opts)
    local title = cmd_opts.args
    if title == "" then
      title = nil
    end
    files.new_task({ title = title })
  end, {
    desc = "Create a new task file in sync dir",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("UdNewNote", function()
    files.new_note()
  end, {
    desc = "Create a note linked to the current task",
  })

  vim.api.nvim_create_user_command("UdExplore", function()
    files.explore()
  end, {
    desc = "Set cwd to sync dir for file explorer",
  })

  -- Set up keymaps
  local keymaps = config.options.keymaps
  if keymaps then
    if keymaps.sync then
      vim.keymap.set("n", keymaps.sync, function()
        sync.sync()
      end, { desc = "ud: Sync" })
    end

    if keymaps.new_task then
      vim.keymap.set("n", keymaps.new_task, function()
        files.new_task()
      end, { desc = "ud: New task" })
    end

    if keymaps.new_note then
      vim.keymap.set("n", keymaps.new_note, function()
        files.new_note()
      end, { desc = "ud: New note on current task" })
    end

    if keymaps.browse then
      vim.keymap.set("n", keymaps.browse, function()
        files.browse()
      end, { desc = "ud: Browse tasks" })
    end
  end

  -- Auto-sync on save: trigger push when saving .md files in sync_dir
  if config.options.auto_sync and config.options.sync_dir then
    local sync_dir_pattern = vim.fn.escape(config.options.sync_dir, "\\") .. "/*.md"

    vim.api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      pattern = sync_dir_pattern,
      callback = function(ev)
        sync.apply_file(ev.match)
      end,
    })
  end

  -- Auto-start watch mode if configured
  if config.options.watch then
    -- Defer to avoid blocking startup
    vim.defer_fn(function()
      sync.watch_start()
    end, 100)
  end

  -- Stop watch on VimLeave
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      if sync.is_watching() then
        sync.watch_stop()
      end
    end,
  })
end

return M

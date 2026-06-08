local config = require("ud.config")

local M = {}

--- Run a ud CLI command and return stdout lines via callback.
---@param args string[] CLI arguments (e.g., {"describe", "task", id, "-o", "apply"})
---@param callback fun(ok: boolean, lines: string[])
function M.run_cmd(args, callback)
  local ud_bin = config.options.ud_bin or "ud"
  local cmd = { ud_bin }
  for _, a in ipairs(args) do
    table.insert(cmd, a)
  end

  local stdout_chunks = {}
  local stderr_chunks = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          table.insert(stdout_chunks, line)
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_chunks, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          callback(true, stdout_chunks)
        else
          callback(false, stderr_chunks)
        end
      end)
    end,
  })
end

--- Open a task in an editable buffer.
--- Fetches `ud describe task <id> -o apply` and loads into a scratch buffer.
--- The user can edit and run :UdApplyTask to update.
---@param task_id string
function M.open_task(task_id)
  M.run_cmd({ "describe", "task", task_id, "-o", "apply" }, function(ok, lines)
    if not ok then
      vim.notify("ud: " .. table.concat(lines, "\n"), vim.log.levels.ERROR)
      return
    end

    -- Remove trailing empty line from jobstart output
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end

    -- Resolve short ID from frontmatter for buffer naming
    local full_id = task_id
    for _, line in ipairs(lines) do
      local id_match = line:match("^id:%s*(.+)$")
      if id_match then
        full_id = id_match
        break
      end
    end
    local short_id = full_id:sub(1, 8)

    -- Reuse existing buffer if already open
    local bufname = "ud://task/" .. short_id
    local existing_buf = vim.fn.bufnr(bufname)
    if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
      -- Switch to existing buffer and refresh content
      vim.api.nvim_set_current_buf(existing_buf)
      vim.api.nvim_buf_set_lines(existing_buf, 0, -1, false, lines)
      vim.bo[existing_buf].modified = false
      vim.notify("ud: refreshed task " .. short_id, vim.log.levels.INFO)
      return
    end

    -- Create new scratch buffer
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, bufname)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Buffer settings
    vim.bo[buf].buftype = "acwrite" -- writable scratch: triggers BufWriteCmd
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modified = false

    -- Switch to the buffer
    vim.api.nvim_set_current_buf(buf)

    -- Auto-apply on :w via BufWriteCmd
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        local apply = require("ud.apply")
        apply.apply_task()
        -- Mark as saved after apply kicks off
        vim.bo[buf].modified = false
      end,
    })

    vim.notify("ud: opened task " .. short_id .. " — :w to apply changes", vim.log.levels.INFO)
  end)
end

--- List tasks and let user pick one to open.
---@param opts? { status?: string }
function M.list_tasks(opts)
  opts = opts or {}

  local args = { "get", "tasks", "--all" }
  if opts.status then
    table.insert(args, "--status")
    table.insert(args, opts.status)
  end

  M.run_cmd(args, function(ok, lines)
    if not ok then
      vim.notify("ud: " .. table.concat(lines, "\n"), vim.log.levels.ERROR)
      return
    end

    -- Parse task list lines: "[<id>] <status> <title>"
    local items = {}
    for _, line in ipairs(lines) do
      -- Match the ud get tasks output format
      local id, rest = line:match("^%[(%x+)%]%s+(.+)$")
      if id then
        table.insert(items, { id = id, display = line })
      end
    end

    if #items == 0 then
      vim.notify("ud: no tasks found", vim.log.levels.WARN)
      return
    end

    vim.ui.select(items, {
      prompt = "Select task to open:",
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      if choice then
        M.open_task(choice.id)
      end
    end)
  end)
end

return M

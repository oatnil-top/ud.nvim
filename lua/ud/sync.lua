local config = require("ud.config")

local M = {}

-- Job ID for the watch mode background process
M._watch_job = nil

--- Run a ud CLI command asynchronously.
---@param args string[] CLI arguments
---@param callback fun(ok: boolean, output: string)
function M.run(args, callback)
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
          if line ~= "" then
            table.insert(stdout_chunks, line)
          end
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
          callback(true, table.concat(stdout_chunks, "\n"))
        else
          local err = table.concat(stderr_chunks, "\n")
          if err == "" then
            err = table.concat(stdout_chunks, "\n")
          end
          callback(false, err)
        end
      end)
    end,
  })
end

--- Run a one-shot local-sync (pull + push).
---@param opts? { full?: boolean, push?: boolean, on_done?: fun(ok: boolean) }
function M.sync(opts)
  opts = opts or {}
  local sync_dir = config.get_sync_dir()
  if not sync_dir then
    return
  end

  local args = { "local-sync" }

  if config.options.create_dir then
    table.insert(args, "--create-dir")
  end

  if opts.full then
    table.insert(args, "--full")
  elseif opts.push then
    table.insert(args, "--push")
  end

  -- Auto-resolve conflicts keeping local (non-interactive)
  table.insert(args, "--keep-local")

  table.insert(args, sync_dir)

  vim.notify("ud: syncing...", vim.log.levels.INFO)

  M.run(args, function(ok, output)
    if ok then
      -- Parse summary line from output
      local summary = output:match("Sync complete: (.+)")
      if summary then
        vim.notify("ud: " .. summary, vim.log.levels.INFO)
      else
        vim.notify("ud: sync complete", vim.log.levels.INFO)
      end
    else
      vim.notify("ud: sync failed — " .. output, vim.log.levels.ERROR)
    end
    if opts.on_done then
      opts.on_done(ok)
    end
  end)
end

--- Start watch mode (background continuous sync).
function M.watch_start()
  if M._watch_job then
    vim.notify("ud: watch already running (job " .. M._watch_job .. ")", vim.log.levels.WARN)
    return
  end

  local sync_dir = config.get_sync_dir()
  if not sync_dir then
    return
  end

  local ud_bin = config.options.ud_bin or "ud"
  local interval = config.options.watch_interval or "30s"

  local cmd = { ud_bin, "local-sync", "--watch", "--interval", interval, "--keep-local" }

  if config.options.create_dir then
    table.insert(cmd, "--create-dir")
  end

  table.insert(cmd, sync_dir)

  M._watch_job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line == "" then
            goto continue
          end
          -- Show sync summary with counts (skip "nothing to sync")
          local summary = line:match("^Sync complete: (.+)$")
          if summary and not summary:match("nothing to sync") then
            vim.schedule(function()
              vim.notify("ud: " .. summary, vim.log.levels.INFO)
            end)
          end
          ::continue::
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.schedule(function()
              vim.notify("ud watch: " .. line, vim.log.levels.WARN)
            end)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        M._watch_job = nil
        if exit_code ~= 0 then
          vim.notify("ud: watch stopped (exit " .. exit_code .. ")", vim.log.levels.WARN)
        else
          vim.notify("ud: watch stopped", vim.log.levels.INFO)
        end
      end)
    end,
  })

  if M._watch_job > 0 then
    vim.notify("ud: watch started (job " .. M._watch_job .. ")", vim.log.levels.INFO)
  else
    vim.notify("ud: failed to start watch", vim.log.levels.ERROR)
    M._watch_job = nil
  end
end

--- Stop watch mode.
function M.watch_stop()
  if not M._watch_job then
    vim.notify("ud: no watch running", vim.log.levels.WARN)
    return
  end

  vim.fn.jobstop(M._watch_job)
  -- on_exit callback will clear M._watch_job
end

--- Check if watch mode is running.
---@return boolean
function M.is_watching()
  return M._watch_job ~= nil
end

--- Apply a single file and write back server metadata.
--- Runs `ud apply -f <file>`, parses the task ID from output,
--- then `ud describe task <id> -o apply` to write back id/timestamps.
---@param filepath string absolute path to the .md file
function M.apply_file(filepath)
  M.run({ "apply", "-f", filepath }, function(ok, output)
    if not ok then
      -- Task was deleted from remote
      if output:match("Task not found") or output:match("not found") then
        local filename = vim.fn.fnamemodify(filepath, ":t")
        vim.ui.select({ "Yes, delete local file", "No, keep it" }, {
          prompt = "Task was deleted from remote. Delete \"" .. filename .. "\"?",
        }, function(choice)
          if choice and choice:match("^Yes") then
            -- Close buffer if open
            local bufnr = vim.fn.bufnr(filepath)
            if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
              vim.api.nvim_buf_delete(bufnr, { force = true })
            end
            os.remove(filepath)
            vim.notify("ud: deleted " .. filename, vim.log.levels.INFO)
          end
        end)
      else
        vim.notify("ud: apply failed — " .. output, vim.log.levels.ERROR)
      end
      return
    end

    -- Parse task ID from "Task created: <id>" or "Task updated: <id>"
    local task_id = output:match("[Tt]ask %w+: (%S+)")
    if not task_id then
      -- Could be a note: "Note created: <id>" — no write-back needed
      return
    end

    -- Fetch the canonical version with server metadata and write back
    M.run({ "describe", "task", task_id, "-o", "apply" }, function(ok2, describe_output)
      if not ok2 then
        return
      end

      -- Write back to file
      local f = io.open(filepath, "w")
      if f then
        f:write(describe_output)
        -- Ensure trailing newline
        if not describe_output:match("\n$") then
          f:write("\n")
        end
        f:close()

        -- Reload buffer if it's still open
        local bufnr = vim.fn.bufnr(filepath)
        if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("edit!")
          end)
        end
      end
    end)
  end)
end

return M

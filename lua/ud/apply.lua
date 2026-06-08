local config = require("ud.config")

local M = {}

--- Parse YAML frontmatter from lines.
--- Returns (frontmatter_table, body_start_line_index).
--- If no frontmatter found, returns (nil, 1).
---@param lines string[]
---@return table|nil, integer
function M.parse_frontmatter(lines)
  if #lines == 0 or lines[1] ~= "---" then
    return nil, 1
  end

  local end_idx = nil
  for i = 2, #lines do
    if lines[i] == "---" then
      end_idx = i
      break
    end
  end

  if not end_idx then
    return nil, 1
  end

  -- Simple YAML key-value parser (covers our frontmatter needs)
  local fm = {}
  for i = 2, end_idx - 1 do
    local line = lines[i]
    local key, value = line:match("^(%S+):%s*(.*)$")
    if key then
      -- Strip surrounding quotes
      value = value:gsub("^['\"](.+)['\"]$", "%1")
      if value == "" then
        fm[key] = true
      else
        fm[key] = value
      end
    end
  end

  return fm, end_idx + 1
end

--- Build markdown content with frontmatter for ud apply.
---@param fm table frontmatter key-value pairs
---@param body string[] body lines
---@return string
function M.build_markdown(fm, body)
  local parts = { "---" }
  for k, v in pairs(fm) do
    if type(v) == "boolean" then
      table.insert(parts, k .. ":")
    elseif type(v) == "table" then
      -- YAML list
      table.insert(parts, k .. ": [" .. table.concat(v, ", ") .. "]")
    else
      table.insert(parts, k .. ": " .. tostring(v))
    end
  end
  table.insert(parts, "---")

  for _, line in ipairs(body) do
    table.insert(parts, line)
  end

  return table.concat(parts, "\n")
end

--- Run ud apply with the given content string.
--- Calls callback(ok, output) when done.
---@param content string markdown content to pipe
---@param callback fun(ok: boolean, output: string)
function M.run_apply(content, callback)
  local ud_bin = config.options.ud_bin or "ud"
  local stdout_chunks = {}
  local stderr_chunks = {}

  -- Write content to a temp file to avoid shell escaping issues
  local tmpfile = vim.fn.tempname() .. ".md"
  local f = io.open(tmpfile, "w")
  if not f then
    callback(false, "Failed to create temp file")
    return
  end
  f:write(content)
  f:close()

  vim.fn.jobstart({ ud_bin, "apply", "-f", tmpfile }, {
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
      -- Clean up temp file
      os.remove(tmpfile)

      vim.schedule(function()
        if exit_code == 0 then
          local output = table.concat(stdout_chunks, "\n")
          callback(true, output)
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

--- Apply the current buffer as a new task.
function M.apply_task()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local existing_fm, body_start = M.parse_frontmatter(lines)
  local body = {}
  for i = body_start, #lines do
    table.insert(body, lines[i])
  end

  -- Build frontmatter: merge existing with defaults
  local fm = {}
  local defaults = config.options.defaults or {}

  -- Start with defaults
  if defaults.status then
    fm.status = defaults.status
  end
  if defaults.tags and #defaults.tags > 0 then
    fm.tags = defaults.tags
  end
  if defaults.board then
    fm.board = defaults.board
  end

  -- Override with existing frontmatter (user's values win)
  if existing_fm then
    for k, v in pairs(existing_fm) do
      fm[k] = v
    end
  end

  -- Derive title from first heading if not in frontmatter
  if not fm.title then
    for _, line in ipairs(body) do
      local heading = line:match("^#%s+(.+)$")
      if heading then
        fm.title = heading
        break
      end
    end
  end

  -- Fallback title from filename
  if not fm.title then
    local bufname = vim.fn.expand("%:t:r")
    if bufname and bufname ~= "" then
      fm.title = bufname
    end
  end

  local content = M.build_markdown(fm, body)

  M.run_apply(content, function(ok, output)
    if ok then
      vim.notify("ud: " .. output, vim.log.levels.INFO)
    else
      vim.notify("ud apply failed: " .. output, vim.log.levels.ERROR)
    end
  end)
end

--- Apply the current buffer or visual selection as a note on a task.
---@param opts? { task_id?: string, range?: { start: integer, end_: integer } }
function M.apply_note(opts)
  opts = opts or {}

  local lines
  if opts.range then
    lines = vim.api.nvim_buf_get_lines(0, opts.range.start - 1, opts.range.end_, false)
  else
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  end

  local existing_fm, body_start = M.parse_frontmatter(lines)
  local body = {}
  for i = body_start, #lines do
    table.insert(body, lines[i])
  end

  -- Determine task_id
  local task_id = opts.task_id
  if not task_id and existing_fm then
    task_id = existing_fm.task_id
  end

  if task_id then
    M._do_apply_note(task_id, existing_fm, body)
  else
    -- Prompt for task ID
    vim.ui.input({ prompt = "Task ID: " }, function(input)
      if not input or input == "" then
        vim.notify("ud: cancelled — no task ID provided", vim.log.levels.WARN)
        return
      end
      M._do_apply_note(input, existing_fm, body)
    end)
  end
end

--- Internal: build and send note apply.
---@param task_id string
---@param existing_fm table|nil
---@param body string[]
function M._do_apply_note(task_id, existing_fm, body)
  local fm = { task_id = task_id }

  -- Carry over note_id if updating
  if existing_fm and existing_fm.note_id then
    fm.note_id = existing_fm.note_id
  end

  local content = M.build_markdown(fm, body)

  M.run_apply(content, function(ok, output)
    if ok then
      vim.notify("ud: " .. output, vim.log.levels.INFO)
    else
      vim.notify("ud apply note failed: " .. output, vim.log.levels.ERROR)
    end
  end)
end

return M

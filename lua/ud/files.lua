local config = require("ud.config")

local M = {}

--- Parse YAML frontmatter from file lines.
--- Returns (frontmatter_table, body_start_line_index).
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

  local fm = {}
  for i = 2, end_idx - 1 do
    local line = lines[i]
    local key, value = line:match("^(%S+):%s*(.*)$")
    if key then
      value = value:gsub("^['\"](.+)['\"]$", "%1")
      -- Parse YAML lists: [tag1, tag2]
      local list = value:match("^%[(.*)%]$")
      if list then
        local items = {}
        for item in list:gmatch("[^,]+") do
          table.insert(items, vim.trim(item))
        end
        fm[key] = items
      elseif value == "" then
        fm[key] = true
      else
        fm[key] = value
      end
    end
  end

  return fm, end_idx + 1
end

--- Build frontmatter string for a new task file.
---@param overrides? table additional frontmatter fields
---@return string
function M.build_task_frontmatter(overrides)
  overrides = overrides or {}
  local defaults = config.options.defaults or {}

  local parts = { "---" }

  -- title
  if overrides.title then
    table.insert(parts, "title: " .. overrides.title)
  end

  -- status
  local status = overrides.status or defaults.status or "todo"
  table.insert(parts, "status: " .. status)

  -- tags
  local tags = overrides.tags or defaults.tags
  if tags and #tags > 0 then
    table.insert(parts, "tags: [" .. table.concat(tags, ", ") .. "]")
  end

  -- board
  local board = overrides.board or defaults.board
  if board then
    table.insert(parts, "board: " .. board)
  end

  table.insert(parts, "---")
  table.insert(parts, "")

  return table.concat(parts, "\n")
end

--- Build frontmatter string for a new note file.
---@param task_id string
---@param task_title string
---@return string
function M.build_note_frontmatter(task_id, task_title)
  local parts = {
    "---",
    "task_id: " .. task_id,
    "title: ",
    "---",
    "",
  }
  return table.concat(parts, "\n")
end

--- Scan sync directory for .md files and parse their frontmatter.
--- Returns a list of {path, filename, frontmatter} entries.
---@param filter? { status?: string }
---@return table[]
function M.scan_tasks(filter)
  local sync_dir = config.get_sync_dir()
  if not sync_dir then
    return {}
  end

  -- Find all .md files in sync_dir (flat, no recursion)
  local glob = sync_dir .. "/*.md"
  local files = vim.fn.glob(glob, false, true)

  local tasks = {}
  for _, filepath in ipairs(files) do
    local filename = vim.fn.fnamemodify(filepath, ":t")

    -- Skip meta files
    if filename == "UDSYNC.md" then
      goto continue
    end

    -- Read first ~20 lines to parse frontmatter
    local lines = {}
    local f = io.open(filepath, "r")
    if f then
      local n = 0
      for line in f:lines() do
        table.insert(lines, line)
        n = n + 1
        if n >= 30 then
          break
        end
      end
      f:close()
    end

    local fm = M.parse_frontmatter(lines)

    -- Skip notes (they have task_id in frontmatter)
    if fm and fm.task_id then
      goto continue
    end

    -- Apply status filter
    if filter and filter.status and fm then
      if fm.status ~= filter.status then
        goto continue
      end
    end

    local title = (fm and fm.title) or filename:gsub("%.md$", "")
    local status = (fm and fm.status) or "?"
    local id = (fm and fm.id) or ""

    table.insert(tasks, {
      path = filepath,
      filename = filename,
      title = title,
      status = status,
      id = id,
      frontmatter = fm,
    })

    ::continue::
  end

  return tasks
end

--- Find a task file by ID (full or partial).
---@param task_id string full or partial UUID
---@return table|nil task entry from scan_tasks
function M.find_by_id(task_id)
  local tasks = M.scan_tasks()
  local id_lower = task_id:lower()

  for _, task in ipairs(tasks) do
    if task.id and task.id:lower():sub(1, #id_lower) == id_lower then
      return task
    end
  end

  return nil
end

--- Browse tasks via vim.ui.select and open the chosen one.
---@param opts? { status?: string }
function M.browse(opts)
  opts = opts or {}
  local tasks = M.scan_tasks({ status = opts.status })

  if #tasks == 0 then
    vim.notify("ud: no tasks found in sync dir", vim.log.levels.WARN)
    return
  end

  -- Sort: in-progress first, then todo, then rest
  local priority = { ["in-progress"] = 1, todo = 2, pending = 3, done = 4 }
  table.sort(tasks, function(a, b)
    local pa = priority[a.status] or 99
    local pb = priority[b.status] or 99
    if pa ~= pb then
      return pa < pb
    end
    return a.title < b.title
  end)

  vim.ui.select(tasks, {
    prompt = "Select task:",
    format_item = function(item)
      local short_id = item.id ~= "" and ("[" .. item.id:sub(1, 8) .. "] ") or ""
      return short_id .. item.status .. "  " .. item.title
    end,
  }, function(choice)
    if choice then
      vim.cmd("edit " .. vim.fn.fnameescape(choice.path))
    end
  end)
end

--- Open a task by ID.
---@param task_id string
function M.open(task_id)
  local task = M.find_by_id(task_id)
  if task then
    vim.cmd("edit " .. vim.fn.fnameescape(task.path))
  else
    vim.notify("ud: task " .. task_id .. " not found in sync dir", vim.log.levels.WARN)
  end
end

--- Create a new task file in the sync dir and open it.
---@param opts? { title?: string }
function M.new_task(opts)
  opts = opts or {}
  local sync_dir = config.get_sync_dir()
  if not sync_dir then
    return
  end

  local function create(title)
    if not title or title == "" then
      title = "Untitled"
    end

    -- Sanitize filename
    local filename = title:gsub("[/\\:*?\"<>|%%!#$&'()+,;=@%[%]^{}~]", "-")
    filename = filename:gsub("%s+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
    if filename == "" then
      filename = "untitled"
    end

    local filepath = sync_dir .. "/" .. filename .. ".md"

    -- Avoid overwriting existing files
    local counter = 1
    while vim.fn.filereadable(filepath) == 1 do
      filepath = sync_dir .. "/" .. filename .. "-" .. counter .. ".md"
      counter = counter + 1
    end

    local content = M.build_task_frontmatter({ title = title })

    local f = io.open(filepath, "w")
    if not f then
      vim.notify("ud: failed to create " .. filepath, vim.log.levels.ERROR)
      return
    end
    f:write(content)
    f:close()

    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
    -- Place cursor at end of file (ready to type description)
    vim.cmd("normal! G")
  end

  if opts.title then
    create(opts.title)
  else
    vim.ui.input({ prompt = "Task title: " }, function(input)
      if input then
        create(input)
      end
    end)
  end
end

--- Create a new note file linked to the task in the current buffer.
---@param opts? { task_id?: string }
function M.new_note(opts)
  opts = opts or {}
  local sync_dir = config.get_sync_dir()
  if not sync_dir then
    return
  end

  -- Try to get task_id from current buffer's frontmatter
  local task_id = opts.task_id
  local task_title = nil

  if not task_id then
    local lines = vim.api.nvim_buf_get_lines(0, 0, 30, false)
    local fm = M.parse_frontmatter(lines)
    if fm then
      task_id = fm.id
      task_title = fm.title
    end
  end

  if not task_id then
    vim.ui.input({ prompt = "Task ID: " }, function(input)
      if input and input ~= "" then
        M.new_note({ task_id = input })
      else
        vim.notify("ud: cancelled — no task ID", vim.log.levels.WARN)
      end
    end)
    return
  end

  if not task_title then
    task_title = task_id:sub(1, 8)
  end

  -- Sanitize task title for filename
  local safe_title = task_title:gsub("[/\\:*?\"<>|%%!#$&'()+,;=@%[%]^{}~]", "-")
  safe_title = safe_title:gsub("%s+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
  if safe_title == "" then
    safe_title = "untitled"
  end

  -- Limit length
  if #safe_title > 50 then
    safe_title = safe_title:sub(1, 50)
  end

  local filename = safe_title .. "-Note.md"
  local filepath = sync_dir .. "/" .. filename

  -- Avoid overwriting
  local counter = 1
  while vim.fn.filereadable(filepath) == 1 do
    filepath = sync_dir .. "/" .. safe_title .. "-Note-" .. counter .. ".md"
    counter = counter + 1
  end

  local content = M.build_note_frontmatter(task_id, task_title)

  local f = io.open(filepath, "w")
  if not f then
    vim.notify("ud: failed to create " .. filepath, vim.log.levels.ERROR)
    return
  end
  f:write(content)
  f:close()

  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  -- Place cursor on the title line in frontmatter
  vim.cmd("normal! 3G$")
end

return M

local config = require("ud.config")
local apply = require("ud.apply")

local M = {}

--- Setup the ud.nvim plugin.
---@param opts table|nil User configuration overrides
function M.setup(opts)
  config.setup(opts)

  -- Register commands
  vim.api.nvim_create_user_command("UdApplyTask", function()
    apply.apply_task()
  end, {
    desc = "Apply current buffer as a ud task",
  })

  vim.api.nvim_create_user_command("UdApplyNote", function(cmd_opts)
    local range = nil
    if cmd_opts.range == 2 then
      range = { start = cmd_opts.line1, end_ = cmd_opts.line2 }
    end
    apply.apply_note({ range = range })
  end, {
    desc = "Apply buffer/selection as a ud note on a task",
    range = true,
  })

  -- Set up keymaps
  local keymaps = config.options.keymaps
  if keymaps then
    if keymaps.apply_task then
      vim.keymap.set("n", keymaps.apply_task, function()
        apply.apply_task()
      end, { desc = "ud: Apply buffer as task" })
    end

    if keymaps.apply_note then
      vim.keymap.set({ "n", "v" }, keymaps.apply_note, function()
        -- In visual mode, use the selection range
        local mode = vim.fn.mode()
        if mode == "v" or mode == "V" or mode == "\22" then
          -- Exit visual mode to get marks
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
          vim.schedule(function()
            local start_line = vim.fn.line("'<")
            local end_line = vim.fn.line("'>")
            apply.apply_note({ range = { start = start_line, end_ = end_line } })
          end)
        else
          apply.apply_note()
        end
      end, { desc = "ud: Apply as note" })
    end
  end
end

return M

local config = require("ud.config")

local M = {}

--- Check if the ud CLI binary is available.
---@return boolean
function M.check_cli()
  local ud_bin = config.options.ud_bin or "ud"
  local ok = vim.fn.executable(ud_bin) == 1
  if not ok then
    vim.notify("ud: CLI not found — install ud or set ud_bin in config", vim.log.levels.ERROR)
  end
  return ok
end

--- Neovim :checkhealth integration
function M.check()
  vim.health.start("ud.nvim")

  -- Check binary
  local ud_bin = config.options.ud_bin or "ud"
  if vim.fn.executable(ud_bin) == 1 then
    vim.health.ok("ud binary found: " .. ud_bin)
  else
    vim.health.error("ud binary not found: " .. ud_bin, {
      "Install ud CLI: https://github.com/oatnil/ud",
      "Or set ud_bin in require('ud').setup({ ud_bin = '/path/to/ud' })",
    })
  end

  -- Check sync_dir
  local sync_dir = config.options.sync_dir
  if sync_dir then
    if vim.fn.isdirectory(sync_dir) == 1 then
      vim.health.ok("sync_dir exists: " .. sync_dir)
    else
      vim.health.warn("sync_dir does not exist: " .. sync_dir, {
        "Run :UdSync to create it (if create_dir is enabled)",
      })
    end
  else
    vim.health.warn("sync_dir not configured", {
      "Set sync_dir in require('ud').setup({ sync_dir = '~/ud-sync' })",
    })
  end
end

return M

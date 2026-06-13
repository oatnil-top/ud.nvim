# ud.nvim

Neovim adapter for the [UnDercontrol](https://undercontrol.io) CLI. Syncs tasks as plain markdown files to a local directory using `ud local-sync`, so you can edit them with your normal Neovim workflow.

## Requirements

- Neovim >= 0.9
- [ud CLI](https://undercontrol.io) installed and configured

## Installation

### lazy.nvim

```lua
{
  "oatnil/ud-nvim",
  config = function()
    require("ud").setup({
      sync_dir = "~/ud-sync",
    })
  end,
}
```

## Configuration

```lua
require("ud").setup({
  -- Path to ud binary (default: "ud", found in $PATH)
  ud_bin = "ud",

  -- Local sync directory (required)
  sync_dir = "~/ud-sync",

  -- Auto-push on save for files in sync_dir (default: true)
  auto_sync = true,

  -- Start watch mode on setup (default: false)
  watch = false,

  -- Poll interval for watch mode (default: "30s")
  watch_interval = "30s",

  -- Create sync dir if it doesn't exist (default: true)
  create_dir = true,

  -- Default frontmatter for new tasks
  defaults = {
    status = "todo",
    tags = {},
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:UdSync [full\|push]` | Run sync. `full` pulls all tasks, `push` pushes only |
| `:UdSyncWatch` | Start background watch mode (continuous sync) |
| `:UdSyncStop` | Stop watch mode |
| `:UdList [status]` | Browse tasks, optionally filtered by status |
| `:UdOpen [id]` | Open task by ID or browse |
| `:UdNewTask [title]` | Create a new task file |
| `:UdNewNote` | Create a note linked to the task in the current buffer |
| `:UdExplore` | Set cwd to sync dir and open task browser |

## Keymaps

No keymaps are set by default. Add your own in the `keymaps` table:

```lua
require("ud").setup({
  sync_dir = "~/ud-sync",
  keymaps = {
    sync = "<leader>us",       -- trigger sync
    new_task = "<leader>ut",   -- create new task
    new_note = "<leader>un",   -- create note on current task
    browse = "<leader>uo",     -- browse tasks
  },
})
```

Or set them yourself outside the plugin:

```lua
vim.keymap.set("n", "<leader>us", "<cmd>UdSync<cr>", { desc = "ud: Sync" })
vim.keymap.set("n", "<leader>ut", "<cmd>UdNewTask<cr>", { desc = "ud: New task" })
vim.keymap.set("n", "<leader>uo", "<cmd>UdList<cr>", { desc = "ud: Browse tasks" })
```

## How it works

1. **Setup** checks that the `ud` CLI is installed
2. **`:UdSync full`** pulls all tasks as `.md` files into your sync dir
3. **Edit** the markdown files normally — YAML frontmatter holds task metadata
4. **Save** triggers an auto-push (syncs changes back to the server)
5. **`:UdSyncWatch`** starts continuous background sync
6. **Notifications** show sync counts (e.g. "3 created, 2 pushed, 5 pulled")

Tasks are plain markdown files:

```markdown
---
id: abc12345-...
title: My Task
status: todo
tags: [work, urgent]
---

Task description goes here.
```

Notes link to a parent task via `task_id`:

```markdown
---
task_id: abc12345-...
title: Progress update
---

Note content here.
```

## Health check

Run `:checkhealth ud` to verify your setup.

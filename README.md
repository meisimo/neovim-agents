# agents.nvim

A provider-neutral Neovim interface for coding-agent CLIs. The first provider is
[Claude Code](https://docs.anthropic.com/en/docs/claude-code), with an adapter boundary designed
for additional CLIs later.

The plugin runs the provider's real interactive CLI in a Neovim terminal. Conversation history
continues to belong to the provider, so sessions remain available from both Neovim and the native
CLI.

## Status

This project is an early scaffold. It currently supports starting, resuming, continuing, toggling,
and stopping a Claude Code terminal session.

## Requirements

- Neovim 0.10 or newer
- The `claude` executable installed and authenticated

## Installation

With lazy.nvim:

```lua
{
  "your-name/agents.nvim",
  opts = {},
}
```

For local development:

```lua
{
  dir = "/path/to/neovim-agents",
  name = "agents.nvim",
  opts = {},
}
```

## Configuration

Defaults are shown below:

```lua
require("agents").setup({
  default_provider = "claude",
  cwd = nil, -- nil uses Neovim's current working directory
  window = {
    position = "right", -- right, left, top, or bottom
    size = 0.4,         -- fraction of the editor, or an absolute size
  },
  mappings = {
    toggle = "<C-f><C-f>", -- Show or hide the terminal, preserving its session
    escape = "<C-f>f",     -- Enter Neovim's Terminal-Normal mode
  },
  providers = {
    claude = {
      command = "claude",
      args = {},
    },
  },
})
```

The toggle mapping works in normal buffers and in the agent terminal, but does not affect other
terminal windows. The escape mapping is local to the agent terminal. Set either value to `false`
to disable that mapping. After using the escape mapping, press `i` to send input to the agent again.

## Commands

```vim
:Agents open [provider]       " Start a new conversation
:Agents resume [session-id]   " Resume by ID; omit it for Claude's picker
:Agents continue              " Continue the latest conversation in this directory
:Agents toggle                " Show or hide the agent terminal
:Agents stop                  " Stop the terminal job and delete its buffer
:Agents health                " Check provider availability
```

The default provider is used when no provider is supplied. Run `:help agents.nvim` for the same
reference inside Neovim.

The same operations are available to mappings and other Lua code:

```lua
local agents = require("agents")

vim.keymap.set("n", "<leader>aa", agents.toggle, { desc = "Toggle coding agent" })
vim.keymap.set("n", "<leader>ac", agents.continue, { desc = "Continue coding-agent chat" })
```

## Provider contract

Each provider module exposes:

- `is_available(config)` to check its executable
- `build_command(action, options, config)` to produce an argument vector

The terminal and command layers do not contain provider-specific CLI flags. This is the boundary
future Codex or other adapters should implement.

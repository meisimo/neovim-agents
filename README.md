# agents.nvim

A provider-neutral Neovim interface for coding-agent CLIs. It currently integrates
[Claude Code](https://docs.anthropic.com/en/docs/claude-code) and
[Codex CLI](https://developers.openai.com/codex/cli/reference) behind one command and terminal
interface.

The plugin runs the provider's real interactive CLI in a Neovim terminal. Conversation history
continues to belong to the provider, so sessions remain available from both Neovim and the native
CLI.

## Status

This project is in early development. It supports starting, resuming, continuing, toggling, and
stopping native Claude Code and Codex CLI terminal sessions.

## Requirements

- Neovim 0.10 or newer
- At least one supported CLI installed and authenticated: `claude` or `codex`

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
    codex = {
      command = "codex",
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
:Agents open [provider]                    " Start a new conversation
:Agents resume [provider] [session-id]      " Resume by ID or open the native picker
:Agents continue [provider]                 " Continue the latest conversation in this directory
:Agents toggle                " Show or hide the agent terminal
:Agents stop                  " Stop the terminal job and delete its buffer
:Agents health                " Check provider availability
```

The default provider is used when no provider is supplied. For backward compatibility,
`:Agents resume <session-id>` treats an unrecognized second argument as a session ID for the
default provider. Examples:

```vim
:Agents open codex
:Agents resume codex
:Agents resume codex 019c0000-0000-0000-0000-000000000000
:Agents continue codex
:Agents resume claude my-claude-session-id
```

For Codex, `continue` uses `codex resume --last`, scoped by Codex to Neovim's current working
directory. Run `:help agents.nvim` for the same reference inside Neovim.

The same operations are available to mappings and other Lua code:

```lua
local agents = require("agents")

vim.keymap.set("n", "<leader>aa", agents.toggle, { desc = "Toggle coding agent" })
vim.keymap.set("n", "<leader>ac", agents.continue, { desc = "Continue coding-agent chat" })
```

## Provider contract

Providers are created with `require("agents.providers.adapter").new()` and expose:

- `is_available(config)` to check its executable
- `supports(action)` to advertise supported actions
- `build_command(action, options, config)` to produce an argument vector

The command and terminal layers contain no provider-specific flags. New adapters can be added to
the built-in registry or registered at runtime with
`require("agents.providers").register(name, provider)`.

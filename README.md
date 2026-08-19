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
stopping native Claude Code and Codex CLI terminal sessions, along with safe automatic refresh of
loaded file buffers changed outside Neovim and file-range references pasted into the active chat.

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
  close_on_exit = true, -- Hide the sidebar when its active CLI exits naturally
  window = {
    position = "right", -- right, left, top, or bottom
    size = 0.4,         -- fraction of the editor, or an absolute size
  },
  mappings = {
    toggle = "<C-f><C-f>", -- Show or hide the terminal, preserving its session
    escape = "<C-f>f",     -- Enter Neovim's Terminal-Normal mode
    context = "<C-f>p",    -- Paste the Visual selection's file reference
  },
  refresh = {
    enabled = true,
    events = { "BufEnter", "FocusGained", "CursorHold" },
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
terminal windows. The escape mapping is local to the agent terminal, and the context mapping works
in Visual mode. Set any value to `false` to disable that mapping. After using the escape mapping,
press `i` to send input to the agent again.

Buffer refresh asks Neovim to check loaded file buffers for external changes on the configured
events. `FocusGained` checks every loaded file buffer; the other supported events check only their
event buffer. Modified buffers and non-file buffers are skipped, so unsaved contents are never
replaced. This first version is event-driven and does not install a filesystem watcher.

## Commands

```vim
:Agents open [provider]                     " Start and select a new conversation
:Agents resume [provider] [provider-id]      " Resume by provider ID or open its native picker
:Agents continue [provider]                  " Continue the latest conversation in this directory
:Agents toggle                               " Show or hide the agent sidebar
:Agents next                                 " Select the next open chat
:Agents prev                                 " Select the previous open chat
:Agents select [session-id]                  " Select by plugin ID or open a picker
:Agents context                              " Paste the current Visual selection as a file reference
:Agents stop [session-id]                    " Stop a chat and retain its transcript
:Agents close [session-id]                   " Stop and remove a chat
:Agents health                               " Check provider availability
```

Starting or resuming a conversation creates a new plugin session without stopping existing ones.
The sidebar winbar lists sessions as `<id>:<provider>`; click a label or use the switching commands
to select one. An `x` marks a stopped or naturally exited chat. Closing the sidebar leaves all jobs
running. When an active CLI exits naturally, the sidebar is hidden by default and its transcript
remains selectable; set `close_on_exit = false` to keep it visible.

The default provider is used when no provider is supplied. For backward compatibility,
`:Agents resume <provider-session-id>` treats an unrecognized second argument as a provider
conversation ID for the default provider. Examples:

```vim
:Agents open codex
:Agents resume codex
:Agents resume codex 019c0000-0000-0000-0000-000000000000
:Agents continue codex
:Agents resume claude my-claude-session-id
```

For Codex, `continue` uses `codex resume --last`, scoped by Codex to Neovim's current working
directory. Run `:help agents.nvim` for the same reference inside Neovim.

From a characterwise or linewise Visual selection, press `<C-f>p` or run `:Agents context` to paste
a reference such as `@src/module-a/init.py:6:23-14:78` into Claude Code or
`src/module-a/init.py:6:23-14:78` into Codex. The reference is not submitted, and the sidebar is
focused so the prompt can be completed. The file must be saved, and blockwise selections are not
supported. Paths inside the session working directory are relative; other paths are absolute.

The same operations are available to mappings and other Lua code:

```lua
local agents = require("agents")

vim.keymap.set("n", "<leader>aa", agents.toggle, { desc = "Toggle coding agent" })
vim.keymap.set("n", "<leader>ac", agents.continue, { desc = "Continue coding-agent chat" })
vim.keymap.set("x", "<leader>ax", agents.context, { desc = "Add file range to agent chat" })
vim.keymap.set("n", "]a", agents.next, { desc = "Next coding-agent chat" })
vim.keymap.set("n", "[a", agents.previous, { desc = "Previous coding-agent chat" })
```

`agents.select(id)`, `agents.stop(id)`, and `agents.close(id)` accept a plugin session ID. Omitting
the ID uses the active session, except `agents.select()`, which opens the session picker.

## Provider contract

Providers are created with `require("agents.providers.adapter").new()` and expose:

- `is_available(config)` to check its executable
- `supports(action)` to advertise supported actions
- `build_command(action, options, config)` to produce an argument vector

Adapters may also set `context_prefix` when their CLI has stable file-mention syntax. Claude uses
`@`; the default and Codex use no prefix.

The command and terminal layers contain no provider-specific flags. New adapters can be added to
the built-in registry or registered at runtime with
`require("agents.providers").register(name, provider)`.

See [doc/architecture.md](doc/architecture.md) for the design behind sessions, native terminal
backends, structured backends, and planned workspace integration.

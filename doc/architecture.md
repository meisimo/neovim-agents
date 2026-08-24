# Architecture and Design

## Status

Proposed.

This document describes the intended architecture for `agents.nvim`. It is a design guide for
the features listed in [features-summary.md](features-summary.md), not a description of the current
implementation.

## Context

`agents.nvim` currently starts the real interactive CLI for a provider in a Neovim terminal. This
has an important benefit: the provider continues to own its conversation history and the user
retains the CLI's native commands, permission prompts, pickers, keybindings, and other features.

The current terminal module combines three responsibilities in a single global state:

1. The lifetime of the agent process.
2. The terminal buffer used by that process.
3. The window used as the chat sidebar.

This works for one chat, but it makes multiple chats, session switching, lifecycle handling, and
workspace integration difficult. Some planned features also need semantic information such as the
start and end of a turn. A raw terminal stream does not provide that information reliably.

Terminal user interfaces write ANSI control sequences that describe screen updates rather than a
conversation transcript. If a CLI uses an alternate screen, previous output may not exist in the
Neovim terminal buffer at all. Parsing terminal bytes is therefore not a reliable way to identify
messages, file changes, approvals, or turn completion.

## Decision

The plugin will use a hybrid architecture:

- A session-management layer will coordinate every chat.
- The native terminal will remain the default backend.
- Structured backends may be added for providers that expose a suitable machine-readable protocol.
- Features will use backend capabilities and degrade gracefully when semantic events are not
  available.
- The sidebar, workspace integration, and session state will not depend directly on a particular
  provider or process transport.

The session-management layer is not a mandatory proxy for every byte exchanged with a CLI. In
native mode, the terminal remains both the provider's input surface and its output renderer. The
manager observes its lifecycle without attempting to interpret its screen.

Structured integration is additive. It must not be required for a provider to participate in the
plugin.

## Goals

- Preserve access to native CLI functionality.
- Support multiple concurrent chats and fast switching between them.
- Keep providers with only an interactive CLI usable.
- Isolate provider-specific command flags and protocols.
- Provide reliable lifecycle events where the backend supports them.
- Keep workspace features such as buffer refresh independent of the agent provider.
- Make the session and UI layers testable with fake backends.

## Non-goals

- Defining a universal representation for every provider-specific feature.
- Parsing ANSI terminal output into semantic conversation messages.
- Reimplementing every native CLI command in Neovim.
- Attributing every filesystem modification conclusively to an agent.
- Persisting running processes across Neovim restarts. Conversation persistence remains the
  provider's responsibility.

## High-level architecture

```text
Commands and public Lua API
             |
             v
       Session Manager <--------------------+
       |                                     |
       | owns sessions and active chat       | events/actions
       |                                     |
       +--------------+----------------------+
                      |
          +-----------+------------+
          |                        |
          v                        v
     Sidebar UI             Workspace Services
     - active buffer         - buffer refresh
     - chat tabs             - change tracking
     - change list           - context references
          |
          v
        Backend
     +----+---------------------+
     |                          |
     v                          v
Native Terminal Backend   Structured Backend
- PTY passthrough         - provider protocol
- terminal buffer         - semantic events
- native CLI UI           - Neovim-rendered UI
```

## Core concepts

### Session

A session represents one open chat in the plugin. It is distinct from a provider conversation:
the plugin may not know the provider's session ID immediately, especially when running a native
interactive CLI.

A session should contain state similar to:

```lua
{
  id = "agents-local-id",
  provider = "codex",
  cwd = "/path/to/project",
  backend = backend,
  buffer = 42,
  status = "running",
  title = "Authentication refactor",
  provider_session_id = nil,
  draft = {},
  changed_files = {},
}
```

Possible session statuses are:

- `starting`
- `running`
- `idle`
- `busy`
- `stopped`
- `exited`
- `failed`

Native terminal backends use `running`, `stopped`, and `exited`; they cannot distinguish `idle`
from `busy`. Structured backends may refine a running session into `idle` and `busy` states.

### Session manager

The session manager owns the collection and ordering of sessions:

```lua
{
  sessions = {
    [session_id] = session,
  },
  order = { session_id_1, session_id_2 },
  active_id = session_id_1,
}
```

Its responsibilities are:

- Create, resume, select, stop, and close sessions.
- Select a backend through the provider configuration.
- Maintain the active session independently of sidebar visibility.
- Route backend events to the UI and workspace services.
- Keep session lifecycle separate from buffer and window lifecycle.

Commands should call the session manager rather than opening a terminal directly.

### Provider

A provider describes how a particular agent is launched and which backends it offers. The current
provider contract for availability checks, supported actions, and command construction remains
useful for native mode.

A provider may additionally create a structured backend:

```lua
{
  name = "codex",
  build_command = function(...) end,
  create_structured_backend = function(...) end, -- optional
}
```

Providers are not required to implement structured integration. A new or unknown provider should
be usable by implementing only native command construction.

### Backend

A backend is one execution strategy for a provider. Backend capabilities, rather than the provider
name, determine which UI behavior is available. This matters because the native and structured
backends for the same provider have different abilities.

A conceptual backend interface is:

```lua
backend:start()
backend:send(text)
backend:interrupt()
backend:stop()
backend:capabilities()
backend:on_event(callback)
```

Not every operation must be supported. Unsupported operations should be represented by
capabilities and should return a clear error if invoked.

Example capabilities:

```lua
{
  native_ui = true,
  structured_output = false,
  turn_events = false,
  approvals = false,
  file_events = false,
  interrupt = true,
}
```

#### Native terminal backend

The native backend:

- Builds a command through the provider adapter.
- Starts it in a PTY-backed Neovim terminal buffer.
- Passes input directly to the CLI.
- Preserves native CLI behavior.
- Emits only events that can be established reliably, such as process start, exit, and failure.

Each native backend instance owns one job and one terminal buffer. It does not create, resize, show,
or close the sidebar window.

#### Structured backend

A structured backend:

- Communicates through a documented provider protocol or SDK surface.
- Translates provider messages into a small normalized event set.
- Preserves the original provider payload on normalized events.
- Supports a Neovim-native transcript, composer, approvals, and precise turn state where possible.

Structured backends are provider-specific and may expose different capabilities. They should be
optional because their protocols may be experimental, incomplete, or change independently of the
native CLI.

### Events

The event contract should remain small. Candidate events are:

- `session_started`
- `session_exited`
- `session_failed`
- `turn_started`
- `turn_completed`
- `turn_failed`
- `output`
- `approval_requested`
- `files_changed`

Every event includes the plugin session ID. Structured provider events should also retain their
raw payload:

```lua
{
  type = "turn_completed",
  session_id = "agents-local-id",
  data = {},
  raw = provider_event,
}
```

The plugin should not normalize fields until more than one consumer needs them. This avoids a
large lowest-common-denominator protocol.

### Sidebar

The sidebar is a view over the active session. It owns the chat window but does not own agent jobs.

- Showing or hiding the sidebar does not start or stop a session.
- Switching chats replaces the buffer displayed in the existing sidebar window.
- Native sessions display their terminal buffer.
- Structured sessions display their transcript/composer buffer or buffers.
- Sidebar position and size remain global UI configuration unless a future use case requires
  per-session values.

Chat tabs are internal to the sidebar and are not Neovim tabpages. A winbar or header may show the
ordered sessions, while mappings and commands select the next, previous, or named session.

## Feature design

### Basic sidebar chat

Native mode remains the default experience. It preserves the complete interactive CLI but cannot
guarantee a scrollable transcript when the CLI uses an alternate screen.

There are three possible interaction modes:

1. **Native**: the unmodified CLI terminal interface.
2. **Terminal compatibility**: provider-specific flags that request flatter output or avoid the
   alternate screen, where supported.
3. **Structured**: a Neovim-rendered transcript and composer backed by a provider protocol.

Compatibility and structured modes must be explicit configuration choices. They may sacrifice
native features and should not silently replace native mode.

When the CLI process exits, its backend emits `session_exited`. The manager marks the session as
exited and, if it was active, closes the sidebar according to `close_on_exit`. The terminal buffer
should remain available as an exited transcript until the user closes that chat explicitly.

### Chat switching

Every chat has an independent session, backend, and buffer. Hidden terminal buffers keep their
jobs alive. Switching changes `active_id` and displays the selected buffer in the same sidebar
window.

The initial command set should support:

- Select next and previous chat.
- Select a chat from a list.
- Stop the active chat.
- Close the active chat and remove it from the tab list.
- Optionally stop all chats.

Stopping and closing are separate operations. A stopped session may retain a transcript; closing
removes it from plugin state.

The native implementation exposes these operations as `:Agents next`, `:Agents prev`,
`:Agents select [session-id]`, `:Agents stop [session-id]`, and `:Agents close [session-id]`.
Winbar tabs are also clickable. Sessions are global to the current Neovim instance and there is no
hard limit on concurrently running native processes.

### Copy a file range to chat

This feature is implemented for native terminal sessions.

File selections are represented as provider-neutral context references:

```lua
{
  kind = "file_range",
  path = "src/module-a/init.py",
  start_line = 6,
  start_col = 23,
  end_line = 14,
  end_col = 78,
}
```

The default text representation is deliberately plain:

```text
src/module-a/init.py:6:23-14:78
```

- Native mode pastes the reference into the active CLI input without submitting it.
- Structured mode adds the reference to the active draft.
- A provider may add a stable file-reference prefix. Claude Code uses `@`; Codex uses the plain
  reference.

The core model must not depend on provider-specific `@file` or mention syntax.

### Automatic buffer refresh

Buffer refresh is a workspace concern and does not depend on agent output.

The initial implementation runs Neovim's external-change check for loaded file buffers on
`BufEnter`, `FocusGained`, and `CursorHold`. It is implemented in `workspace/refresh.lua` and is
configured independently from providers and sessions. A later implementation may add filesystem
watchers for lower latency.

When a change tracker reports a specific path, the refresh service can check its corresponding
loaded buffer immediately. It must never silently overwrite a buffer with unsaved local changes;
Neovim's normal external-change and conflict behavior remains authoritative.

### Modified-files utility

Session-baseline change tracking and navigation are implemented for Git worktrees.

The design distinguishes two guarantees:

1. **Session changes**: files changed since a session baseline.
2. **Turn changes**: files changed between the start and completion of one prompt.

Session changes can work with every backend. The plugin captures a Git/workspace baseline when a
session starts or when the user resets it, then accumulates changed paths. The result can be shown
through `vim.ui.select`, a quickfix list, or a dedicated plugin buffer.

Exact turn changes require reliable `turn_started` and `turn_completed` events. Structured
backends can provide these. Native terminal backends cannot infer them safely from ANSI output, so
their UI must describe the result as changes since the session baseline rather than changes made by
the last prompt.

Even with turn boundaries, a filesystem snapshot proves that a file changed during an interval; it
does not necessarily prove that the agent caused the change. Provider-reported file events may
improve attribution but should be verified against the workspace before navigation.

The change list supports:

- Open a file.
- Open an editable side-by-side diff when possible.
- Move to the next or previous changed file.
- Reset the baseline.
- Distinguish created, modified, deleted, and renamed paths where the source data allows it.

## Proposed module layout

```text
lua/agents/
  init.lua
  commands.lua
  config.lua

  core/
    session.lua
    session_manager.lua
    events.lua

  backends/
    terminal.lua
    codex_app_server.lua
    claude_stream.lua

  providers/
    init.lua
    adapter.lua
    codex.lua
    claude.lua

  ui/
    sidebar.lua
    tabs.lua
    changes.lua
    composer.lua

  workspace/
    refresh.lua
    change_tracker.lua

  context.lua
```

Only modules needed by an implemented feature should be added. The layout expresses ownership; it
is not a requirement to create empty modules in advance.

## Configuration direction

Backend selection should be explicit and provider-local:

```lua
require("agents").setup({
  close_on_exit = true,
  providers = {
    claude = {
      command = "claude",
      mode = "native",
    },
    codex = {
      command = "codex",
      mode = "native",
    },
  },
})
```

Potential modes are `native`, `structured`, and later `terminal_compatibility`. Native should remain
the default. Selecting an unavailable structured mode should produce a clear health/configuration
error instead of silently changing execution behavior.

## Implementation sequence

The native-terminal portions of phases 1 and 2, file-range context references, and automatic
buffer refresh from phase 3 are implemented. The remaining phase 3 feature and later phases remain
planned.

### Phase 1: Separate responsibilities

- Extract window creation, visibility, and sizing into a sidebar module.
- Convert the terminal singleton into independently constructed backend instances.
- Add the session model and manager without changing the default user experience.
- Route commands through the manager.

### Phase 2: Multiple native sessions

- Maintain multiple terminal jobs and buffers.
- Add active-session selection and sidebar chat tabs.
- Handle process exit as a session lifecycle event.
- Separate stop, hide, and close operations.

### Phase 3: Provider-independent workspace features

- Add file-range context references. (Implemented.)
- Add safe automatic buffer refresh. (Implemented and manually verified.)
- Add session-baseline change tracking and navigation. (Implemented for Git worktrees.)

### Phase 4: Capabilities and structured events

- Finalize the minimal backend capability contract.
- Add a fake backend for deterministic tests.
- Add normalized turn and output events without discarding raw provider events.

### Phase 5: Experimental structured integration

- Implement one structured provider backend.
- Add turn-scoped file changes where supported.
- Validate lifecycle, cancellation, approvals, and resume behavior.
- Build a structured transcript/composer only after the transport proves stable.

## Testing strategy

- Test the session manager with fake backends and no real CLI processes.
- Test ordering, switching, exit races, stop/close semantics, and capability errors as pure state
  transitions where possible.
- Test the terminal backend with short local commands rather than authenticated agent CLIs.
- Test provider adapters as command/protocol translation units.
- Test workspace refresh with temporary files and both clean and modified Neovim buffers.
- Keep structured backend fixtures containing raw provider events to detect protocol drift.

The manager must associate callbacks with a session instance rather than global job state. This
prevents a delayed exit callback from one session from modifying another session.

## Tradeoffs

### Benefits

- Native CLI functionality remains available and is still the default.
- Providers without a structured protocol remain supported.
- Multi-chat support no longer depends on terminal-global state.
- Workspace features can evolve independently from agent integrations.
- Rich UI can be added incrementally rather than through a full rewrite.

### Costs

- There are two UI paths to maintain once structured mode is implemented.
- Capability-dependent behavior must be communicated clearly to users.
- Structured provider protocols may change and require compatibility work.
- Native mode cannot offer reliable per-turn semantics or reconstruct discarded TUI history.
- Multiple hidden native sessions consume one process per chat.

These costs are preferable to making an unstable semantic protocol mandatory for all providers or
reducing every provider to the features shared by all CLIs.

## Open questions

- Should an exited chat remain in the tab list by default, or move to a separate recent list?
- What is the default maximum number of simultaneously running native sessions?
- Should session titles be user-assigned only, or inferred from the provider when possible?
- Should the first changed-file UI use quickfix, `vim.ui.select`, or a dedicated sidebar buffer?
- Is automatic refresh based on Neovim events sufficient initially, or is immediate filesystem
  watching required?
- Which structured provider backend is stable enough to prototype first?

## Provider protocol references

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex developer command reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage)

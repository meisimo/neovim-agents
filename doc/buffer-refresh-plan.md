# Automatic Buffer Refresh Implementation Plan

## Status

Implemented and manually verified. The first event-driven version is complete; compatibility
matrix expansion, formatter automation, and filesystem-watcher experiments are deferred
improvements.

## Objective

Keep loaded file buffers synchronized with changes made outside Neovim, including changes made by
agent processes, without coupling the feature to a provider or terminal session.

The first version uses Neovim's external-change detection. It does not watch the filesystem, parse
agent output, or attempt to attribute changes to a particular agent.

## User experience

When Neovim regains focus or the user returns to a file buffer, the plugin checks whether the file
changed on disk. A clean buffer is refreshed through Neovim's normal external-change handling. A
buffer containing unsaved changes is never force-reloaded or overwritten.

Refresh behavior is enabled by default and can be disabled or assigned a different set of events:

```lua
require("agents").setup({
  refresh = {
    enabled = true,
    events = { "BufEnter", "FocusGained", "CursorHold" },
  },
})
```

The initial release does not add a user command. The refresh service exposes Lua functions so later
workspace features can request targeted checks.

## Scope

### Included

- Detect external changes using Neovim's built-in check mechanism.
- Check the current file buffer on buffer-local events.
- Check loaded file buffers when Neovim regains focus.
- Preserve buffers with unsaved local changes.
- Ignore terminal, help, prompt, quickfix, unnamed, unloaded, and invalid buffers.
- Provide a path-targeted refresh API for the future modified-files tracker.
- Make setup idempotent so configuration reloads do not duplicate autocmds.
- Add automated tests and user documentation.

### Excluded

- Filesystem watchers.
- Polling timers.
- Per-turn change detection.
- Determining whether an agent caused a change.
- Resolving conflicts between disk changes and unsaved buffer changes.
- Refreshing files that are not loaded in Neovim.
- Notifications beyond Neovim's standard external-change behavior.

## Design

### Module ownership

Add `lua/agents/workspace/refresh.lua`. This module owns refresh policy and autocmd registration; it
must not depend on providers, sessions, terminal jobs, or the sidebar.

The initial public module interface will be:

```lua
refresh.setup(options)
refresh.refresh_buffer(bufnr)
refresh.refresh_path(path)
refresh.refresh_all()
```

`refresh.setup()` recreates a named augroup and installs the configured events. Recreating the
augroup keeps repeated calls to `require("agents").setup()` idempotent.

### Buffer eligibility

A buffer can be checked only when all of the following are true:

- The buffer handle is valid.
- The buffer is loaded.
- `buftype` is empty.
- The buffer has a non-empty filename.
- The filename identifies a regular file or a file that previously existed and may have been
  removed externally.

The refresh service must not change the active window or replace its buffer.

### Refresh behavior

Refresh operations will delegate change detection to Neovim rather than comparing timestamps or
reading files directly.

- `refresh_buffer(bufnr)` checks one eligible buffer.
- `refresh_path(path)` normalizes the path, finds matching loaded buffers, and checks only those
  buffers.
- `refresh_all()` checks all eligible loaded buffers.

The implementation must never use `:edit!`, directly replace buffer lines, clear the `modified`
flag, or otherwise force disk content over unsaved changes. Neovim remains responsible for
external-change and conflict behavior.

Autocmd behavior:

- `BufEnter` and `CursorHold` check the event buffer.
- `FocusGained` checks all eligible loaded file buffers because several files may have changed
  while Neovim was unfocused.

Callbacks should schedule or guard refresh work if an event context makes an immediate check
unsafe. Expected external-change warnings must not be written to the plugin error log as internal
failures.

### Configuration

Add the following defaults to `lua/agents/config.lua`:

```lua
refresh = {
  enabled = true,
  events = { "BufEnter", "FocusGained", "CursorHold" },
}
```

Configuration requirements:

- `enabled` must be a boolean.
- `events` must be a list of supported event names.
- An empty event list is valid and installs no autocmds.
- Calling setup with `enabled = false` removes previously installed refresh autocmds.
- Invalid values produce an actionable `agents.nvim` error.

The supported event list should initially remain limited to events whose callback behavior is
covered by tests. Users should not be able to inject arbitrary autocmd event names through this
option.

### Plugin setup integration

After configuration is resolved, `lua/agents/init.lua` passes `config.options.refresh` to the
refresh service. Refresh registration remains independent from command and sidebar registration.

No session must be running for automatic refresh to work. This is intentional: buffer refresh is a
workspace feature, not an agent lifecycle feature.

## Implementation steps

### 1. Configuration

- Add refresh defaults.
- Validate the refresh configuration and supported events.
- Preserve existing deep-merge setup behavior.

### 2. Workspace refresh service

- Add buffer eligibility checks.
- Implement single-buffer, path-targeted, and all-buffer refresh functions.
- Normalize paths consistently with Neovim buffer names.
- Prevent one invalid or deleted buffer from aborting an entire refresh pass.

### 3. Autocmd lifecycle

- Create a named `agents.nvim` refresh augroup.
- Clear and recreate its autocmds during setup.
- Route buffer-local and global events to the appropriate refresh function.
- Remove the autocmds when refresh is disabled.

### 4. Automated tests

Use temporary files and real Neovim buffers in the headless test suite. Cover:

- [x] A loaded, unmodified buffer observes content changed on disk.
- [x] A modified buffer retains its unsaved contents after the disk file changes.
- [x] A later check refreshes that buffer after the local changes are intentionally discarded.
- [x] Terminal buffers are ignored.
- [x] Help-style and quickfix buffers are ignored.
- [x] Unnamed and invalid buffers are ignored.
- [x] Unloaded buffers are ignored.
- [x] A file deleted externally is handled without aborting the refresh pass.
- [x] `refresh_path()` checks a matching loaded buffer.
- [x] `refresh_path()` leaves unrelated loaded buffers untouched.
- [x] Equivalent normalized and absolute paths match the same loaded buffer.
- [x] Symlinked and canonical forms of the same path match the same loaded buffer.
- [x] `refresh_all()` continues if one candidate cannot be checked.
- [x] Refresh operations preserve the active window and buffer.
- [x] `BufEnter` refreshes its event buffer.
- [x] `CursorHold` refreshes its event buffer.
- [x] `FocusGained` refreshes all eligible loaded file buffers.
- [x] Repeated setup creates only one set of autocmds.
- [x] Disabling the feature removes previously registered autocmds.
- [x] An empty event list installs no autocmds.
- [x] Invalid configuration reports a clear error.

Tests must preserve and restore global options and autocmd state that could affect other cases.

### 5. Documentation

- [x] Add refresh defaults and behavior to `README.md`.
- [x] Add the option and safety guarantee to `doc/agents.txt`.
- [x] Mark automatic buffer refresh as implemented in `doc/features-summary.md`.
- [x] Update the implementation status and module layout in `doc/architecture.md`.
- [x] State that the first version is event-driven and does not use filesystem watchers.

### 6. Verification

- [x] **Automated:** Run the complete headless Neovim test suite.
- [ ] **Deferred:** Run the suite on Neovim 0.10, the minimum supported version.
- [ ] **Deferred:** Run the Lua formatter or formatting check when available.
- [x] **Automated/tooling:** Run `git diff --check`.
- [x] **Manual:** Verify that an external edit refreshes a clean buffer in interactive Neovim.
- [x] **Manual:** Verify that an external edit cannot overwrite an unsaved buffer in interactive
  Neovim, and that a later check succeeds after the local change is deliberately discarded or
  saved.

## Acceptance criteria

The feature is complete when:

- External changes become visible in eligible clean buffers on a configured event.
- Unsaved buffer contents cannot be silently overwritten by the refresh service.
- The service works without an active agent session.
- Targeted refresh by path is available for later workspace features.
- Setup and disable operations are idempotent.
- Terminal and other non-file buffers are unaffected.
- Automated tests cover the safety and lifecycle cases above.
- README, help, architecture, and feature-summary documentation agree with the implementation.

All first-version acceptance criteria are satisfied. The unchecked compatibility and tooling
items above remain follow-up quality improvements and do not block moving to the next feature.

## Follow-up work

The modified-files utility can call `refresh_path(path)` whenever its change tracker discovers a
specific path. A later filesystem-watcher implementation may call the same function for lower
latency without changing refresh policy or provider integrations.

File-range context references are now implemented. The next Phase 3 feature should be
session-baseline change tracking and navigation.

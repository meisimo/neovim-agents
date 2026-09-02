# Features Summary

This document describes what are all the features of this plugin (existing, incoming, discarded, etc...) as a general overview.

The purpose of this document is to serve as a guideline for design and architecture to align with existing and future changes.

## Features

### Basic side bar chat (multi provider)

- **Description**: A side bar chat for several providers (claude, codex and cursor) functional. The user can open the chat, focus it, dismiss it, navigate in it, write in it.
- **Status**: Done
- **Usability**:
  - **Commands**: `:Agents open [provider]`, `:Agents resume [provider] [session-id]`, `:Agents continue [provider]`, `:Agents toggle`, `:Agents stop [session-id]`, `:Agents close [session-id]`, and `:Agents health`
- **Shortcuts**: `<C-f><C-f>` toggles the sidebar, `<C-f>f` leaves Terminal mode, `<C-f>l` / `<C-f>h` switch sessions, and `<C-f>d` opens the active session's changes by default. The shared `<C-f>` prefix and action suffixes are configurable.
- Each agent process runs in its own terminal buffer. Starting an agent does not replace the current editing buffer, so a file with unsaved changes can remain open and modified while the agent starts.
- Improvements & known issues:
  - Changing between output block and input block is not good and doesnt feel well integrated.
  - `claude` cli output block is not scrollable in any way (nor with vim motions nor with mouse scroll) so there is no way to see large (larger than the terminal height) outputs complete

### Local error logging

- **Description**: Errors raised through the `:Agents` command, the sidebar toggle mapping, or sidebar session selection are shown through `vim.notify` and appended to `logs/errors.log` inside the plugin directory. Entries include a timestamp and Lua stack trace.
- **Status**: Done for debugging
- The `logs` directory is created when the first error is recorded and is excluded from Git.
- Logging failures are ignored so that a read-only plugin directory or other filesystem problem does not replace the original error.

### Modified files utility

- **Description**: Users can list and review Git workspace files changed since an agent session's
  baseline, then move between those files in a side-by-side diff.
- **Status**: Done for Git worktrees and session-scoped native terminal sessions
- `:Agents changes [session-id]` opens a status-labeled picker and an editable diff review.
- `<C-f>dj` and `<C-f>dk` navigate to the next and previous changed files by default.
- `:Agents next-change` and `:Agents prev-change` navigate the captured change list.
- `:Agents reset-changes [session-id]` captures the current workspace as the new baseline.
- Pre-existing edits, the real Git index, and unsaved Neovim buffers are preserved.
- Native backends cannot prove per-turn or agent attribution, so the UI explicitly reports changes
  since the session baseline.

### Neovim files automatic refresh

- Description: If a chat modifies a file that is open in a tab the user will see the changes on the fly without having to reopen the file.
- **Status**: Done
- Loaded file buffers are checked on `BufEnter`, `FocusGained`, and `CursorHold` by default.
- Buffers with unsaved changes and non-file buffers are skipped. The first version is event-driven
  and does not use filesystem watchers.
- Automated headless coverage and interactive manual verification cover clean refreshes, unsaved
  buffer safety, targeted and all-buffer refreshes, special buffers, and autocmd lifecycle.
- Possible future improvements include broader Neovim-version testing and filesystem watchers if
  event-driven refresh latency proves insufficient.

### Inline code suggestions

- **Description**: Manually request code at the current cursor and preview it as non-mutating ghost
  text before accepting or dismissing it.
- **Status**: Experimental, opt-in, and implemented for Claude Code only.
- `:Agents suggest`, `:Agents suggest-accept`, and `:Agents suggest-dismiss` are also exposed through
  Lua and configurable Normal-mode mappings.
- Unsaved buffer text is captured with a byte cap. Requests are asynchronous, cancellable,
  tool-free, and non-persistent, and never reuse an interactive chat session.
- Editing, moving away, entering Insert mode, leaving the buffer, timeout, and stale callbacks all
  clear the preview without changing text. Acceptance is one insertion and one undo entry.
- Requests transmit nearby source to Claude and may incur provider cost. Continuous suggestions,
  replacements, streaming, multiple candidates, and Codex support are deferred.

### Copy from file to the chat

- **Description**: A selected region of a file can be easily copy and paste to the chat, that is, if a user selects the from line 6 char 23 to line 14 char 78 in the file `src/module-a/init.py` then he can copy directly to the `chat` with a command or a shortcut the path to that region so the model in that chat may read it later when the prompt is sent.
- **Status**: Done for saved files and native terminal sessions
- `:Agents context` and `require("agents").context()` convert characterwise or linewise Visual
  selections to provider-neutral file references and insert them without submitting the prompt.
- `<C-f>p` invokes the context operation from Visual mode by default.
- Claude Code references use its `@` file prefix; Codex and providers without a configured prefix
  receive the plain path and range.
- Paths inside the active session working directory are relative; paths outside it are absolute.
- Modified buffers and blockwise selections are rejected so the reference cannot silently point to
  stale or ambiguous content.

### Chat switch support

- Description: The user can navigate through different "tabs" within the same "Chat section" similar to how the current "tabs" in the editor works (check current plugin for tabs management). Is in this tabs what are the current opened chats.
- **Status**: Done for native terminal sessions
- **Usability**:
  - **Commands**: `:Agents next`, `:Agents prev`, `:Agents select [session-id]`, `:Agents stop [session-id]`, and `:Agents close [session-id]`
  - **Mouse**: Click a session label in the sidebar winbar
- Each new, resumed, or continued chat gets an independent process and terminal buffer. Hiding the sidebar does not stop any chat.

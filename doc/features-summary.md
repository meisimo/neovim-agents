# Features Summary

This document describes what are all the features of this plugin (existing, incoming, discarded, etc...) as a general overview.

The purpose of this document is to serve as a guideline for design and architecture to align with existing and future changes.

## Features

### Basic side bar chat (multi provider)

- **Description**: A side bar chat for several providers (claude, codex and cursor) functional. The user can open the chat, focus it, dismiss it, navigate in it, write in it.
- **Status**: Done
- **Usability**:
  - **Commands**: `:Agents open [provider]`, `:Agents resume [provider] [session-id]`, `:Agents continue [provider]`, `:Agents toggle`, `:Agents stop [session-id]`, `:Agents close [session-id]`, and `:Agents health`
  - **Shortcuts**: `<C-f><C-f>` toggles the sidebar and `<C-f>f` leaves Terminal mode by default. Both mappings are configurable.
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

- **Description**: If after output is finished (a single prompt output) there were modified files the user can easily navigate through the modified files, that is, see a list were the modified files can by select and opened
- **Status**: Pending to be designed

### Neovim files automatic refresh

- Description: If a chat modifies a file that is open in a tab the user will see the changes on the fly without having to reopen the file.
- **Status**: In progress; the provider-independent refresh service and event integration are
  implemented
- Loaded file buffers are checked on `BufEnter`, `FocusGained`, and `CursorHold` by default.
- Buffers with unsaved changes and non-file buffers are skipped. The first version is event-driven
  and does not use filesystem watchers.

### Copy from file to the chat

- **Description**: A selected region of a file can be easily copy and paste to the chat, that is, if a user selects the from line 6 char 23 to line 14 char 78 in the file `src/module-a/init.py` then he can copy directly to the `chat` with a command or a shortcut the path to that region so the model in that chat may read it later when the prompt is sent.
- **Status**: Pending to be designed

### Chat switch support

- Description: The user can navigate through different "tabs" within the same "Chat section" similar to how the current "tabs" in the editor works (check current plugin for tabs management). Is in this tabs what are the current opened chats.
- **Status**: Done for native terminal sessions
- **Usability**:
  - **Commands**: `:Agents next`, `:Agents prev`, `:Agents select [session-id]`, `:Agents stop [session-id]`, and `:Agents close [session-id]`
  - **Mouse**: Click a session label in the sidebar winbar
- Each new, resumed, or continued chat gets an independent process and terminal buffer. Hiding the sidebar does not stop any chat.

local function assert_equal(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message or ("expected truthy value, got %s"):format(vim.inspect(value)))
  end
end

local function find_mapping(buffer, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "t")) do
    if mapping.lhs == lhs then
      return mapping
    end
  end
end

local function find_global_mapping(mode, lhs)
  for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
    if mapping.lhs:lower() == lhs:lower() then
      return mapping
    end
  end
end

local claude = require("agents.providers.claude")
local codex = require("agents.providers.codex")
local providers = require("agents.providers")
local adapter = require("agents.providers.adapter")

assert_equal({ "claude" }, claude.build_command("open", {}, { command = "claude" }))
assert_equal({ "claude", "--resume" }, claude.build_command("resume", {}, { command = "claude" }))
assert_equal(
  { "claude", "--resume", "session-123" },
  claude.build_command("resume", { session_id = "session-123" }, { command = "claude" })
)
assert_equal(
  { "custom-claude", "--verbose", "--continue" },
  claude.build_command("continue", {}, { command = "custom-claude", args = { "--verbose" } })
)
assert_equal(true, claude.supports("resume"))
assert_equal(false, claude.supports("fork"))
assert_equal("@", claude.context_prefix)

assert_equal({ "codex" }, codex.build_command("open", {}, { command = "codex" }))
assert_equal("", codex.context_prefix)
assert_equal({ "codex", "resume" }, codex.build_command("resume", {}, { command = "codex" }))
assert_equal(
  { "codex", "resume", "session-456" },
  codex.build_command("resume", { session_id = "session-456" }, { command = "codex" })
)
assert_equal(
  { "custom-codex", "--no-alt-screen", "resume", "--last" },
  codex.build_command("continue", {}, { command = "custom-codex", args = { "--no-alt-screen" } })
)
assert_equal({ "claude", "codex" }, providers.names())

local example = adapter.new({
  name = "example",
  command = "example-agent",
  actions = {
    open = function()
      return { "chat" }
    end,
  },
})
providers.register("example", example)
assert_equal(
  { "example-agent", "--color", "chat" },
  providers.get("example").build_command("open", {}, { args = { "--color" } })
)
assert_equal({ "claude", "codex", "example" }, providers.names())

local agents = require("agents")
local mappings = require("agents.mappings")
agents.setup()
assert_equal(2, vim.fn.exists(":Agents"))
assert_equal("<C-f>", require("agents.config").options.mappings.prefix)
assert_equal("<prefix>", require("agents.config").options.mappings.toggle)
assert_equal("f", require("agents.config").options.mappings.escape)
assert_equal("p", require("agents.config").options.mappings.context)
assert_equal("d", require("agents.config").options.mappings.changes)
assert_equal("dj", require("agents.config").options.mappings.next_change)
assert_equal("dk", require("agents.config").options.mappings.previous_change)
assert_equal("l", require("agents.config").options.mappings.next)
assert_equal("h", require("agents.config").options.mappings.previous)
assert_equal(true, require("agents.config").options.close_on_exit)
assert_equal(
  { enabled = true, events = { "BufEnter", "FocusGained", "CursorHold" } },
  require("agents.config").options.refresh
)
assert_equal("Toggle agent terminal", vim.fn.maparg("<C-f><C-f>", "n", false, true).desc)
assert_equal("Add file range to agent chat", vim.fn.maparg("<C-f>p", "x", false, true).desc)
assert_equal("Review current agent session changes", vim.fn.maparg("<C-f>d", "n", false, true).desc)
assert_equal("Review next agent session change", vim.fn.maparg("<C-f>dj", "n", false, true).desc)
assert_equal(
  "Review previous agent session change",
  vim.fn.maparg("<C-f>dk", "n", false, true).desc
)
assert_equal("Select next agent session", vim.fn.maparg("<C-f>l", "n", false, true).desc)
assert_equal("Select previous agent session", vim.fn.maparg("<C-f>h", "n", false, true).desc)
local commands = require("agents.commands")
local original_execute_safe = commands.execute_safe
local mapped_commands = {}
commands.execute_safe = function(arguments)
  table.insert(mapped_commands, arguments[1])
end
for _, lhs in ipairs({ "<C-f>d", "<C-f>dj", "<C-f>dk", "<C-f>l", "<C-f>h" }) do
  find_global_mapping("n", lhs).callback()
end
commands.execute_safe = original_execute_safe
assert_equal({ "changes", "next-change", "prev-change", "next", "prev" }, mapped_commands)
agents.setup({ mappings = { prefix = "<C-g>" } })
assert_equal("", vim.fn.maparg("<C-f><C-f>", "n"))
assert_equal("", vim.fn.maparg("<C-f>d", "n"))
assert_equal("", vim.fn.maparg("<C-f>dj", "n"))
assert_equal("", vim.fn.maparg("<C-f>dk", "n"))
assert_equal("", vim.fn.maparg("<C-f>l", "n"))
assert_equal("", vim.fn.maparg("<C-f>h", "n"))
assert_equal("Toggle agent terminal", vim.fn.maparg("<C-g><C-g>", "n", false, true).desc)
assert_equal("Add file range to agent chat", vim.fn.maparg("<C-g>p", "x", false, true).desc)
assert_equal("Review current agent session changes", vim.fn.maparg("<C-g>d", "n", false, true).desc)
assert_equal("Review next agent session change", vim.fn.maparg("<C-g>dj", "n", false, true).desc)
assert_equal(
  "Review previous agent session change",
  vim.fn.maparg("<C-g>dk", "n", false, true).desc
)
assert_equal("Select next agent session", vim.fn.maparg("<C-g>l", "n", false, true).desc)
assert_equal("Select previous agent session", vim.fn.maparg("<C-g>h", "n", false, true).desc)
assert_equal("<C-g>x", mappings.resolve({ prefix = "<C-g>", custom = "x" }, "custom"))
assert_equal(nil, mappings.resolve({ prefix = "<C-g>", custom = false }, "custom"))
agents.setup({ window = { position = "bottom" } })
assert_equal("bottom", require("agents.config").options.window.position)
assert_equal(2, vim.fn.exists(":Agents"))
assert_equal("function", type(agents.open))
assert_equal("function", type(agents.resume))
assert_equal("function", type(agents.continue))
assert_equal("function", type(agents.next))
assert_equal("function", type(agents.previous))
assert_equal("function", type(agents.select))
assert_equal("function", type(agents.close))
assert_equal("function", type(agents.context))
assert_equal("function", type(agents.changes))
assert_equal("function", type(agents.next_change))
assert_equal("function", type(agents.previous_change))
assert_equal("function", type(agents.reset_changes))
agents.setup({ mappings = { context = false } })
assert_equal("", vim.fn.maparg("<C-f>p", "x"))
agents.setup({ window = { position = "bottom" } })
assert_equal("Add file range to agent chat", vim.fn.maparg("<C-f>p", "x", false, true).desc)

local refresh = require("agents.workspace.refresh")
agents.setup({ refresh = { enabled = false } })
assert_equal(0, #vim.api.nvim_get_autocmds({ group = "AgentsNvimRefresh" }))

local refresh_path = vim.fn.tempname()
vim.fn.writefile({ "before" }, refresh_path)
local refresh_buffer = vim.fn.bufadd(refresh_path)
vim.fn.bufload(refresh_buffer)
assert_equal({ "before" }, vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false))

vim.fn.writefile({ "after", "external" }, refresh_path)
local active_window = vim.api.nvim_get_current_win()
local active_buffer = vim.api.nvim_get_current_buf()
assert_equal(true, refresh.refresh_buffer(refresh_buffer))
assert_equal(active_window, vim.api.nvim_get_current_win())
assert_equal(active_buffer, vim.api.nvim_get_current_buf())
assert_truthy(vim.wait(1000, function()
  return vim.deep_equal(
    { "after", "external" },
    vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false)
  )
end), "clean buffer did not observe the external change")

vim.api.nvim_buf_set_lines(refresh_buffer, 0, -1, false, { "unsaved" })
vim.fn.writefile({ "second external change" }, refresh_path)
assert_equal(false, refresh.refresh_buffer(refresh_buffer))
assert_equal({ "unsaved" }, vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false))
assert_equal(true, vim.bo[refresh_buffer].modified)

vim.bo[refresh_buffer].modified = false
local normalized_refresh_path = vim.fn.fnamemodify(refresh_path, ":h")
  .. "/./"
  .. vim.fn.fnamemodify(refresh_path, ":t")
assert_equal(true, refresh.refresh_path(normalized_refresh_path) > 0)
assert_truthy(vim.wait(1000, function()
  return vim.deep_equal(
    { "second external change" },
    vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false)
  )
end), "normalized path did not refresh its loaded buffer")

local unrelated_path = vim.fn.tempname()
vim.fn.writefile({ "unrelated before" }, unrelated_path)
local unrelated_buffer = vim.fn.bufadd(unrelated_path)
vim.fn.bufload(unrelated_buffer)
vim.bo[unrelated_buffer].autoread = false

vim.fn.writefile({ "targeted change" }, refresh_path)
vim.fn.writefile({ "unrelated external change" }, unrelated_path)
assert_equal(1, refresh.refresh_path(refresh_path))
assert_truthy(vim.wait(1000, function()
  return vim.deep_equal(
    { "targeted change" },
    vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false)
  )
end), "targeted buffer was not refreshed")
assert_equal(
  { "unrelated before" },
  vim.api.nvim_buf_get_lines(unrelated_buffer, 0, -1, false)
)
vim.bo[unrelated_buffer].autoread = true

local unnamed = vim.api.nvim_create_buf(true, false)
assert_equal(false, refresh.refresh_buffer(unnamed))
vim.bo[unnamed].buftype = "nofile"
assert_equal(false, refresh.refresh_buffer(unnamed))
vim.api.nvim_buf_delete(unnamed, { force = true })
assert_equal(false, refresh.refresh_buffer(unnamed))

local help_buffer = vim.api.nvim_create_buf(true, false)
vim.bo[help_buffer].buftype = "help"
assert_equal(false, refresh.refresh_buffer(help_buffer))

local quickfix_buffer = vim.api.nvim_create_buf(true, false)
vim.bo[quickfix_buffer].buftype = "quickfix"
assert_equal(false, refresh.refresh_buffer(quickfix_buffer))

local terminal_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_call(terminal_buffer, function()
  vim.fn.termopen({ vim.o.shell, vim.o.shellcmdflag, "exit 0" })
end)
assert_equal("terminal", vim.bo[terminal_buffer].buftype)
assert_equal(false, refresh.refresh_buffer(terminal_buffer))

local unloaded_path = vim.fn.tempname()
vim.fn.writefile({ "unloaded" }, unloaded_path)
local unloaded_buffer = vim.fn.bufadd(unloaded_path)
assert_equal(false, vim.api.nvim_buf_is_loaded(unloaded_buffer))
assert_equal(false, refresh.refresh_buffer(unloaded_buffer))

local deleted_path = vim.fn.tempname()
vim.fn.writefile({ "deleted file contents" }, deleted_path)
local deleted_buffer = vim.fn.bufadd(deleted_path)
vim.fn.bufload(deleted_buffer)
vim.fn.delete(deleted_path)
local deleted_ok = pcall(refresh.refresh_buffer, deleted_buffer)
assert_equal(true, deleted_ok)
assert_equal(
  { "deleted file contents" },
  vim.api.nvim_buf_get_lines(deleted_buffer, 0, -1, false)
)

vim.fn.writefile({ "refresh all change" }, unrelated_path)
local original_refresh_buffer = refresh.refresh_buffer
refresh.refresh_buffer = function(bufnr)
  if bufnr == deleted_buffer then
    return false
  end
  return original_refresh_buffer(bufnr)
end
local refresh_all_window = vim.api.nvim_get_current_win()
local refresh_all_buffer = vim.api.nvim_get_current_buf()
local refresh_all_ok = pcall(refresh.refresh_all)
refresh.refresh_buffer = original_refresh_buffer
assert_equal(true, refresh_all_ok)
assert_equal(refresh_all_window, vim.api.nvim_get_current_win())
assert_equal(refresh_all_buffer, vim.api.nvim_get_current_buf())
assert_truthy(vim.wait(1000, function()
  return vim.deep_equal(
    { "refresh all change" },
    vim.api.nvim_buf_get_lines(unrelated_buffer, 0, -1, false)
  )
end), "refresh_all did not continue after an uncheckable candidate")

agents.setup({
  refresh = { events = { "BufEnter", "FocusGained", "CursorHold" } },
})
local autocmd_count = #vim.api.nvim_get_autocmds({ group = "AgentsNvimRefresh" })
assert_equal(3, autocmd_count)

vim.fn.writefile({ "autocmd refresh" }, refresh_path)
vim.api.nvim_exec_autocmds("BufEnter", { buffer = refresh_buffer })
assert_truthy(vim.wait(1000, function()
  return vim.deep_equal(
    { "autocmd refresh" },
    vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false)
  )
end), "BufEnter did not refresh its event buffer")

vim.fn.writefile({ "cursor hold refresh" }, refresh_path)
vim.api.nvim_exec_autocmds("CursorHold", { buffer = refresh_buffer })
assert_truthy(vim.wait(1000, function()
  return vim.deep_equal(
    { "cursor hold refresh" },
    vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false)
  )
end), "CursorHold did not refresh its event buffer")

vim.fn.writefile({ "focus target" }, refresh_path)
vim.fn.writefile({ "focus unrelated" }, unrelated_path)
local refresh_all_calls = 0
local real_refresh_all = refresh.refresh_all
refresh.refresh_all = function()
  refresh_all_calls = refresh_all_calls + 1
  return real_refresh_all()
end
vim.api.nvim_exec_autocmds("FocusGained", {})
assert_truthy(vim.wait(1000, function()
  return refresh_all_calls == 1
    and vim.deep_equal(
      { "focus target" },
      vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false)
    )
    and vim.deep_equal(
      { "focus unrelated" },
      vim.api.nvim_buf_get_lines(unrelated_buffer, 0, -1, false)
    )
end), "FocusGained did not refresh all loaded file buffers")
refresh.refresh_all = real_refresh_all

agents.setup({
  refresh = { events = { "BufEnter", "FocusGained", "CursorHold" } },
})
assert_equal(autocmd_count, #vim.api.nvim_get_autocmds({ group = "AgentsNvimRefresh" }))

agents.setup({ refresh = { events = {} } })
assert_equal(0, #vim.api.nvim_get_autocmds({ group = "AgentsNvimRefresh" }))

local function assert_config_error(options, pattern)
  local valid, config_error = pcall(agents.setup, options)
  assert_equal(false, valid)
  assert_truthy(config_error:find(pattern))
end

assert_config_error({ mappings = false }, "mappings must be a table")
assert_config_error(
  { mappings = { prefix = false } },
  "mappings.prefix must be a non%-empty string"
)
assert_config_error({ mappings = { escape = 1 } }, "mappings.escape must be a string or false")
assert_config_error({ mappings = { changes = 1 } }, "mappings.changes must be a string or false")
assert_config_error({ refresh = false }, "refresh must be a table")
assert_config_error({ refresh = { enabled = "yes" } }, "refresh.enabled must be a boolean")
assert_config_error({ refresh = { events = "BufEnter" } }, "refresh.events must be a list")
assert_config_error(
  { refresh = { events = { "BufWritePost" } } },
  "refresh.events%[1%] must be one of"
)
agents.setup({ refresh = { enabled = false } })

vim.api.nvim_buf_delete(refresh_buffer, { force = true })
vim.api.nvim_buf_delete(unrelated_buffer, { force = true })
vim.api.nvim_buf_delete(help_buffer, { force = true })
vim.api.nvim_buf_delete(quickfix_buffer, { force = true })
vim.api.nvim_buf_delete(terminal_buffer, { force = true })
vim.api.nvim_buf_delete(unloaded_buffer, { force = true })
vim.api.nvim_buf_delete(deleted_buffer, { force = true })
vim.fn.delete(refresh_path)
vim.fn.delete(unrelated_path)
vim.fn.delete(unloaded_path)

local change_tracker = require("agents.workspace.change_tracker")
local changes_root = vim.fn.tempname()
vim.fn.mkdir(changes_root, "p")

local function git(arguments)
  local command = { "git" }
  vim.list_extend(command, arguments)
  local result = vim.system(command, { cwd = changes_root, text = false }):wait()
  if result.code ~= 0 then
    error(result.stderr)
  end
  return result.stdout
end

git({ "init", "--quiet" })
vim.fn.writefile({ "*.ignored" }, vim.fs.joinpath(changes_root, ".gitignore"))
vim.fn.writefile({ "committed" }, vim.fs.joinpath(changes_root, "deleted.txt"))
vim.fn.writefile({ "rename contents" }, vim.fs.joinpath(changes_root, "rename-old.txt"))
vim.fn.writefile({ "committed" }, vim.fs.joinpath(changes_root, "tracked.txt"))
git({ "add", "." })
git({
  "-c",
  "user.name=agents.nvim tests",
  "-c",
  "user.email=agents@example.invalid",
  "commit",
  "--quiet",
  "-m",
  "initial",
})

vim.fn.writefile({ "pre-existing edit" }, vim.fs.joinpath(changes_root, "tracked.txt"))
vim.fn.writefile({ "pre-existing untracked" }, vim.fs.joinpath(changes_root, "untracked.txt"))
local status_before_capture = git({ "status", "--porcelain=v1", "-z" })
local baseline = change_tracker.capture(changes_root)
assert_equal(vim.uv.fs_realpath(changes_root), vim.uv.fs_realpath(baseline.root))
assert_equal(status_before_capture, git({ "status", "--porcelain=v1", "-z" }))
assert_equal("pre-existing edit\n", change_tracker.read(baseline, "tracked.txt"))

vim.fn.writefile({ "agent edit" }, vim.fs.joinpath(changes_root, "tracked.txt"))
vim.fn.writefile(
  { "agent edit to prior untracked" },
  vim.fs.joinpath(changes_root, "untracked.txt")
)
vim.fn.writefile({ "created" }, vim.fs.joinpath(changes_root, "created.txt"))
vim.fn.writefile({ "odd path" }, vim.fs.joinpath(changes_root, "odd\tname.txt"))
vim.fn.writefile({ "ignored" }, vim.fs.joinpath(changes_root, "generated.ignored"))
vim.fn.delete(vim.fs.joinpath(changes_root, "deleted.txt"))
vim.uv.fs_rename(
  vim.fs.joinpath(changes_root, "rename-old.txt"),
  vim.fs.joinpath(changes_root, "rename-new.txt")
)

local tracked_changes, current_snapshot = change_tracker.changes(baseline)
local changes_by_path = {}
for _, change in ipairs(tracked_changes) do
  changes_by_path[change.path] = change
end
assert_equal("A", changes_by_path["created.txt"].status)
assert_equal("D", changes_by_path["deleted.txt"].status)
assert_equal("A", changes_by_path["odd\tname.txt"].status)
assert_equal("R", changes_by_path["rename-new.txt"].status)
assert_equal("rename-old.txt", changes_by_path["rename-new.txt"].old_path)
assert_equal("M", changes_by_path["tracked.txt"].status)
assert_equal("M", changes_by_path["untracked.txt"].status)
assert_equal(nil, changes_by_path["generated.ignored"])
assert_equal("agent edit\n", change_tracker.read(current_snapshot, "tracked.txt"))
assert_equal(nil, change_tracker.read(current_snapshot, "deleted.txt"))

vim.fn.writefile({ "pre-existing edit" }, vim.fs.joinpath(changes_root, "tracked.txt"))
local reverted_changes = change_tracker.changes(baseline)
local reverted_tracked = false
for _, change in ipairs(reverted_changes) do
  reverted_tracked = reverted_tracked or change.path == "tracked.txt"
end
assert_equal(false, reverted_tracked)

local reset_baseline = change_tracker.capture(changes_root)
assert_equal(0, #change_tracker.changes(reset_baseline))
local non_git_root = vim.fn.tempname()
vim.fn.mkdir(non_git_root, "p")
local non_git_ok, non_git_error = pcall(change_tracker.capture, non_git_root)
assert_equal(false, non_git_ok)
assert_truthy(non_git_error:find("cannot capture workspace changes"))
vim.fn.delete(non_git_root, "rf")

local changes_ui_module = require("agents.ui.changes")
assert_equal(
  "[M] tracked.txt",
  changes_ui_module.format_item({ status = "M", path = "tracked.txt" })
)
assert_equal(
  "[R] old.lua → new.lua",
  changes_ui_module.format_item({ status = "R", old_path = "old.lua", path = "new.lua" })
)

vim.fn.writefile({ "review current" }, vim.fs.joinpath(changes_root, "tracked.txt"))
vim.fn.delete(vim.fs.joinpath(changes_root, "created.txt"))
local review_changes, review_current = change_tracker.changes(reset_baseline)
local selected_review_change = nil
local original_ui_select = vim.ui.select
local original_notify = vim.notify
vim.ui.select = function(items, options, callback)
  assert_equal("Session 77 changes since baseline", options.prompt)
  for _, item in ipairs(items) do
    if item.path == "tracked.txt" then
      selected_review_change = item
      break
    end
  end
  callback(selected_review_change)
end
vim.notify = function() end

local review_ui = changes_ui_module.new({ tracker = change_tracker, refresh = refresh })
assert_equal(true, review_ui:pick({
  id = 77,
  change_tracking = { baseline = reset_baseline },
}, review_changes, review_current))
local review_state = review_ui:state()
assert_truthy(review_state)
assert_equal(#review_changes, review_state.count)
assert_equal("nofile", vim.bo[vim.api.nvim_win_get_buf(review_state.left)].buftype)
local review_file_buffer = vim.api.nvim_win_get_buf(review_state.right)
assert_equal(
  vim.uv.fs_realpath(vim.fs.joinpath(changes_root, "tracked.txt")),
  vim.uv.fs_realpath(vim.api.nvim_buf_get_name(review_file_buffer))
)
assert_equal(true, vim.wo[review_state.left].diff)
assert_equal(true, vim.wo[review_state.right].diff)

vim.api.nvim_buf_set_lines(review_file_buffer, 0, -1, false, { "unsaved review edit" })
review_ui:next()
review_ui:previous()
assert_equal(true, vim.api.nvim_buf_is_valid(review_file_buffer))
assert_equal(true, vim.bo[review_file_buffer].modified)
assert_equal(
  { "unsaved review edit" },
  vim.api.nvim_buf_get_lines(review_file_buffer, 0, -1, false)
)
review_ui:invalidate(77)
assert_equal(nil, review_ui:state())
assert_equal(false, review_ui:pick({ id = 77 }, {}, review_current))
vim.bo[review_file_buffer].modified = false
vim.cmd("tabclose")
vim.ui.select = original_ui_select
vim.notify = original_notify

vim.fn.delete(changes_root, "rf")

local context = require("agents.context")
local context_root = vim.fn.tempname()
vim.fn.mkdir(context_root, "p")
local context_path = vim.fs.joinpath(context_root, "file with spaces.lua")
vim.fn.writefile({ "abcdef", "ghijkl", "mnopqr", "aéz" }, context_path)
local context_buffer = vim.fn.bufadd(context_path)
vim.fn.bufload(context_buffer)

assert_equal(
  "file with spaces.lua:1-3",
  context.render({
    bufnr = context_buffer,
    mode = "V",
    first = { line = 3, col = 7 },
    last = { line = 1, col = 1 },
  }, context_root)
)
local original_relpath = vim.fs.relpath
vim.fs.relpath = nil
local fallback_relative_reference = context.render({
  bufnr = context_buffer,
  mode = "V",
  first = { line = 1, col = 1 },
  last = { line = 1, col = 1 },
}, context_root)
vim.fs.relpath = original_relpath
assert_equal("file with spaces.lua:1", fallback_relative_reference)
assert_equal(
  "file with spaces.lua:1:2-2:4",
  context.render({
    bufnr = context_buffer,
    mode = "v",
    first = { line = 2, col = 4 },
    last = { line = 1, col = 2 },
  }, context_root)
)
assert_equal(
  "@file with spaces.lua:1:2-2:4",
  context.render({
    bufnr = context_buffer,
    mode = "v",
    first = { line = 1, col = 2 },
    last = { line = 2, col = 4 },
  }, context_root, "@")
)
assert_truthy(
  context.render({
    bufnr = context_buffer,
    mode = "V",
    first = { line = 2, col = 1 },
    last = { line = 2, col = 1 },
  }, vim.fn.tempname()):find(vim.pesc(context_path), 1, false)
)

local block_ok, block_error = pcall(function()
  context.render({
    bufnr = context_buffer,
    mode = "\22",
    first = { line = 1, col = 1 },
    last = { line = 2, col = 2 },
  }, context_root)
end)
assert_equal(false, block_ok)
assert_truthy(block_error:find("blockwise selections are not supported"))

vim.api.nvim_buf_set_lines(context_buffer, 0, 1, false, { "unsaved" })
local modified_context_ok, modified_context_error = pcall(function()
  context.render({
    bufnr = context_buffer,
    mode = "V",
    first = { line = 1, col = 1 },
    last = { line = 1, col = 1 },
  }, context_root)
end)
assert_equal(false, modified_context_ok)
assert_truthy(modified_context_error:find("save the file"))
vim.api.nvim_buf_set_lines(context_buffer, 0, 1, false, { "abcdef" })
vim.bo[context_buffer].modified = false

local unnamed_context_buffer = vim.api.nvim_create_buf(true, false)
local unnamed_context_ok, unnamed_context_error = pcall(function()
  context.render({
    bufnr = unnamed_context_buffer,
    mode = "V",
    first = { line = 1, col = 1 },
    last = { line = 1, col = 1 },
  }, context_root)
end)
assert_equal(false, unnamed_context_ok)
assert_truthy(unnamed_context_error:find("named file buffer"))
vim.api.nvim_buf_delete(unnamed_context_buffer, { force = true })

local special_context_buffer = vim.api.nvim_create_buf(false, true)
local special_context_ok, special_context_error = pcall(function()
  context.render({
    bufnr = special_context_buffer,
    mode = "V",
    first = { line = 1, col = 1 },
    last = { line = 1, col = 1 },
  }, context_root)
end)
assert_equal(false, special_context_ok)
assert_truthy(special_context_error:find("loaded file buffer"))
vim.api.nvim_buf_delete(special_context_buffer, { force = true })

local context_window_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_buf(0, context_buffer)
vim.api.nvim_win_set_cursor(0, { 1, 1 })
vim.cmd("normal! v2l")
local captured_visual = context.capture_visual(context_buffer)
assert_equal("v", captured_visual.mode)
assert_equal({ line = 1, col = 2 }, captured_visual.first)
assert_equal({ line = 1, col = 4 }, captured_visual.last)
vim.cmd("normal! \27")
local captured_command = context.capture_command(context_buffer, 1, 1, 1)
assert_equal("v", captured_command.mode)
assert_equal({ line = 1, col = 2 }, captured_command.first)
assert_equal({ line = 1, col = 4 }, captured_command.last)

vim.api.nvim_win_set_cursor(0, { 4, 1 })
vim.cmd("normal! vl")
local multibyte_visual = context.capture_visual(context_buffer)
assert_equal({ line = 4, col = 2 }, multibyte_visual.first)
assert_equal({ line = 4, col = 4 }, multibyte_visual.last)
vim.cmd("normal! \27")
vim.api.nvim_win_set_buf(0, context_window_buffer)

local commands = require("agents.commands")
assert_equal({ action = "open", provider = "codex" }, commands.parse({ "open", "codex" }))
assert_equal(
  { action = "resume", provider = "codex", session_id = "session-456" },
  commands.parse({ "resume", "codex", "session-456" })
)
assert_equal(
  { action = "resume", provider = "claude", session_id = "session-123" },
  commands.parse({ "resume", "session-123" })
)
assert_equal({ action = "continue", provider = "codex" }, commands.parse({ "continue", "codex" }))
assert_equal({ action = "stop", session_id = "4" }, commands.parse({ "stop", "4" }))
assert_equal({ action = "close", session_id = "3" }, commands.parse({ "close", "3" }))
assert_equal({ action = "select", session_id = "2" }, commands.parse({ "select", "2" }))
assert_equal({ action = "context" }, commands.parse({ "context" }))
assert_equal({ action = "changes", session_id = "2" }, commands.parse({ "changes", "2" }))
assert_equal({ action = "next-change" }, commands.parse({ "next-change" }))
assert_equal({ action = "prev-change" }, commands.parse({ "prev-change" }))
assert_equal(
  { action = "reset-changes", session_id = "1" },
  commands.parse({ "reset-changes", "1" })
)

local session_manager = require("agents.core.session_manager")

local function fake_manager()
  local fake_sidebar = {
    visible = false,
    displayed = nil,
    renders = 0,
  }

  function fake_sidebar:is_visible()
    return self.visible
  end

  function fake_sidebar:show(session)
    self.visible = true
    self.displayed = session.id
  end

  function fake_sidebar:refresh()
    self.renders = self.renders + 1
  end

  function fake_sidebar:hide()
    self.visible = false
    self.displayed = nil
  end

  function fake_sidebar:state()
    return { window = self.visible and 1 or nil }
  end

  local fake_provider = {
    default_command = "fake-agent",
    context_prefix = "@",
    supports = function()
      return true
    end,
    is_available = function()
      return true
    end,
    build_command = function()
      return { "fake-agent" }
    end,
  }
  local fake_registry = {
    get = function(name)
      assert_equal("test", name)
      return fake_provider
    end,
  }
  local fake_config = {
    options = {
      default_provider = "test",
      cwd = "/test/workspace",
      close_on_exit = true,
      mappings = {},
      providers = { test = { command = "fake-agent" } },
    },
  }
  local backends = {}
  local controls = {
    fail_start = false,
    fail_capture = false,
    captures = 0,
    picked = nil,
    moved = nil,
    invalidated = {},
  }
  local fake_change_tracker = {}

  function fake_change_tracker.capture(cwd)
    if controls.fail_capture then
      error("agents.nvim: fake tracking unavailable")
    end
    controls.captures = controls.captures + 1
    return { root = cwd, tree = "tree-" .. controls.captures }
  end

  function fake_change_tracker.changes(baseline)
    return { { status = "M", path = "changed.lua" } }, {
      root = baseline.root,
      tree = "current-tree",
    }
  end

  local fake_changes_ui = {}

  function fake_changes_ui:pick(session, changes, current)
    controls.picked = { session = session, changes = changes, current = current }
  end

  function fake_changes_ui:next()
    controls.moved = "next"
    return { path = "changed.lua" }
  end

  function fake_changes_ui:previous()
    controls.moved = "previous"
    return { path = "changed.lua" }
  end

  function fake_changes_ui:invalidate(session_id)
    table.insert(controls.invalidated, session_id or "all")
  end

  local manager = session_manager.new({
    sidebar = fake_sidebar,
    providers = fake_registry,
    config = fake_config,
    change_tracker = fake_change_tracker,
    changes_ui = fake_changes_ui,
    backend_factory = function(options)
      local backend = {
        bufnr = options.id + 100,
        running = false,
        destroyed = false,
      }

      function backend:start()
        if controls.fail_start then
          error("fake launch failure")
        end
        self.running = true
      end

      function backend:stop()
        self.running = false
        options.on_exit(self, 143)
      end

      function backend:is_running()
        return self.running
      end

      function backend:send(text)
        self.sent = text
      end

      function backend:destroy()
        self.running = false
        self.destroyed = true
        options.on_destroy(self)
      end

      function backend:exit(exit_code)
        self.running = false
        options.on_exit(self, exit_code)
      end

      function backend:wipe()
        self.running = false
        options.on_destroy(self)
      end

      backends[options.id] = backend
      return backend
    end,
  })
  return manager, fake_sidebar, backends, fake_config, controls
end

local manager, fake_sidebar, fake_backends, fake_config, fake_controls = fake_manager()
local no_session_context_ok, no_session_context_error = pcall(function()
  manager:add_context({
    bufnr = context_buffer,
    mode = "V",
    first = { line = 1, col = 1 },
    last = { line = 1, col = 1 },
  })
end)
assert_equal(false, no_session_context_ok)
assert_truthy(no_session_context_error:find("no active session"))
local first = manager:start("open", "test")
local second = manager:start("open", "test")
assert_equal(1, first.id)
assert_equal(2, second.id)
assert_equal(2, #manager:list())
assert_equal(2, manager:active().id)
assert_equal(true, fake_backends[1].running)
assert_equal(true, fake_backends[2].running)
assert_equal(true, manager:state().sessions[1].change_tracking.available)
assert_equal("/test/workspace", manager:state().sessions[1].change_tracking.root)
local session_changes = manager:show_changes(1)
assert_equal("changed.lua", session_changes[1].path)
assert_equal(1, fake_controls.picked.session.id)
assert_equal("current-tree", fake_controls.picked.current.tree)
assert_equal("changed.lua", manager:next_change().path)
assert_equal("next", fake_controls.moved)
assert_equal("changed.lua", manager:previous_change().path)
assert_equal("previous", fake_controls.moved)
local old_baseline_tree = first.change_tracking.baseline.tree
manager:reset_changes(1)
assert_truthy(first.change_tracking.baseline.tree ~= old_baseline_tree)
assert_equal(1, fake_controls.invalidated[#fake_controls.invalidated])
assert_equal(1, manager:select_previous().id)
assert_equal(2, manager:select_next().id)
assert_equal(1, manager:select(1).id)

local sent_context = manager:add_context({
  bufnr = context_buffer,
  mode = "v",
  first = { line = 1, col = 2 },
  last = { line = 1, col = 4 },
})
local resolved_context_path = vim.uv.fs_realpath(context_path) or context_path
assert_equal(("@%s:1:2-1:4"):format(resolved_context_path), sent_context)
assert_equal(sent_context, fake_backends[1].sent)
assert_equal(1, fake_sidebar.displayed)

manager:stop(1)
assert_equal("stopped", first.status)
local stopped_context_ok, stopped_context_error = pcall(function()
  manager:add_context({
    bufnr = context_buffer,
    mode = "V",
    first = { line = 1, col = 1 },
    last = { line = 1, col = 1 },
  })
end)
assert_equal(false, stopped_context_ok)
assert_truthy(stopped_context_error:find("active session is not running"))
assert_equal(true, fake_sidebar.visible)
assert_equal(2, #manager:list())
manager:close(1)
assert_equal(true, fake_backends[1].destroyed)
assert_equal(2, manager:active().id)

manager:select(2)
fake_backends[2]:exit(0)
assert_equal("exited", second.status)
assert_equal(false, fake_sidebar.visible)
assert_equal(2, manager:active().id)
assert_equal(true, manager:toggle())
assert_equal(true, fake_sidebar.visible)

local third = manager:start("open", "test")
assert_equal(3, third.id)
fake_backends[3]:wipe()
assert_equal(1, #manager:list())
assert_equal(2, manager:active().id)
assert_equal(2, fake_sidebar.displayed)

local original_select = vim.ui.select
vim.ui.select = function(items, options, callback)
  assert_equal("Select agent chat", options.prompt)
  assert_equal(1, #items)
  callback(items[1])
end
manager:pick()
vim.ui.select = original_select
assert_equal(2, manager:active().id)

fake_controls.fail_start = true
local started, start_error = pcall(function()
  manager:start("open", "test")
end)
fake_controls.fail_start = false
assert_equal(false, started)
assert_truthy(start_error:find("fake launch failure"))
assert_equal(1, #manager:list())
assert_equal(2, manager:active().id)

fake_controls.fail_capture = true
local unavailable_tracking = manager:start("open", "test")
fake_controls.fail_capture = false
assert_equal(nil, unavailable_tracking.change_tracking.baseline)
assert_truthy(unavailable_tracking.change_tracking.error:find("fake tracking unavailable"))
local unavailable_changes_ok, unavailable_changes_error = pcall(function()
  manager:show_changes(unavailable_tracking.id)
end)
assert_equal(false, unavailable_changes_ok)
assert_truthy(unavailable_changes_error:find("fake tracking unavailable"))
manager:close(unavailable_tracking.id)

fake_config.options.close_on_exit = false
local fourth = manager:start("open", "test")
fake_backends[fourth.id]:exit(0)
assert_equal("exited", fourth.status)
assert_equal(true, fake_sidebar.visible)
manager:close_all()
assert_equal(0, #manager:list())
assert_equal(false, fake_sidebar.visible)

session_manager._reset_for_tests()
local shell_provider = adapter.new({
  name = "shell-test",
  command = vim.o.shell,
  actions = {
    open = function()
      return {}
    end,
  },
})
local exit_provider = adapter.new({
  name = "exit-test",
  command = vim.o.shell,
  actions = {
    open = function()
      return {}
    end,
  },
})
providers.register("shell-test", shell_provider)
providers.register("exit-test", exit_provider)
agents.setup({
  default_provider = "shell-test",
  window = { position = "bottom", size = 5 },
  providers = {
    ["shell-test"] = { command = vim.o.shell, args = {} },
    ["exit-test"] = { command = vim.o.shell, args = { "-c", "exit 0" } },
  },
})

-- Starting a terminal must not try to replace the user's modified editing buffer.
local modified_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_win_set_buf(0, modified_buffer)
vim.api.nvim_buf_set_lines(modified_buffer, 0, -1, false, { "unsaved work" })
assert_equal(true, vim.bo[modified_buffer].modified)

commands.execute({ "open", "shell-test" })
assert_equal(true, vim.api.nvim_buf_is_valid(modified_buffer))
assert_equal(true, vim.bo[modified_buffer].modified)
commands.execute({ "open", "shell-test" })
manager = session_manager.get()
local state = manager:state()
assert_equal(2, #state.sessions)
assert_equal(2, state.active_id)
assert_truthy(manager:list()[1].backend:is_running())
assert_truthy(manager:list()[2].backend:is_running())
assert_truthy(state.sessions[1].buffer ~= state.sessions[2].buffer)
assert_equal("Toggle agent terminal", find_mapping(state.sessions[1].buffer, "<C-F><C-F>").desc)
assert_equal("Enter Terminal-Normal mode", find_mapping(state.sessions[1].buffer, "<C-F>f").desc)

local sent_channel = nil
local sent_terminal_text = nil
local original_chan_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(channel, text)
  sent_channel = channel
  sent_terminal_text = text
end
local terminal_send_ok, terminal_send_error = pcall(function()
  manager:list()[2].backend:send("source.lua:2-4")
end)
vim.api.nvim_chan_send = original_chan_send
assert_equal(true, terminal_send_ok)
assert_equal(nil, terminal_send_error)
assert_equal(manager:list()[2].backend.job, sent_channel)
assert_equal("source.lua:2-4", sent_terminal_text)

local editor_window = nil
for _, window in ipairs(vim.api.nvim_list_wins()) do
  if window ~= state.sidebar.window then
    editor_window = window
    break
  end
end
assert_truthy(editor_window)
vim.api.nvim_set_current_win(editor_window)
vim.api.nvim_win_set_buf(editor_window, context_buffer)
vim.api.nvim_win_set_cursor(editor_window, { 1, 1 })
vim.cmd("normal! v2l")
vim.cmd("normal! \27")
sent_channel = nil
sent_terminal_text = nil
original_chan_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(channel, text)
  sent_channel = channel
  sent_terminal_text = text
end
local command_context_ok, command_context_error = pcall(vim.cmd, "'<,'>Agents context")
vim.api.nvim_chan_send = original_chan_send
assert_equal(true, command_context_ok)
assert_equal("", command_context_error)
assert_equal(manager:active().backend.job, sent_channel)
assert_equal(
  ("%s:1:2-1:4"):format(resolved_context_path),
  sent_terminal_text
)
assert_equal(state.sidebar.window, vim.api.nvim_get_current_win())

local sidebar_window = state.sidebar.window
assert_truthy(sidebar_window)
local winbar = vim.wo[sidebar_window].winbar
assert_truthy(winbar:find("1:shell%-test"))
assert_truthy(winbar:find("2:shell%-test"))
_G.AgentsNvimSelectSession(1, 1, "l", "")
assert_equal(1, manager:state().active_id)
assert_equal(state.sessions[1].buffer, vim.api.nvim_win_get_buf(manager:state().sidebar.window))

commands.execute({ "toggle" })
assert_equal(nil, manager:state().sidebar.window)
assert_truthy(manager:list()[1].backend:is_running())
assert_truthy(manager:list()[2].backend:is_running())
commands.execute({ "toggle" })
assert_truthy(manager:state().sidebar.window)

local stopped_buffer = manager:state().sessions[1].buffer
commands.execute({ "stop", "1" })
assert_equal("stopped", manager:state().sessions[1].status)
assert_truthy(vim.api.nvim_buf_is_valid(stopped_buffer))
assert_truthy(vim.wait(1000, function()
  return not manager:list()[1].backend:is_running()
end))
commands.execute({ "close", "1" })
assert_equal(false, vim.api.nvim_buf_is_valid(stopped_buffer))
assert_equal(2, manager:state().active_id)

commands.execute({ "open", "exit-test" })
assert_truthy(vim.wait(1000, function()
  local active = manager:active()
  return active and active.status == "exited"
end))
assert_equal(nil, manager:state().sidebar.window)
assert_equal(2, #manager:list())
commands.execute({ "select", "3" })
assert_truthy(manager:state().sidebar.window)
assert_truthy(vim.wo[manager:state().sidebar.window].winbar:find("3:exit%-test x"))
assert_equal({ "2", "3" }, commands.complete("", "Agents select "))
assert_equal({ "2", "3" }, commands.complete("", "Agents changes "))
assert_equal({ "2", "3" }, commands.complete("", "Agents reset-changes "))

manager:close_all()
vim.api.nvim_buf_delete(modified_buffer, { force = true })
vim.api.nvim_buf_delete(context_buffer, { force = true })
vim.fn.delete(context_root, "rf")
session_manager._reset_for_tests()

print("agents.nvim tests passed")
vim.cmd("quitall!")

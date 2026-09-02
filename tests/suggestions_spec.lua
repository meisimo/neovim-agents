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

local function assert_contains(text, pattern)
  assert_truthy(text:find(pattern, 1, true), ("expected %q to contain %q"):format(text, pattern))
end

local agents = require("agents")
local config = require("agents.config")

agents.setup()
assert_equal({
  enabled = false,
  provider = "claude",
  context_lines = 100,
  max_context_bytes = 64 * 1024,
  timeout_ms = 30 * 1000,
  mappings = {
    request = "<C-f>s",
    accept = "<C-f>a",
    dismiss = "<C-f>x",
  },
}, config.options.suggestions)
assert_equal("", vim.fn.maparg("<C-f>s", "n"))
assert_equal("function", type(agents.suggest))
assert_equal("function", type(agents.accept_suggestion))
assert_equal("function", type(agents.dismiss_suggestion))

local function assert_config_error(options, pattern)
  local ok, err = pcall(agents.setup, options)
  assert_equal(false, ok)
  assert_truthy(err:find(pattern), err)
end

assert_config_error({ suggestions = false }, "suggestions must be a table")
assert_config_error({ suggestions = { enabled = "yes" } }, "enabled must be a boolean")
assert_config_error({ suggestions = { provider = "" } }, "provider must be a non%-empty string")
assert_config_error({ suggestions = { context_lines = 0 } }, "context_lines must be a positive")
assert_config_error(
  { suggestions = { max_context_bytes = 1.5 } },
  "max_context_bytes must be a positive"
)
assert_config_error({ suggestions = { timeout_ms = -1 } }, "timeout_ms must be a positive")
assert_config_error({ suggestions = { mappings = false } }, "mappings must be a table")
assert_config_error(
  { suggestions = { mappings = { request = "" } } },
  "request must be a non%-empty string or false"
)

agents.setup({
  suggestions = {
    enabled = true,
    mappings = { request = "gs", accept = false, dismiss = "gx" },
  },
})
assert_equal("Request inline code suggestion", vim.fn.maparg("gs", "n", false, true).desc)
assert_equal("Dismiss inline code suggestion", vim.fn.maparg("gx", "n", false, true).desc)
assert_equal("", vim.fn.maparg("<C-f>a", "n"))
agents.setup()
assert_equal("", vim.fn.maparg("gs", "n"))
assert_equal("", vim.fn.maparg("gx", "n"))

local commands = require("agents.commands")
assert_equal({ action = "suggest" }, commands.parse({ "suggest" }))
assert_equal({ action = "suggest-accept" }, commands.parse({ "suggest-accept" }))
assert_equal({ action = "suggest-dismiss" }, commands.parse({ "suggest-dismiss" }))
assert_equal(
  { "suggest", "suggest-accept", "suggest-dismiss" },
  commands.complete("suggest", "Agents suggest")
)

local suggestions_module = require("agents.suggestions")
local original_request = suggestions_module.request
local original_accept = suggestions_module.accept
local original_dismiss = suggestions_module.dismiss
suggestions_module.request = function()
  return "requested"
end
suggestions_module.accept = function()
  return "accepted"
end
suggestions_module.dismiss = function()
  return "dismissed"
end
assert_equal("requested", agents.suggest())
assert_equal("accepted", agents.accept_suggestion())
assert_equal("dismissed", agents.dismiss_suggestion())
suggestions_module.request = original_request
suggestions_module.accept = original_accept
suggestions_module.dismiss = original_dismiss

local claude = require("agents.providers.claude")
local request = claude.build_suggestion_request({ prompt = "private source", cwd = "/workspace" }, {
  command = "custom-claude",
  args = { "--model", "sonnet" },
})
assert_equal({
  "custom-claude",
  "--model",
  "sonnet",
  "-p",
  "--permission-mode",
  "dontAsk",
  "--tools",
  "",
  "--disable-slash-commands",
  "--no-session-persistence",
  "--output-format",
  "json",
  "--json-schema",
  claude.suggestion_schema,
}, request.command)
assert_equal("private source", request.stdin)
assert_equal("/workspace", request.cwd)
assert_equal(nil, request.env)
assert_equal(true, claude.supports_suggestions())

local process = require("agents.process")
local original_system = vim.system
local system_call
local process_callback = function() end
local process_handle = { kill = function() end }
vim.system = function(command, options, callback)
  system_call = { command = command, options = options, callback = callback }
  return process_handle
end
assert_equal(process_handle, process.run({
  command = { "agent", "--flag" },
  stdin = "prompt",
  cwd = "/workspace",
  env = { TEST_VARIABLE = "value" },
}, process_callback))
vim.system = original_system
assert_equal({ "agent", "--flag" }, system_call.command)
assert_equal("prompt", system_call.options.stdin)
assert_equal("/workspace", system_call.options.cwd)
assert_equal({ TEST_VARIABLE = "value" }, system_call.options.env)
assert_equal(true, system_call.options.text)
assert_equal(process_callback, system_call.callback)

local context = require("agents.suggestions.context")
local test_path = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "first", "second", "local café = value", "fourth", "fifth" }, test_path)
local bufnr = vim.fn.bufadd(test_path)
vim.fn.bufload(bufnr)
vim.bo[bufnr].filetype = "lua"
vim.api.nvim_win_set_buf(0, bufnr)
vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "unsaved first" })
vim.api.nvim_win_set_cursor(0, { 3, 6 })

local snapshot = context.capture(bufnr, vim.api.nvim_get_current_win(), {
  cwd = vim.fn.fnamemodify(test_path, ":h"),
  context_lines = 1,
  max_context_bytes = 4096,
})
assert_equal(2, snapshot.row)
assert_equal(6, snapshot.col)
assert_equal("lua", snapshot.filetype)
assert_contains(snapshot.prompt, "Path: " .. snapshot.path)
assert_contains(snapshot.prompt, "Filetype: lua")
assert_contains(snapshot.prompt, "second")
assert_contains(snapshot.prompt, "fourth")
assert_truthy(not snapshot.prompt:find("unsaved first", 1, true))
assert_contains(snapshot.prompt, "<cursor_prefix>\nlocal ")
assert_contains(snapshot.prompt, "<cursor_suffix>\ncafé = value")

local boundary_lines = {}
for index = 1, 205 do
  boundary_lines[index] = ("boundary-%03d"):format(index)
end
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, boundary_lines)
vim.api.nvim_win_set_cursor(0, { 103, 0 })
local bounded = context.capture(bufnr, vim.api.nvim_get_current_win(), {
  cwd = snapshot.cwd,
  context_lines = 100,
  max_context_bytes = 1024 * 1024,
})
assert_contains(bounded.prompt, "boundary-003")
assert_contains(bounded.prompt, "boundary-203")
assert_truthy(not bounded.prompt:find("boundary-002", 1, true))
assert_truthy(not bounded.prompt:find("boundary-204", 1, true))

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
  string.rep("before", 40),
  string.rep("é", 300) .. "CURSOR" .. string.rep("界", 300),
  string.rep("after", 40),
})
vim.api.nvim_win_set_cursor(0, { 2, 600 })
local capped = context.capture(bufnr, vim.api.nvim_get_current_win(), {
  cwd = snapshot.cwd,
  context_lines = 100,
  max_context_bytes = 1000,
})
assert_truthy(#capped.prompt <= 1000)
assert_contains(capped.prompt, "[truncated]")
assert_equal(true, context._valid_utf8(capped.prompt))
assert_truthy(not capped.prompt:find(string.rep("before", 40), 1, true))

local unnamed = vim.api.nvim_create_buf(true, false)
local unnamed_ok, unnamed_error = pcall(context.capture, unnamed, vim.api.nvim_get_current_win(), {
  context_lines = 1,
  max_context_bytes = 1000,
})
assert_equal(false, unnamed_ok)
assert_truthy(unnamed_error:find("named file buffer"))
vim.api.nvim_buf_delete(unnamed, { force = true })

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local value = " })
vim.bo[bufnr].modified = false
vim.api.nvim_feedkeys("Auser\27", "xt", false)
vim.api.nvim_win_set_cursor(0, { 1, 6 })

local function new_fixture(overrides)
  overrides = overrides or {}
  local controls = {
    callbacks = {},
    handles = {},
    timers = {},
    notifications = {},
    logs = {},
    requests = {},
  }
  local fake_provider = {
    default_command = "fake",
    supports_suggestions = function()
      return overrides.supported ~= false
    end,
    is_available = function()
      return overrides.available ~= false
    end,
    build_suggestion_request = function(captured)
      return { command = { "fake" }, stdin = captured.prompt, cwd = captured.cwd }
    end,
  }
  local fake_registry = {
    has = function()
      return overrides.registered ~= false
    end,
    get = function()
      return fake_provider
    end,
  }
  local fake_context = {
    capture = function(current_bufnr, winid)
      local cursor = vim.api.nvim_win_get_cursor(winid)
      return {
        bufnr = current_bufnr,
        winid = winid,
        row = cursor[1] - 1,
        col = cursor[2],
        changedtick = vim.api.nvim_buf_get_changedtick(current_bufnr),
        prompt = "captured unsaved source",
        cwd = "/workspace",
      }
    end,
  }
  local runner = function(process_request, callback)
    if overrides.spawn_error then
      error("fake spawn failure")
    end
    table.insert(controls.requests, process_request)
    table.insert(controls.callbacks, callback)
    local handle = { killed = false }
    function handle:kill(signal)
      self.killed = signal
    end
    table.insert(controls.handles, handle)
    return handle
  end
  local timer_factory = function(timeout, callback)
    local timer = { timeout = timeout, callback = callback, closed = false, stopped = false }
    function timer:stop()
      self.stopped = true
    end
    function timer:is_closing()
      return self.closed
    end
    function timer:close()
      self.closed = true
    end
    table.insert(controls.timers, timer)
    return timer
  end
  local fake_config = {
    options = {
      cwd = nil,
      suggestions = {
        enabled = overrides.enabled ~= false,
        provider = "fake",
        context_lines = 10,
        max_context_bytes = 1000,
        timeout_ms = 250,
      },
      providers = { fake = { command = "fake" } },
    },
  }
  local controller = suggestions_module.new({
    config = fake_config,
    context = fake_context,
    providers = fake_registry,
    runner = runner,
    timer_factory = timer_factory,
    schedule = function(callback)
      callback()
    end,
    notify = function(message, level)
      table.insert(controls.notifications, { message = message, level = level })
    end,
    log = {
      error = function(message)
        table.insert(controls.logs, message)
      end,
    },
  })
  return controller, controls
end

local disabled, disabled_controls = new_fixture({ enabled = false })
assert_equal(false, disabled:request())
assert_contains(disabled_controls.notifications[1].message, "inline suggestions are disabled")
assert_equal(0, #disabled_controls.requests)

for _, unsupported_options in ipairs({
  { registered = false },
  { supported = false },
}) do
  local unsupported, unsupported_controls = new_fixture(unsupported_options)
  assert_equal(false, unsupported:request())
  assert_contains(unsupported_controls.notifications[1].message, "does not support")
end

local unavailable, unavailable_controls = new_fixture({ available = false })
assert_equal(false, unavailable:request())
assert_contains(unavailable_controls.notifications[1].message, 'executable "fake" was not found')

local spawn_failure, spawn_controls = new_fixture({ spawn_error = true })
assert_equal(false, spawn_failure:request())
assert_contains(spawn_controls.notifications[1].message, "failed to start")
assert_truthy(#spawn_controls.logs == 1)

vim.api.nvim_win_set_cursor(0, { 1, 6 })
local synchronous_controls = { callback_ran = false }
local synchronous = suggestions_module.new({
  config = {
    options = {
      cwd = nil,
      suggestions = {
        enabled = true,
        provider = "fake",
        context_lines = 1,
        max_context_bytes = 1000,
        timeout_ms = 250,
      },
      providers = { fake = {} },
    },
  },
  context = {
    capture = function(current_bufnr, winid)
      local cursor = vim.api.nvim_win_get_cursor(winid)
      return {
        bufnr = current_bufnr,
        winid = winid,
        row = cursor[1] - 1,
        col = cursor[2],
        changedtick = vim.api.nvim_buf_get_changedtick(current_bufnr),
        prompt = "source",
        cwd = "/workspace",
      }
    end,
  },
  providers = {
    has = function()
      return true
    end,
    get = function()
      return {
        supports_suggestions = function()
          return true
        end,
        is_available = function()
          return true
        end,
        build_suggestion_request = function()
          return { command = { "fake" }, stdin = "source", cwd = "/workspace" }
        end,
      }
    end,
  },
  runner = function(_, callback)
    callback({
      code = 0,
      stdout = vim.json.encode({ structured_output = { suggestion = "sync" } }),
      stderr = "",
    })
    return { kill = function() end }
  end,
  timer_factory = function(_, _)
    return {
      stop = function() end,
      is_closing = function()
        return false
      end,
      close = function() end,
    }
  end,
  schedule = function(callback)
    synchronous_controls.callback_ran = true
    callback()
  end,
  notify = function(message)
    error(message)
  end,
  log = { error = function() end },
})
assert_equal(true, synchronous:request())
assert_equal(true, synchronous_controls.callback_ran)
assert_equal("sync", synchronous.current.text)
assert_equal(true, synchronous:dismiss())

local controller, controls = new_fixture()
assert_equal(true, controller:request())
assert_equal("captured unsaved source", controls.requests[1].stdin)
assert_equal(250, controls.timers[1].timeout)
assert_equal(true, controller:request())
assert_equal(15, controls.handles[1].killed)
controls.callbacks[1]({
  code = 0,
  stdout = vim.json.encode({ structured_output = { suggestion = "old" } }),
  stderr = "",
})
assert_equal(nil, controller.current.text)
controls.callbacks[2]({
  code = 0,
  stdout = vim.json.encode({ structured_output = { suggestion = "result\n\nend" } }),
  stderr = "",
})
assert_equal("result\n\nend", controller.current.text)
assert_equal({ "local value = user" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
local extmarks = vim.api.nvim_buf_get_extmarks(
  bufnr,
  require("agents.suggestions.render").namespace,
  0,
  -1,
  { details = true }
)
assert_equal(1, #extmarks)
assert_equal({ { "result", "AgentsSuggestion" } }, extmarks[1][4].virt_text)
assert_equal(2, #extmarks[1][4].virt_lines)
assert_equal("", extmarks[1][4].virt_lines[1][1][1])

local register_before = vim.fn.getreginfo('"')
local accepted
vim.keymap.set("n", "gA", function()
  accepted = controller:accept()
end)
vim.api.nvim_feedkeys("gA", "xt", false)
vim.keymap.del("n", "gA")
assert_equal(true, accepted)
assert_equal(
  { "local result", "", "endvalue = user" },
  vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
)
assert_equal({ 3, 3 }, vim.api.nvim_win_get_cursor(0))
assert_equal(register_before, vim.fn.getreginfo('"'))
assert_equal(false, controller:accept())
vim.cmd("undo")
assert_equal({ "local value = user" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
vim.cmd("redo")
assert_equal(
  { "local result", "", "endvalue = user" },
  vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
)

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abcdef" })
vim.api.nvim_win_set_cursor(0, { 1, 2 })
local stale_edit, stale_edit_controls = new_fixture()
assert_equal(true, stale_edit:request())
vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { "x" })
stale_edit_controls.callbacks[1]({
  code = 0,
  stdout = vim.json.encode({ structured_output = { suggestion = "ignored" } }),
  stderr = "",
})
assert_equal(nil, stale_edit.current)

vim.api.nvim_win_set_cursor(0, { 1, 2 })
local stale_cursor, stale_cursor_controls = new_fixture()
assert_equal(true, stale_cursor:request())
vim.api.nvim_win_set_cursor(0, { 1, 3 })
stale_cursor_controls.callbacks[1]({
  code = 0,
  stdout = vim.json.encode({ structured_output = { suggestion = "ignored" } }),
  stderr = "",
})
assert_equal(nil, stale_cursor.current)

vim.api.nvim_win_set_cursor(0, { 1, 2 })
local timed_out, timeout_controls = new_fixture()
assert_equal(true, timed_out:request())
timeout_controls.timers[1].callback()
assert_equal(nil, timed_out.current)
assert_equal(15, timeout_controls.handles[1].killed)
assert_contains(timeout_controls.notifications[1].message, "timed out")
timeout_controls.callbacks[1]({
  code = 0,
  stdout = vim.json.encode({ structured_output = { suggestion = "late" } }),
  stderr = "",
})
assert_equal(nil, timed_out.current)

local function completion_error(result, expected)
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  local instance, instance_controls = new_fixture()
  assert_equal(true, instance:request())
  instance_controls.callbacks[1](result)
  assert_equal(nil, instance.current)
  assert_contains(instance_controls.notifications[1].message, expected)
end

completion_error({ code = 2, stdout = "private", stderr = string.rep("e", 3000) }, "code 2")
completion_error({ code = 0, stdout = "not json", stderr = "" }, "malformed")
completion_error({
  code = 0,
  stdout = vim.json.encode({ structured_output = { suggestion = "ok", extra = true } }),
  stderr = "",
}, "malformed")
completion_error({
  code = 0,
  stdout = '{"structured_output":{"suggestion":"' .. string.char(255) .. '"}}',
  stderr = "",
}, "invalid suggestion text")
completion_error({
  code = 0,
  stdout = '{"structured_output":{"suggestion":"a\\u0000b"}}',
  stderr = "",
}, "invalid suggestion text")

vim.api.nvim_win_set_cursor(0, { 1, 2 })
local empty, empty_controls = new_fixture()
assert_equal(true, empty:request())
empty_controls.callbacks[1]({
  code = 0,
  stdout = vim.json.encode({ structured_output = { suggestion = "  \n" } }),
  stderr = "",
})
assert_equal(nil, empty.current)
assert_equal(0, #empty_controls.notifications)

vim.api.nvim_win_set_cursor(0, { 1, 2 })
local autocmd_controller, autocmd_controls = new_fixture()
autocmd_controller:setup()
assert_equal(true, autocmd_controller:request())
vim.api.nvim_exec_autocmds("InsertEnter", { buffer = bufnr })
assert_equal(nil, autocmd_controller.current)
assert_equal(15, autocmd_controls.handles[1].killed)

vim.bo[bufnr].modified = false
assert_equal(true, autocmd_controller:request())
vim.api.nvim_buf_delete(bufnr, { force = true })
assert_equal(nil, autocmd_controller.current)
assert_equal(15, autocmd_controls.handles[2].killed)
vim.fn.delete(test_path)

print("agents.nvim suggestion tests passed")

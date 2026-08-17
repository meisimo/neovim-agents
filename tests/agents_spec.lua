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

assert_equal({ "codex" }, codex.build_command("open", {}, { command = "codex" }))
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
agents.setup()
assert_equal(2, vim.fn.exists(":Agents"))
assert_equal("<C-f><C-f>", require("agents.config").options.mappings.toggle)
assert_equal("<C-f>f", require("agents.config").options.mappings.escape)
assert_equal(true, require("agents.config").options.close_on_exit)
assert_equal(
  { enabled = true, events = { "BufEnter", "FocusGained", "CursorHold" } },
  require("agents.config").options.refresh
)
assert_equal("Toggle agent terminal", vim.fn.maparg("<C-f><C-f>", "n", false, true).desc)
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

local unnamed = vim.api.nvim_create_buf(true, false)
assert_equal(false, refresh.refresh_buffer(unnamed))
vim.bo[unnamed].buftype = "nofile"
assert_equal(false, refresh.refresh_buffer(unnamed))
vim.api.nvim_buf_delete(unnamed, { force = true })
assert_equal(false, refresh.refresh_buffer(unnamed))

agents.setup({ refresh = { events = { "BufEnter", "FocusGained" } } })
local autocmd_count = #vim.api.nvim_get_autocmds({ group = "AgentsNvimRefresh" })
assert_equal(2, autocmd_count)

vim.fn.writefile({ "autocmd refresh" }, refresh_path)
vim.api.nvim_exec_autocmds("BufEnter", { buffer = refresh_buffer })
assert_truthy(vim.wait(1000, function()
  return vim.deep_equal(
    { "autocmd refresh" },
    vim.api.nvim_buf_get_lines(refresh_buffer, 0, -1, false)
  )
end), "BufEnter did not refresh its event buffer")

agents.setup({ refresh = { events = { "BufEnter", "FocusGained" } } })
assert_equal(autocmd_count, #vim.api.nvim_get_autocmds({ group = "AgentsNvimRefresh" }))

local valid, config_error = pcall(agents.setup, {
  refresh = { events = { "BufWritePost" } },
})
assert_equal(false, valid)
assert_truthy(config_error:find("refresh.events%[1%] must be one of"))
agents.setup({ refresh = { enabled = false } })

vim.api.nvim_buf_delete(refresh_buffer, { force = true })
vim.fn.delete(refresh_path)

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
  local controls = { fail_start = false }
  local manager = session_manager.new({
    sidebar = fake_sidebar,
    providers = fake_registry,
    config = fake_config,
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
local first = manager:start("open", "test")
local second = manager:start("open", "test")
assert_equal(1, first.id)
assert_equal(2, second.id)
assert_equal(2, #manager:list())
assert_equal(2, manager:active().id)
assert_equal(true, fake_backends[1].running)
assert_equal(true, fake_backends[2].running)
assert_equal(1, manager:select_previous().id)
assert_equal(2, manager:select_next().id)
assert_equal(1, manager:select(1).id)

manager:stop(1)
assert_equal("stopped", first.status)
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

manager:close_all()
vim.api.nvim_buf_delete(modified_buffer, { force = true })
session_manager._reset_for_tests()

print("agents.nvim tests passed")
vim.cmd("quitall!")

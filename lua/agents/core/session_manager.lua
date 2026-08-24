local config = require("agents.config")
local providers = require("agents.providers")
local terminal = require("agents.backends.terminal")
local sidebar_module = require("agents.ui.sidebar")
local changes_module = require("agents.ui.changes")
local change_tracker = require("agents.workspace.change_tracker")
local context = require("agents.context")

local M = {}

local Manager = {}
Manager.__index = Manager

local default_manager = nil

local function default_sidebar()
  return sidebar_module.new(function()
    return config.options.window
  end)
end

local function default_backend_factory(options)
  return terminal.new(options)
end

local function provider_config(manager, name)
  local value = manager.config.options.providers[name]
  if not value then
    error(("agents.nvim: provider %q is not configured"):format(name))
  end
  return value
end

function M.new(options)
  options = options or {}
  return setmetatable({
    sessions = {},
    order = {},
    active_id = nil,
    next_id = 1,
    sidebar = options.sidebar or default_sidebar(),
    backend_factory = options.backend_factory or default_backend_factory,
    provider_registry = options.providers or providers,
    config = options.config or config,
    change_tracker = options.change_tracker or change_tracker,
    changes_ui = options.changes_ui or changes_module.new(),
  }, Manager)
end

function M.get()
  if not default_manager then
    default_manager = M.new()
  end
  return default_manager
end

function M._reset_for_tests()
  if default_manager then
    default_manager:close_all()
  end
  default_manager = nil
end

function Manager:_ordered_sessions()
  local result = {}
  for _, id in ipairs(self.order) do
    local session = self.sessions[id]
    if session then
      table.insert(result, session)
    end
  end
  return result
end

function Manager:list()
  return self:_ordered_sessions()
end

function Manager:active()
  return self.active_id and self.sessions[self.active_id] or nil
end

function Manager:_session(id)
  id = id or self.active_id
  id = tonumber(id)
  local session = id and self.sessions[id] or nil
  if not session then
    error(id and ("agents.nvim: unknown session %q"):format(id) or "agents.nvim: no active session")
  end
  return session
end

function Manager:_refresh()
  self.sidebar:refresh(self:_ordered_sessions(), self.active_id)
end

function Manager:_show_active()
  local session = self:active()
  if not session then
    self.sidebar:hide()
    return
  end
  self.sidebar:show(session, self:_ordered_sessions(), self.active_id)
end

function Manager:_remove(session)
  self.changes_ui:invalidate(session.id)
  local removed_index = nil
  for index, id in ipairs(self.order) do
    if id == session.id then
      removed_index = index
      table.remove(self.order, index)
      break
    end
  end
  self.sessions[session.id] = nil

  if self.active_id ~= session.id then
    self:_refresh()
    return
  end

  local replacement_id = removed_index and self.order[removed_index] or nil
  self.active_id = replacement_id or self.order[#self.order]
  if self.sidebar:is_visible() then
    self:_show_active()
  end
end

function Manager:_on_exit(session, backend, exit_code)
  local current = self.sessions[session.id]
  if current ~= session or current.backend ~= backend then
    return
  end

  session.exit_code = exit_code
  if session.stop_requested then
    session.stop_requested = nil
    session.status = "stopped"
    self:_refresh()
    return
  end

  session.status = "exited"
  self:_refresh()
  if self.active_id == session.id and self.config.options.close_on_exit ~= false then
    self.sidebar:hide()
  end
end

function Manager:_on_destroy(session, backend)
  local current = self.sessions[session.id]
  if current ~= session or current.backend ~= backend or session.closing then
    return
  end
  self:_remove(session)
end

function Manager:start(action, provider_name, action_options)
  provider_name = provider_name or self.config.options.default_provider
  action_options = action_options or {}

  local provider = self.provider_registry.get(provider_name)
  local options = provider_config(self, provider_name)
  if not provider.supports(action) then
    error(("agents.nvim: provider %q does not support %s"):format(provider_name, action))
  end
  if not provider.is_available(options) then
    local executable = options.command or provider.default_command or provider_name
    error(("agents.nvim: executable %q was not found"):format(executable))
  end

  local id = self.next_id
  local previous_active_id = self.active_id
  local session = {
    id = id,
    provider = provider_name,
    cwd = self.config.options.cwd or vim.fn.getcwd(),
    action = action,
    context_prefix = provider.context_prefix or "",
    status = "starting",
    exit_code = nil,
    change_tracking = {},
  }

  local captured, baseline_or_error = pcall(self.change_tracker.capture, session.cwd)
  if captured then
    session.change_tracking.baseline = baseline_or_error
  else
    session.change_tracking.error = baseline_or_error
  end

  local backend
  backend = self.backend_factory({
    id = id,
    provider = provider_name,
    command = provider.build_command(action, action_options, options),
    cwd = session.cwd,
    mappings = self.config.options.mappings,
    on_toggle = function()
      self:toggle()
    end,
    on_exit = function(exited_backend, exit_code)
      self:_on_exit(session, exited_backend, exit_code)
    end,
    on_destroy = function(destroyed_backend)
      self:_on_destroy(session, destroyed_backend)
    end,
  })
  session.backend = backend

  local started, start_error = pcall(function()
    backend:start()
  end)
  if not started then
    pcall(function()
      backend:destroy()
    end)
    error(start_error)
  end
  session.buffer = backend.bufnr
  session.status = "running"
  self.sessions[id] = session
  table.insert(self.order, id)
  self.active_id = id
  self.next_id = id + 1

  local ok, err = pcall(function()
    self:_show_active()
  end)
  if not ok then
    self.sessions[id] = nil
    table.remove(self.order)
    self.active_id = previous_active_id
    backend:destroy()
    error(err)
  end
  return session
end

function Manager:select(id)
  local session = self:_session(id)
  self.active_id = session.id
  self:_show_active()
  return session
end

function Manager:select_next()
  if #self.order == 0 then
    error("agents.nvim: no sessions to select")
  end
  local index = 1
  for current, id in ipairs(self.order) do
    if id == self.active_id then
      index = current % #self.order + 1
      break
    end
  end
  return self:select(self.order[index])
end

function Manager:select_previous()
  if #self.order == 0 then
    error("agents.nvim: no sessions to select")
  end
  local index = #self.order
  for current, id in ipairs(self.order) do
    if id == self.active_id then
      index = (current - 2) % #self.order + 1
      break
    end
  end
  return self:select(self.order[index])
end

function Manager:pick()
  local sessions = self:_ordered_sessions()
  if #sessions == 0 then
    error("agents.nvim: no sessions to select")
  end
  vim.ui.select(sessions, {
    prompt = "Select agent chat",
    format_item = function(session)
      return ("[%d] %s - %s"):format(session.id, session.provider, session.status)
    end,
  }, function(session)
    if session and self.sessions[session.id] == session then
      self:select(session.id)
    end
  end)
end

function Manager:add_context(selection)
  local session = self:_session()
  if
    session.status ~= "running"
    or type(session.backend.is_running) ~= "function"
    or not session.backend:is_running()
  then
    error("agents.nvim: active session is not running")
  end
  if type(session.backend.send) ~= "function" then
    error("agents.nvim: active session backend cannot accept context")
  end

  local text = context.render(selection, session.cwd, session.context_prefix)
  session.backend:send(text)
  self:_show_active()
  return text
end

function Manager:show_changes(id)
  local session = self:_session(id)
  if not session.change_tracking.baseline then
    error(session.change_tracking.error or "agents.nvim: no change baseline is available", 0)
  end

  local changes, current = self.change_tracker.changes(session.change_tracking.baseline)
  self.changes_ui:pick(session, changes, current)
  return changes
end

function Manager:next_change()
  return self.changes_ui:next()
end

function Manager:previous_change()
  return self.changes_ui:previous()
end

function Manager:reset_changes(id)
  local session = self:_session(id)
  local baseline = self.change_tracker.capture(session.cwd)
  session.change_tracking = { baseline = baseline }
  self.changes_ui:invalidate(session.id)
  return baseline
end

function Manager:stop(id)
  local session = self:_session(id)
  if session.status ~= "running" and session.status ~= "starting" then
    return session
  end
  session.stop_requested = true
  session.status = "stopped"
  session.backend:stop()
  self:_refresh()
  return session
end

function Manager:close(id)
  local session = self:_session(id)
  session.closing = true
  self:_remove(session)
  session.backend:destroy()
end

function Manager:close_all()
  local sessions = self:_ordered_sessions()
  self.sessions = {}
  self.order = {}
  self.active_id = nil
  self.sidebar:hide()
  self.changes_ui:invalidate()
  for _, session in ipairs(sessions) do
    session.closing = true
    session.backend:destroy()
  end
end

function Manager:toggle()
  if self.sidebar:is_visible() then
    self.sidebar:hide()
    return true
  end
  if not self:active() then
    return false
  end
  self:_show_active()
  return true
end

function Manager:state()
  local sessions = {}
  for _, session in ipairs(self:_ordered_sessions()) do
    table.insert(sessions, {
      id = session.id,
      provider = session.provider,
      cwd = session.cwd,
      action = session.action,
      buffer = session.buffer,
      status = session.status,
      exit_code = session.exit_code,
      change_tracking = {
        available = session.change_tracking.baseline ~= nil,
        root = session.change_tracking.baseline and session.change_tracking.baseline.root or nil,
        error = session.change_tracking.error,
      },
    })
  end
  return {
    sessions = sessions,
    active_id = self.active_id,
    next_id = self.next_id,
    sidebar = self.sidebar:state(),
  }
end

return M

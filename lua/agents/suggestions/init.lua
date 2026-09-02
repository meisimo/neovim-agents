local config = require("agents.config")
local context = require("agents.suggestions.context")
local log = require("agents.log")
local process = require("agents.process")
local providers = require("agents.providers")
local render = require("agents.suggestions.render")
local utf8 = require("agents.suggestions.utf8")

local Controller = {}
Controller.__index = Controller

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "agents.nvim" })
end

local function default_timer(timeout_ms, callback)
  local timer = assert(vim.uv.new_timer())
  timer:start(timeout_ms, 0, vim.schedule_wrap(callback))
  return timer
end

local function close_timer(timer)
  if not timer then
    return
  end
  pcall(function()
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
  end)
end

local function split_lines(text)
  return vim.split(text, "\n", { plain = true, trimempty = false })
end

function Controller.new(dependencies)
  dependencies = dependencies or {}
  return setmetatable({
    config = dependencies.config or config,
    context = dependencies.context or context,
    providers = dependencies.providers or providers,
    render = dependencies.render or render,
    runner = dependencies.runner or process.run,
    timer_factory = dependencies.timer_factory or default_timer,
    schedule = dependencies.schedule or vim.schedule,
    notify = dependencies.notify or notify,
    log = dependencies.log or log,
    generation = 0,
    current = nil,
  }, Controller)
end

function Controller:_kill_request(state)
  if state and state.request and type(state.request.kill) == "function" then
    pcall(state.request.kill, state.request, 15)
  end
end

function Controller:_clear(invalidate, terminate)
  local state = self.current
  if invalidate then
    self.generation = self.generation + 1
  end
  if not state then
    return false
  end
  self.current = nil
  close_timer(state.timer)
  if terminate then
    self:_kill_request(state)
  end
  self.render.clear(state.bufnr, state.extmark)
  return true
end

function Controller:_error(message, detail)
  self:_clear(true, false)
  if detail and detail ~= "" then
    self.log.error(message .. "\n" .. detail:sub(1, 2048))
  else
    self.log.error(message)
  end
  self.notify(message, vim.log.levels.ERROR)
end

function Controller:_matches(state)
  if self.current ~= state or state.generation ~= self.generation then
    return false
  end
  if not vim.api.nvim_buf_is_valid(state.bufnr) or not vim.api.nvim_buf_is_loaded(state.bufnr) then
    return false
  end
  if vim.api.nvim_buf_get_changedtick(state.bufnr) ~= state.changedtick then
    return false
  end
  if not vim.api.nvim_win_is_valid(state.winid) then
    return false
  end
  if vim.api.nvim_get_current_win() ~= state.winid then
    return false
  end
  if vim.api.nvim_win_get_buf(state.winid) ~= state.bufnr then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  return cursor[1] - 1 == state.row and cursor[2] == state.col
end

function Controller:_complete(state, result)
  if self.current ~= state or state.generation ~= self.generation then
    return
  end
  close_timer(state.timer)
  state.timer = nil
  state.request = nil

  if not self:_matches(state) then
    self:_clear(true, false)
    return
  end
  if type(result) ~= "table" or result.code ~= 0 then
    local code = type(result) == "table" and result.code or "unknown"
    local stderr = type(result) == "table" and result.stderr or nil
    self:_error(
      ("agents.nvim: %s suggestion request exited with code %s"):format(state.provider, code),
      stderr
    )
    return
  end

  local ok, envelope = pcall(vim.json.decode, result.stdout or "")
  local structured = ok and type(envelope) == "table" and envelope.structured_output or nil
  local suggestion = type(structured) == "table" and structured.suggestion or nil
  local fields = 0
  if type(structured) == "table" then
    for _ in pairs(structured) do
      fields = fields + 1
    end
  end
  if type(suggestion) ~= "string" or fields ~= 1 then
    self:_error(("agents.nvim: %s returned a malformed suggestion response"):format(state.provider))
    return
  end
  if suggestion:find("\0", 1, true) or not utf8.valid(suggestion) then
    self:_error(("agents.nvim: %s returned invalid suggestion text"):format(state.provider))
    return
  end
  if suggestion:match("^%s*$") then
    self:_clear(true, false)
    return
  end

  state.text = suggestion
  local rendered, extmark = pcall(self.render.show, state.bufnr, state.row, state.col, suggestion)
  if not rendered then
    self:_error("agents.nvim: failed to render inline suggestion", extmark)
    return
  end
  state.extmark = extmark
end

function Controller:_timeout(state)
  if self.current ~= state or state.generation ~= self.generation or not state.request then
    return
  end
  self:_clear(true, true)
  self.notify("agents.nvim: inline suggestion request timed out", vim.log.levels.WARN)
end

function Controller:request()
  local options = self.config.options.suggestions
  if not options.enabled then
    self.notify("agents.nvim: inline suggestions are disabled", vim.log.levels.WARN)
    return false
  end

  self:_clear(true, true)
  local provider_name = options.provider
  if not self.providers.has(provider_name) then
    self.notify(
      ("agents.nvim: provider %q does not support inline suggestions"):format(provider_name),
      vim.log.levels.ERROR
    )
    return false
  end
  local provider = self.providers.get(provider_name)
  local provider_options = self.config.options.providers[provider_name] or {}
  if
    type(provider.supports_suggestions) ~= "function"
    or not provider.supports_suggestions(provider_options)
    or type(provider.build_suggestion_request) ~= "function"
  then
    self.notify(
      ("agents.nvim: provider %q does not support inline suggestions"):format(provider_name),
      vim.log.levels.ERROR
    )
    return false
  end
  if not provider.is_available(provider_options) then
    local executable = provider_options.command or provider.default_command or provider_name
    self.notify(
      ("agents.nvim: executable %q was not found"):format(executable),
      vim.log.levels.ERROR
    )
    return false
  end

  local captured_ok, snapshot =
    pcall(self.context.capture, vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), {
      cwd = self.config.options.cwd,
      context_lines = options.context_lines,
      max_context_bytes = options.max_context_bytes,
    })

  if not captured_ok then
    self.notify(snapshot, vim.log.levels.ERROR)
    return false
  end
  local request_ok, request = pcall(provider.build_suggestion_request, snapshot, provider_options)
  if not request_ok then
    self.notify(request, vim.log.levels.ERROR)
    return false
  end

  local state = {
    generation = self.generation,
    provider = provider_name,
    bufnr = snapshot.bufnr,
    winid = snapshot.winid,
    row = snapshot.row,
    col = snapshot.col,
    changedtick = snapshot.changedtick,
  }
  self.current = state
  local starting = true
  local pending_result = nil
  local started, handle = pcall(self.runner, request, function(result)
    if starting then
      pending_result = result
    else
      self.schedule(function()
        self:_complete(state, result)
      end)
    end
  end)
  if not started or not handle or type(handle.kill) ~= "function" then
    starting = false
    self.current = nil
    self.generation = self.generation + 1
    local reason = started and "runner returned an invalid process handle" or handle
    self.log.error(
      ("agents.nvim: failed to start %s suggestion request\n%s"):format(
        provider_name,
        tostring(reason)
      )
    )
    self.notify(
      ("agents.nvim: failed to start %s suggestion request"):format(provider_name),
      vim.log.levels.ERROR
    )
    return false
  end
  state.request = handle

  local timer_ok, timer = pcall(self.timer_factory, options.timeout_ms, function()
    self:_timeout(state)
  end)
  if not timer_ok or not timer then
    starting = false
    self:_clear(true, true)
    self.notify("agents.nvim: failed to start inline suggestion timeout", vim.log.levels.ERROR)
    return false
  end
  state.timer = timer
  starting = false
  if pending_result then
    self.schedule(function()
      self:_complete(state, pending_result)
    end)
  end
  return true
end

function Controller:dismiss()
  return self:_clear(true, true)
end

function Controller:accept()
  local state = self.current
  if not state or not state.text or not self:_matches(state) then
    self:_clear(true, true)
    return false
  end

  local text = state.text
  local bufnr = state.bufnr
  local winid = state.winid
  local row = state.row
  local col = state.col
  local replacement = split_lines(text)
  self:_clear(true, true)
  vim.api.nvim_buf_set_text(bufnr, row, col, row, col, replacement)
  local final_row = row + #replacement - 1
  local final_col = #replacement == 1 and col + #replacement[1] or #replacement[#replacement]
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(winid, { final_row + 1, final_col })
  return true
end

function Controller:handle_event(args)
  local state = self.current
  if not state then
    return
  end
  if args.event == "CursorMoved" or args.event == "CursorMovedI" then
    if not self:_matches(state) then
      self:_clear(true, true)
    end
    return
  end
  if args.buf == state.bufnr then
    self:_clear(true, true)
  end
end

function Controller:setup()
  self:dismiss()
  self.render.setup()
  local group = vim.api.nvim_create_augroup("AgentsNvimSuggestions", { clear = true })
  vim.api.nvim_create_autocmd({
    "BufLeave",
    "BufWipeout",
    "TextChanged",
    "TextChangedI",
    "InsertEnter",
    "CursorMoved",
    "CursorMovedI",
  }, {
    group = group,
    callback = function(args)
      self:handle_event(args)
    end,
  })
end

local singleton = Controller.new()
local M = { Controller = Controller }

function M.setup()
  singleton:setup()
end

function M.request()
  return singleton:request()
end

function M.accept()
  return singleton:accept()
end

function M.dismiss()
  return singleton:dismiss()
end

function M.state()
  return singleton.current
end

function M.new(dependencies)
  return Controller.new(dependencies)
end

return M

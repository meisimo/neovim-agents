local config = require("agents.config")
local log = require("agents.log")
local providers = require("agents.providers")
local session_manager = require("agents.core.session_manager")
local sidebar = require("agents.ui.sidebar")

local M = {}

local actions = {
  "open",
  "resume",
  "continue",
  "toggle",
  "stop",
  "close",
  "next",
  "prev",
  "select",
  "context",
  "health",
}
local registered_toggle_mapping = nil
local registered_context_mapping = nil

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "agents.nvim" })
end

local function start(action, provider_name, options)
  return session_manager.get():start(action, provider_name, options)
end

local function provider_argument(value)
  if value and providers.has(value) then
    return value
  end
  return nil
end

function M.parse(arguments)
  local action = arguments[1]
  local parsed = { action = action }

  if action == "open" or action == "continue" then
    parsed.provider = arguments[2] or config.options.default_provider
  elseif action == "resume" then
    parsed.provider = provider_argument(arguments[2]) or config.options.default_provider
    parsed.session_id = parsed.provider == arguments[2] and arguments[3] or arguments[2]
  elseif action == "stop" or action == "close" or action == "select" then
    parsed.session_id = arguments[2]
  end

  return parsed
end

local function health()
  local lines = {}
  for _, name in ipairs(providers.names()) do
    local provider_options = config.options.providers[name]
    if provider_options then
      local provider = providers.get(name)
      local executable = provider_options.command or provider.default_command or name
      local available = provider.is_available(provider_options)
      table.insert(
        lines,
        ("%s: %s (%s)"):format(name, available and "available" or "not found", executable)
      )
    end
  end
  notify(table.concat(lines, "\n"))
end

function M.execute(arguments, command_options)
  local parsed = M.parse(arguments)
  local action = parsed.action
  if not action or action == "" then
    notify(
      "Usage: Agents <open|resume|continue|toggle|stop|close|next|prev|select|context|health>",
      vim.log.levels.WARN
    )
    return
  end

  local manager = session_manager.get()
  if action == "toggle" then
    if not manager:toggle() then
      start("open", config.options.default_provider, {})
    end
  elseif action == "stop" then
    manager:stop(parsed.session_id)
  elseif action == "close" then
    manager:close(parsed.session_id)
  elseif action == "next" then
    manager:select_next()
  elseif action == "prev" then
    manager:select_previous()
  elseif action == "select" then
    if parsed.session_id then
      manager:select(parsed.session_id)
    else
      manager:pick()
    end
  elseif action == "context" then
    local context = require("agents.context")
    local selection
    if command_options and command_options.from_command then
      selection = context.capture_command(
        command_options.bufnr,
        command_options.line1,
        command_options.line2,
        command_options.range
      )
    else
      selection = context.capture_visual()
    end
    manager:add_context(selection)
  elseif action == "health" then
    health()
  elseif action == "open" then
    start(action, parsed.provider, {})
  elseif action == "resume" then
    start(action, parsed.provider, { session_id = parsed.session_id })
  elseif action == "continue" then
    start(action, parsed.provider, {})
  else
    error(("agents.nvim: unknown action %q"):format(action))
  end
end

function M.execute_safe(arguments, command_options)
  local ok, err = xpcall(function()
    M.execute(arguments, command_options)
  end, debug.traceback)
  if not ok then
    log.error(err)
    notify(err, vim.log.levels.ERROR)
  end
  return ok, err
end

local function matching(values, prefix)
  return vim.tbl_filter(function(item)
    return vim.startswith(item, prefix)
  end, values)
end

function M.complete(argument_lead, command_line)
  local parts = vim.split(command_line, "%s+", { trimempty = true })
  if #parts <= 1 or (#parts == 2 and not command_line:match("%s$")) then
    return matching(actions, argument_lead)
  end
  if
    (parts[2] == "open" or parts[2] == "resume" or parts[2] == "continue")
    and (#parts == 2 or (#parts == 3 and not command_line:match("%s$")))
  then
    return matching(providers.names(), argument_lead)
  end
  if
    (parts[2] == "select" or parts[2] == "stop" or parts[2] == "close")
    and (#parts == 2 or (#parts == 3 and not command_line:match("%s$")))
  then
    local session_ids = {}
    for _, session in ipairs(session_manager.get():list()) do
      table.insert(session_ids, tostring(session.id))
    end
    return matching(session_ids, argument_lead)
  end
  return {}
end

function M.register()
  sidebar.install_click_handler()
  vim.api.nvim_create_user_command("Agents", function(options)
    M.execute_safe(options.fargs, {
      from_command = true,
      bufnr = vim.api.nvim_get_current_buf(),
      line1 = options.line1,
      line2 = options.line2,
      range = options.range,
    })
  end, {
    nargs = "*",
    range = true,
    complete = M.complete,
    desc = "Manage coding-agent CLI sessions",
    force = true,
  })

  if registered_toggle_mapping then
    pcall(vim.keymap.del, "n", registered_toggle_mapping)
  end
  registered_toggle_mapping = config.options.mappings.toggle or nil
  if registered_toggle_mapping then
    vim.keymap.set("n", registered_toggle_mapping, function()
      M.execute_safe({ "toggle" })
    end, {
      desc = "Toggle agent terminal",
      silent = true,
    })
  end

  if registered_context_mapping then
    pcall(vim.keymap.del, "x", registered_context_mapping)
  end
  registered_context_mapping = config.options.mappings.context or nil
  if registered_context_mapping then
    vim.keymap.set("x", registered_context_mapping, function()
      M.execute_safe({ "context" })
    end, {
      desc = "Add file range to agent chat",
      silent = true,
    })
  end
end

return M

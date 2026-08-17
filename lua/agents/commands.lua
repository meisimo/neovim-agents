local config = require("agents.config")
local providers = require("agents.providers")
local terminal = require("agents.terminal")

local M = {}

local actions = { "open", "resume", "continue", "toggle", "stop", "health" }
local registered_toggle_mapping = nil

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "agents.nvim" })
end

local function provider_config(name)
  local value = config.options.providers[name]
  if not value then
    error(("agents.nvim: provider %q is not configured"):format(name))
  end
  return value
end

local function start(action, provider_name, options)
  local provider = providers.get(provider_name)
  local provider_options = provider_config(provider_name)
  if not provider.supports(action) then
    error(("agents.nvim: provider %q does not support %s"):format(provider_name, action))
  end
  if not provider.is_available(provider_options) then
    local executable = provider_options.command or provider.default_command or provider_name
    error(("agents.nvim: executable %q was not found"):format(executable))
  end

  terminal.open(provider.build_command(action, options, provider_options), {
    provider = provider_name,
    cwd = config.options.cwd or vim.fn.getcwd(),
    window = config.options.window,
    mappings = config.options.mappings,
  })
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

function M.execute(arguments)
  local parsed = M.parse(arguments)
  local action = parsed.action
  if not action or action == "" then
    notify("Usage: Agents <open|resume|continue|toggle|stop|health>", vim.log.levels.WARN)
    return
  end

  if action == "toggle" then
    if not terminal.toggle(config.options.window) then
      start("open", config.options.default_provider, {})
    end
  elseif action == "stop" then
    terminal.stop()
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
  return {}
end

function M.register()
  vim.api.nvim_create_user_command("Agents", function(options)
    local ok, err = pcall(M.execute, options.fargs)
    if not ok then
      notify(err, vim.log.levels.ERROR)
    end
  end, {
    nargs = "*",
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
      M.execute({ "toggle" })
    end, {
      desc = "Toggle agent terminal",
      silent = true,
    })
  end
end

return M

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
  if not provider.is_available(provider_options) then
    error(("agents.nvim: executable %q was not found"):format(provider_options.command))
  end

  terminal.open(provider.build_command(action, options, provider_options), {
    provider = provider_name,
    cwd = config.options.cwd or vim.fn.getcwd(),
    window = config.options.window,
    mappings = config.options.mappings,
  })
end

local function health()
  local lines = {}
  for _, name in ipairs(providers.names()) do
    local provider_options = config.options.providers[name]
    if provider_options then
      local available = providers.get(name).is_available(provider_options)
      table.insert(
        lines,
        ("%s: %s (%s)"):format(
          name,
          available and "available" or "not found",
          provider_options.command
        )
      )
    end
  end
  notify(table.concat(lines, "\n"))
end

function M.execute(arguments)
  local action = arguments[1]
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
    start(action, arguments[2] or config.options.default_provider, {})
  elseif action == "resume" then
    start(action, config.options.default_provider, { session_id = arguments[2] })
  elseif action == "continue" then
    start(action, config.options.default_provider, {})
  else
    error(("agents.nvim: unknown action %q"):format(action))
  end
end

function M.complete(_, command_line)
  local parts = vim.split(command_line, "%s+", { trimempty = true })
  if #parts <= 1 or (#parts == 2 and not command_line:match("%s$")) then
    local prefix = parts[2] or ""
    return vim.tbl_filter(function(item)
      return vim.startswith(item, prefix)
    end, actions)
  end
  if parts[2] == "open" then
    return providers.names()
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

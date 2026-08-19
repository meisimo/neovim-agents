local M = {}

local function assert_type(value, expected, label)
  if type(value) ~= expected then
    error(("agents.nvim: provider %s must be a %s"):format(label, expected))
  end
end

---Create a provider from action-to-arguments builders.
---@param spec { name: string, command: string, context_prefix?: string, actions: table<string, function> }
---@return table
function M.new(spec)
  assert_type(spec, "table", "specification")
  assert_type(spec.name, "string", "name")
  assert_type(spec.command, "string", "command")
  assert_type(spec.actions, "table", "actions")
  if spec.context_prefix ~= nil then
    assert_type(spec.context_prefix, "string", "context prefix")
  end
  for action, builder in pairs(spec.actions) do
    assert_type(action, "string", "action name")
    assert_type(builder, "function", ("action %q"):format(action))
  end

  local provider = {
    name = spec.name,
    default_command = spec.command,
    context_prefix = spec.context_prefix or "",
  }

  function provider.supports(action)
    return spec.actions[action] ~= nil
  end

  function provider.is_available(config)
    config = config or {}
    return vim.fn.executable(config.command or spec.command) == 1
  end

  function provider.build_command(action, options, config)
    local build_arguments = spec.actions[action]
    if not build_arguments then
      error(("agents.nvim: %s does not support action %q"):format(spec.name, action))
    end

    options = options or {}
    config = config or {}

    local configured_arguments = config.args or {}
    if type(configured_arguments) ~= "table" then
      error(("agents.nvim: %s args must be a list"):format(spec.name))
    end

    local command = { config.command or spec.command }
    vim.list_extend(command, vim.deepcopy(configured_arguments))

    local arguments = build_arguments(options, config)
    if type(arguments) ~= "table" then
      error(("agents.nvim: %s action %q must return an argument list"):format(spec.name, action))
    end
    vim.list_extend(command, arguments)
    return command
  end

  return provider
end

return M

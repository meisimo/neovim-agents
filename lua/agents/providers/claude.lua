local M = {
  name = "claude",
}

function M.is_available(config)
  return vim.fn.executable(config.command) == 1
end

function M.build_command(action, options, config)
  options = options or {}
  config = config or {}

  local command = { config.command or "claude" }
  vim.list_extend(command, config.args or {})

  if action == "open" then
    -- Interactive mode starts a new persisted conversation without flags.
  elseif action == "resume" then
    table.insert(command, "--resume")
    if options.session_id and options.session_id ~= "" then
      table.insert(command, options.session_id)
    end
  elseif action == "continue" then
    table.insert(command, "--continue")
  else
    error(("agents.nvim: Claude does not support action %q"):format(action))
  end

  return command
end

return M

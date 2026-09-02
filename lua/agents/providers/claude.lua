local adapter = require("agents.providers.adapter")

local provider = adapter.new({
  name = "claude",
  command = "claude",
  context_prefix = "@",
  actions = {
    open = function()
      return {}
    end,
    resume = function(options)
      local arguments = { "--resume" }
      if options.session_id and options.session_id ~= "" then
        table.insert(arguments, options.session_id)
      end
      return arguments
    end,
    continue = function()
      return { "--continue" }
    end,
  },
})

local suggestion_schema = table.concat({
  '{"type":"object","properties":{"suggestion":{"type":"string"}},',
  '"required":["suggestion"],"additionalProperties":false}',
})

function provider.supports_suggestions()
  return true
end

function provider.build_suggestion_request(request, config)
  config = config or {}
  local command = { config.command or provider.default_command }
  local configured_arguments = config.args or {}
  if type(configured_arguments) ~= "table" then
    error("agents.nvim: claude args must be a list")
  end
  vim.list_extend(command, vim.deepcopy(configured_arguments))
  vim.list_extend(command, {
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
    suggestion_schema,
  })
  return {
    command = command,
    stdin = request.prompt,
    cwd = request.cwd,
    env = nil,
  }
end

provider.suggestion_schema = suggestion_schema

return provider

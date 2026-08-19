local M = {}

local providers = {
  claude = "agents.providers.claude",
  codex = "agents.providers.codex",
}

local function validate(name, provider)
  if type(provider) ~= "table" then
    error(("agents.nvim: provider %q must be a table"):format(name))
  end
  for _, method in ipairs({ "is_available", "build_command", "supports" }) do
    if type(provider[method]) ~= "function" then
      error(("agents.nvim: provider %q must implement %s()"):format(name, method))
    end
  end
  if provider.context_prefix ~= nil and type(provider.context_prefix) ~= "string" then
    error(("agents.nvim: provider %q context_prefix must be a string"):format(name))
  end
  return provider
end

function M.names()
  local names = vim.tbl_keys(providers)
  table.sort(names)
  return names
end

function M.get(name)
  local provider = providers[name]
  if not provider then
    error(("agents.nvim: unknown provider %q"):format(name))
  end
  if type(provider) == "string" then
    provider = validate(name, require(provider))
    providers[name] = provider
  end
  return provider
end

function M.has(name)
  return providers[name] ~= nil
end

function M.register(name, provider)
  if type(name) ~= "string" or name == "" then
    error("agents.nvim: provider name must be a non-empty string")
  end
  providers[name] = validate(name, provider)
end

return M

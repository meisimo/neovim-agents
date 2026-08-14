local M = {}

local providers = {
  claude = "agents.providers.claude",
}

function M.names()
  local names = vim.tbl_keys(providers)
  table.sort(names)
  return names
end

function M.get(name)
  local module = providers[name]
  if not module then
    error(("agents.nvim: unknown provider %q"):format(name))
  end
  return require(module)
end

return M


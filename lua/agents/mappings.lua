local M = {}

function M.resolve(mappings, action)
  local suffix = mappings[action]
  if suffix == false or suffix == nil then
    return nil
  end

  if suffix == "<prefix>" then
    suffix = mappings.prefix
  end

  return mappings.prefix .. suffix
end

return M

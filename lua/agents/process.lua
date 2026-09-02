local M = {}

function M.run(request, callback)
  local options = {
    text = true,
    stdin = request.stdin,
    cwd = request.cwd,
  }
  if request.env ~= nil then
    options.env = request.env
  end
  return vim.system(request.command, options, callback)
end

return M

local M = {}

local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ":p:h:h:h")

M.directory = plugin_root .. "/logs"
M.path = M.directory .. "/errors.log"

function M.error(message)
  local lines = vim.split(tostring(message), "\n", { plain = true })
  table.insert(lines, 1, ("[%s] ERROR"):format(os.date("%Y-%m-%d %H:%M:%S")))
  table.insert(lines, "")

  -- Logging must never replace the error that we are trying to report.
  pcall(function()
    vim.fn.mkdir(M.directory, "p")
    vim.fn.writefile(lines, M.path, "a")
  end)
end

return M

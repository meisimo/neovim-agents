local M = {}

M.defaults = {
  default_provider = "claude",
  cwd = nil,
  window = {
    position = "right",
    size = 0.4,
  },
  mappings = {
    toggle = "<C-f><C-f>",
    escape = "<C-f>f",
  },
  providers = {
    claude = {
      command = "claude",
      args = {},
    },
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(options)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), options or {})
  return M.options
end

return M

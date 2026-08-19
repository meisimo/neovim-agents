local M = {}

M.defaults = {
  default_provider = "claude",
  cwd = nil,
  close_on_exit = true,
  window = {
    position = "right",
    size = 0.4,
  },
  mappings = {
    toggle = "<C-f><C-f>",
    escape = "<C-f>f",
    context = "<C-f>p",
  },
  refresh = {
    enabled = true,
    events = { "BufEnter", "FocusGained", "CursorHold" },
  },
  providers = {
    claude = {
      command = "claude",
      args = {},
    },
    codex = {
      command = "codex",
      args = {},
    },
  },
}

M.options = vim.deepcopy(M.defaults)

local supported_refresh_events = {
  BufEnter = true,
  CursorHold = true,
  FocusGained = true,
}

local function validate_refresh(options)
  if type(options.refresh) ~= "table" then
    error("agents.nvim: refresh must be a table", 0)
  end
  if type(options.refresh.enabled) ~= "boolean" then
    error("agents.nvim: refresh.enabled must be a boolean", 0)
  end

  local is_list = vim.islist or vim.tbl_islist
  if not is_list(options.refresh.events) then
    error("agents.nvim: refresh.events must be a list", 0)
  end
  for index, event in ipairs(options.refresh.events) do
    if type(event) ~= "string" or not supported_refresh_events[event] then
      error(
        ("agents.nvim: refresh.events[%d] must be one of BufEnter, FocusGained, or CursorHold")
          :format(index),
        0
      )
    end
  end
end

function M.setup(options)
  local resolved = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), options or {})
  validate_refresh(resolved)
  M.options = resolved
  return M.options
end

return M

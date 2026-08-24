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
    prefix = "<C-f>",
    toggle = "<prefix>", -- e.g. <C-f><C-f>
    escape = "f", -- e.g. <C-f>f
    context = "p", -- e.g. <C-f>p
    changes = "d", -- e.g. <C-f>d
    next_change = "dj", -- e.g. <C-f>dj
    previous_change = "dk", -- e.g. <C-f>dk
    next = "l", -- e.g. <C-f>l
    previous = "h", -- e.g. <C-f>h
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

local function validate_mappings(options)
  if type(options.mappings) ~= "table" then
    error("agents.nvim: mappings must be a table", 0)
  end
  if type(options.mappings.prefix) ~= "string" or options.mappings.prefix == "" then
    error("agents.nvim: mappings.prefix must be a non-empty string", 0)
  end
  for _, name in ipairs({
    "toggle",
    "escape",
    "context",
    "changes",
    "next_change",
    "previous_change",
    "next",
    "previous",
  }) do
    local mapping = options.mappings[name]
    if mapping ~= false and type(mapping) ~= "string" then
      error(("agents.nvim: mappings.%s must be a string or false"):format(name), 0)
    end
  end
end

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
        ("agents.nvim: refresh.events[%d] must be one of BufEnter, FocusGained, or CursorHold"):format(
          index
        ),
        0
      )
    end
  end
end

function M.setup(options)
  local resolved = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), options or {})
  validate_mappings(resolved)
  validate_refresh(resolved)
  M.options = resolved
  return M.options
end

return M

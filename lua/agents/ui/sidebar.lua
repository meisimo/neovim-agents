local M = {}

local Sidebar = {}
Sidebar.__index = Sidebar

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function dimension(total, size)
  if size > 0 and size < 1 then
    return math.max(1, math.floor(total * size))
  end
  return math.max(1, math.floor(size))
end

local function escape_statusline(value)
  return value:gsub("%%", "%%%%")
end

function M.new(config_getter)
  return setmetatable({
    window = nil,
    config_getter = config_getter,
  }, Sidebar)
end

function M.install_click_handler()
  _G.AgentsNvimSelectSession = function(minimum_width, _, button)
    if button ~= "l" then
      return
    end
    require("agents.commands").execute_safe({ "select", tostring(minimum_width) })
  end
end

function Sidebar:is_visible()
  if not valid_window(self.window) then
    self.window = nil
    return false
  end
  return true
end

function Sidebar:_open_window()
  local window_config = self.config_getter()
  local position = window_config.position
  local size = window_config.size

  if position == "left" or position == "right" then
    vim.cmd(position == "left" and "topleft vsplit" or "botright vsplit")
    vim.api.nvim_win_set_width(0, dimension(vim.o.columns, size))
  elseif position == "top" or position == "bottom" then
    vim.cmd(position == "top" and "topleft split" or "botright split")
    vim.api.nvim_win_set_height(0, dimension(vim.o.lines, size))
  else
    error(("agents.nvim: invalid window position %q"):format(position))
  end

  self.window = vim.api.nvim_get_current_win()
end

function Sidebar:render(sessions, active_id)
  if not self:is_visible() then
    return
  end

  local parts = {}
  for _, session in ipairs(sessions) do
    local highlight = session.id == active_id and "TabLineSel" or "TabLine"
    local marker = session.status == "running" and "" or " x"
    local label = escape_statusline((" %d:%s%s "):format(session.id, session.provider, marker))
    table.insert(
      parts,
      ("%%#%s#%%%d@v:lua.AgentsNvimSelectSession@%s%%T"):format(highlight, session.id, label)
    )
  end
  table.insert(parts, "%#TabLineFill#%=")
  vim.wo[self.window].winbar = table.concat(parts)
end

function Sidebar:show(session, sessions, active_id)
  if not self:is_visible() then
    self:_open_window()
  else
    vim.api.nvim_set_current_win(self.window)
  end

  if not session.buffer or not vim.api.nvim_buf_is_valid(session.buffer) then
    error(("agents.nvim: session %d has no valid buffer"):format(session.id))
  end

  vim.api.nvim_win_set_buf(self.window, session.buffer)
  self:render(sessions, active_id)
  if session.status == "running" then
    vim.cmd("startinsert")
  else
    vim.cmd("stopinsert")
  end
end

function Sidebar:refresh(sessions, active_id)
  self:render(sessions, active_id)
  if not self:is_visible() or vim.api.nvim_get_current_win() ~= self.window then
    return
  end
  for _, session in ipairs(sessions) do
    if session.id == active_id and session.status ~= "running" then
      vim.cmd("stopinsert")
      return
    end
  end
end

function Sidebar:hide()
  if self:is_visible() then
    vim.api.nvim_win_close(self.window, false)
  end
  self.window = nil
end

function Sidebar:state()
  return { window = self:is_visible() and self.window or nil }
end

return M

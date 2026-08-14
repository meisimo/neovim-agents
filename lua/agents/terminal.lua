local M = {}

local state = {
  buffer = nil,
  job = nil,
  provider = nil,
}

local function valid_buffer()
  return state.buffer and vim.api.nvim_buf_is_valid(state.buffer)
end

local function window_for_buffer()
  if not valid_buffer() then
    return nil
  end
  for _, window in ipairs(vim.fn.win_findbuf(state.buffer)) do
    if vim.api.nvim_win_is_valid(window) then
      return window
    end
  end
end

local function dimension(total, size)
  if size > 0 and size < 1 then
    return math.max(1, math.floor(total * size))
  end
  return math.max(1, math.floor(size))
end

local function open_window(window_config)
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
end

local function set_terminal_mappings(buffer, mappings)
  mappings = mappings or {}

  if mappings.toggle then
    vim.keymap.set("t", mappings.toggle, function()
      M.toggle(require("agents.config").options.window)
    end, {
      buffer = buffer,
      desc = "Toggle agent terminal",
      silent = true,
    })
  end

  if mappings.escape then
    vim.keymap.set("t", mappings.escape, [[<C-\><C-n>]], {
      buffer = buffer,
      desc = "Enter Terminal-Normal mode",
      silent = true,
    })
  end
end

function M.open(command, options)
  M.stop()
  open_window(options.window)

  local buffer = vim.api.nvim_create_buf(false, true)
  state.buffer = buffer
  state.provider = options.provider
  vim.api.nvim_win_set_buf(0, buffer)
  vim.api.nvim_buf_set_name(buffer, ("agents://%s"):format(options.provider))
  vim.bo[buffer].bufhidden = "hide"
  set_terminal_mappings(buffer, options.mappings)

  state.job = vim.fn.termopen(command, {
    cwd = options.cwd,
    on_exit = function(job_id)
      -- A stopped job may exit after its replacement has already started.
      if state.job == job_id then
        state.job = nil
      end
    end,
  })

  if state.job <= 0 then
    local result = state.job
    state.job = nil
    error(("agents.nvim: failed to start terminal job (%d)"):format(result))
  end

  vim.cmd("startinsert")
end

function M.toggle(window_config)
  if not valid_buffer() then
    return false
  end

  local window = window_for_buffer()
  if window then
    vim.api.nvim_win_close(window, false)
  else
    open_window(window_config)
    vim.api.nvim_win_set_buf(0, state.buffer)
    vim.cmd("startinsert")
  end
  return true
end

function M.stop()
  if state.job then
    vim.fn.jobstop(state.job)
    state.job = nil
  end
  if valid_buffer() then
    vim.api.nvim_buf_delete(state.buffer, { force = true })
  end
  state.buffer = nil
  state.provider = nil
end

function M.state()
  return vim.deepcopy(state)
end

return M

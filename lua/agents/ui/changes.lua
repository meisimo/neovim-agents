local refresh = require("agents.workspace.refresh")
local tracker = require("agents.workspace.change_tracker")

local M = {}

local Viewer = {}
Viewer.__index = Viewer

local labels = {
  A = "A",
  C = "C",
  D = "D",
  M = "M",
  R = "R",
}

local function valid_window(window)
  return window and vim.api.nvim_win_is_valid(window)
end

local function valid_tab(tab)
  return tab and vim.api.nvim_tabpage_is_valid(tab)
end

local function escape_statusline(value)
  return value:gsub("%%", "%%%%")
end

local function lines(value)
  if not value or value == "" then
    return { "" }
  end
  local result = vim.split(value, "\n", { plain = true })
  if value:sub(-1) == "\n" then
    table.remove(result)
  end
  return #result > 0 and result or { "" }
end

local function is_binary(value)
  return value and value:find("\0", 1, true) ~= nil
end

local function printable_path(path)
  return vim.fn.strtrans(path)
end

local function display_path(change)
  if change.status == "R" or change.status == "C" then
    return ("%s → %s"):format(printable_path(change.old_path), printable_path(change.path))
  end
  return printable_path(change.path)
end

function M.format_item(change)
  return ("[%s] %s"):format(labels[change.status] or change.status, display_path(change))
end

function M.new(options)
  options = options or {}
  return setmetatable({
    tracker = options.tracker or tracker,
    refresh = options.refresh or refresh,
    review = nil,
    selection_token = nil,
  }, Viewer)
end

function Viewer:_scratch(session_id, side, path, content, message)
  local buffer = vim.api.nvim_create_buf(false, true)
  local name = ("agents://changes/%d/%s/%s"):format(session_id, side, path)
  pcall(vim.api.nvim_buf_set_name, buffer, name)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, message and { message } or lines(content))
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].modified = false
  local filetype = vim.filetype.match({ filename = path })
  if filetype then
    vim.bo[buffer].filetype = filetype
  end
  return buffer
end

function Viewer:_current_buffer(review, change, content)
  if change.status == "D" then
    return self:_scratch(review.session_id, "current", change.path, ""), true
  end

  local path = vim.fs.joinpath(review.root, change.path)
  self.refresh.refresh_path(path)
  if vim.fn.filereadable(path) ~= 1 then
    return self:_scratch(
      review.session_id,
      "current",
      change.path,
      content,
      "File changed again after the review snapshot; showing captured content."
    ), true
  end

  local buffer = vim.fn.bufadd(path)
  vim.fn.bufload(buffer)
  if vim.bo[buffer].modified then
    vim.notify(
      ("%s has unsaved changes; the diff includes the buffer's current contents")
        :format(change.path),
      vim.log.levels.WARN,
      { title = "agents.nvim" }
    )
  end
  return buffer, false
end

local function set_window_buffer(window, buffer)
  vim.api.nvim_win_call(window, function()
    vim.cmd(("hide buffer %d"):format(buffer))
  end)
end

function Viewer:_ensure_windows(review)
  if valid_tab(review.tab) and valid_window(review.left) and valid_window(review.right) then
    vim.api.nvim_set_current_tabpage(review.tab)
    return
  end

  vim.cmd("tabnew")
  review.tab = vim.api.nvim_get_current_tabpage()
  review.right = vim.api.nvim_get_current_win()
  vim.cmd("leftabove vsplit")
  review.left = vim.api.nvim_get_current_win()
end

function Viewer:_clear_scratch(review)
  for _, buffer in ipairs(review.scratch or {}) do
    if vim.api.nvim_buf_is_valid(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
  review.scratch = {}
end

function Viewer:_render()
  local review = self.review
  local change = review and review.changes[review.index] or nil
  if not change then
    error("agents.nvim: no changed file is selected", 0)
  end

  local baseline_path = change.old_path or change.path
  local baseline_content = self.tracker.read(review.baseline, baseline_path)
  local current_content = self.tracker.read(review.current, change.path)
  local binary = is_binary(baseline_content) or is_binary(current_content)
  local baseline_message = binary and "Binary file: textual baseline diff is unavailable." or nil
  local baseline_buffer = self:_scratch(
    review.session_id,
    "baseline",
    baseline_path,
    baseline_content,
    baseline_message
  )
  local current_buffer, current_is_scratch = self:_current_buffer(review, change, current_content)

  self:_ensure_windows(review)
  if valid_window(review.left) then
    vim.wo[review.left].diff = false
  end
  if valid_window(review.right) then
    vim.wo[review.right].diff = false
  end
  local previous_scratch = review.scratch
  review.scratch = { baseline_buffer }
  if current_is_scratch then
    table.insert(review.scratch, current_buffer)
  end

  set_window_buffer(review.left, baseline_buffer)
  set_window_buffer(review.right, current_buffer)
  for _, buffer in ipairs(previous_scratch or {}) do
    if vim.api.nvim_buf_is_valid(buffer) then
      pcall(vim.api.nvim_buf_delete, buffer, { force = true })
    end
  end
  vim.wo[review.left].winbar = escape_statusline(
    (" Baseline · %s "):format(printable_path(baseline_path))
  )
  vim.wo[review.right].winbar = escape_statusline(
    (" Current · %s · %d/%d "):format(
      printable_path(change.path),
      review.index,
      #review.changes
    )
  )
  vim.api.nvim_win_set_cursor(review.left, { 1, 0 })
  vim.api.nvim_win_set_cursor(review.right, { 1, 0 })

  if not binary then
    vim.wo[review.left].diff = true
    vim.wo[review.right].diff = true
  else
    vim.notify(
      ("%s is binary; opening it without a textual diff"):format(change.path),
      vim.log.levels.INFO,
      { title = "agents.nvim" }
    )
  end
  vim.api.nvim_set_current_win(review.right)
end

function Viewer:pick(session, changes, current)
  if #changes == 0 then
    vim.notify("No workspace changes since this session's baseline", vim.log.levels.INFO, {
      title = "agents.nvim",
    })
    return false
  end

  local selection_token = { session_id = session.id }
  self.selection_token = selection_token
  vim.ui.select(changes, {
    prompt = ("Session %d changes since baseline"):format(session.id),
    format_item = M.format_item,
  }, function(change)
    if self.selection_token ~= selection_token then
      return
    end
    self.selection_token = nil
    if not change then
      return
    end
    local index = 1
    for candidate, item in ipairs(changes) do
      if item == change then
        index = candidate
        break
      end
    end
    if self.review then
      self.review.session_id = session.id
      self.review.root = session.change_tracking.baseline.root
      self.review.baseline = session.change_tracking.baseline
      self.review.current = current
      self.review.changes = changes
      self.review.index = index
    else
      self.review = {
        session_id = session.id,
        root = session.change_tracking.baseline.root,
        baseline = session.change_tracking.baseline,
        current = current,
        changes = changes,
        index = index,
        scratch = {},
      }
    end
    self:_render()
  end)
  return true
end

function Viewer:_move(offset)
  if not self.review then
    error("agents.nvim: open a change review with :Agents changes first", 0)
  end
  self.review.index = (self.review.index - 1 + offset) % #self.review.changes + 1
  self:_render()
  return self.review.changes[self.review.index]
end

function Viewer:next()
  return self:_move(1)
end

function Viewer:previous()
  return self:_move(-1)
end

function Viewer:invalidate(session_id)
  if
    self.selection_token
    and (not session_id or self.selection_token.session_id == session_id)
  then
    self.selection_token = nil
  end
  local review = self.review
  if not review or (session_id and review.session_id ~= session_id) then
    return
  end
  if valid_window(review.left) then
    vim.wo[review.left].diff = false
  end
  if valid_window(review.right) then
    vim.wo[review.right].diff = false
    vim.wo[review.right].winbar = ""
  end
  if valid_window(review.left) and valid_window(review.right) then
    pcall(vim.api.nvim_win_close, review.left, true)
  end
  self:_clear_scratch(review)
  self.review = nil
end

function Viewer:state()
  if not self.review then
    return nil
  end
  return {
    session_id = self.review.session_id,
    index = self.review.index,
    count = #self.review.changes,
    tab = self.review.tab,
    left = self.review.left,
    right = self.review.right,
  }
end

return M

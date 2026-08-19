local M = {}

local visual_block = "\22"

local function position(value)
  return {
    line = value[2],
    col = value[3],
  }
end

local function compare(left, right)
  if left.line == right.line then
    return left.col < right.col
  end
  return left.line < right.line
end

local function normalize_positions(first, last)
  if compare(last, first) then
    return last, first
  end
  return first, last
end

local function normalize_mode(mode)
  mode = mode and mode:sub(1, 1) or nil
  if mode == visual_block then
    error("agents.nvim: blockwise selections are not supported")
  end
  if mode ~= "v" and mode ~= "V" then
    error("agents.nvim: context requires a Visual selection")
  end
  return mode
end

local function validate_buffer(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    error("agents.nvim: context source buffer is invalid")
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].buftype ~= "" then
    error("agents.nvim: context requires a loaded file buffer")
  end
  if vim.bo[bufnr].modified then
    error("agents.nvim: save the file before adding it as context")
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or vim.fn.isdirectory(name) == 1 then
    error("agents.nvim: context requires a named file buffer")
  end

  local stat = vim.uv.fs_stat(name)
  if not stat or stat.type ~= "file" then
    error("agents.nvim: context file does not exist on disk")
  end
  return vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
end

local function relative_path(base, target)
  base = vim.fs.normalize(vim.fn.fnamemodify(base, ":p"))
  target = vim.fs.normalize(target)
  base = vim.uv.fs_realpath(base) or base
  target = vim.uv.fs_realpath(target) or target

  if base ~= "/" and not base:match("^%a:/$") then
    base = base:gsub("/$", "")
  end

  if vim.fs.relpath then
    return vim.fs.relpath(base, target) or target
  end

  local prefix = base:sub(-1) == "/" and base or (base .. "/")
  if target:sub(1, #prefix) == prefix then
    return target:sub(#prefix + 1)
  end
  return target
end

local function escape_reference_path(path)
  return path:gsub("`", "\\`")
end

function M.capture_visual(bufnr)
  local mode = normalize_mode(vim.fn.mode(1))
  return {
    bufnr = bufnr or vim.api.nvim_get_current_buf(),
    mode = mode,
    first = position(vim.fn.getpos("v")),
    last = position(vim.fn.getpos(".")),
  }
end

function M.capture_command(bufnr, line1, line2, range)
  if not range or range == 0 then
    error("agents.nvim: context requires a Visual selection")
  end

  local first = position(vim.fn.getpos("'<"))
  local last = position(vim.fn.getpos("'>"))
  local start_position, end_position = normalize_positions(first, last)
  if start_position.line ~= line1 or end_position.line ~= line2 then
    error("agents.nvim: context command must use the current Visual selection")
  end

  return {
    bufnr = bufnr,
    mode = normalize_mode(vim.fn.visualmode()),
    first = first,
    last = last,
  }
end

function M.render(selection, cwd, prefix)
  if type(selection) ~= "table" then
    error("agents.nvim: context selection must be a table")
  end
  if type(cwd) ~= "string" or cwd == "" then
    error("agents.nvim: context session has no working directory")
  end
  prefix = prefix or ""
  if type(prefix) ~= "string" then
    error("agents.nvim: context prefix must be a string")
  end

  local mode = normalize_mode(selection.mode)
  local first, last = normalize_positions(selection.first, selection.last)
  if first.line < 1 or first.col < 1 or last.line < 1 or last.col < 1 then
    error("agents.nvim: context selection is invalid")
  end

  local path = escape_reference_path(relative_path(cwd, validate_buffer(selection.bufnr)))
  local location
  if mode == "V" then
    location = first.line == last.line and tostring(first.line)
      or ("%d-%d"):format(first.line, last.line)
  else
    location = ("%d:%d-%d:%d"):format(first.line, first.col, last.line, last.col)
  end
  return ("%s%s:%s"):format(prefix, path, location)
end

return M

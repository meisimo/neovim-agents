local M = {}
local utf8 = require("agents.suggestions.utf8")

local HEADER = table.concat({
  "Generate a code completion for the insertion point below.",
  "Return only the exact characters to insert.",
  "Preserve the local style and indentation.",
  "Do not use Markdown fences or include an explanation.",
  "Return an empty string when no useful insertion is apparent.",
}, "\n")

local function valid_utf8(text)
  return utf8.valid(text)
end

local function take_prefix(text, limit)
  if #text <= limit then
    return text
  end
  local finish = math.max(0, limit)
  while finish > 0 and not valid_utf8(text:sub(1, finish)) do
    finish = finish - 1
  end
  return text:sub(1, finish)
end

local function take_suffix(text, limit)
  if #text <= limit then
    return text
  end
  local start = #text - math.max(0, limit) + 1
  while start <= #text do
    local byte = text:byte(start)
    if not byte or byte < 128 or byte >= 192 then
      break
    end
    start = start + 1
  end
  return text:sub(start)
end

local function render(snapshot, before, after, prefix, suffix)
  local lines = {
    HEADER,
    "Path: " .. snapshot.path,
    "Filetype: " .. snapshot.filetype,
    "<agents_context>",
    "<before>",
  }
  vim.list_extend(lines, before)
  vim.list_extend(lines, {
    "</before>",
    "<cursor_prefix>",
    prefix,
    "</cursor_prefix>",
    "<cursor_suffix>",
    suffix,
    "</cursor_suffix>",
    "<after>",
  })
  vim.list_extend(lines, after)
  vim.list_extend(lines, { "</after>", "</agents_context>" })
  return table.concat(lines, "\n")
end

local function fit_cursor(snapshot, limit)
  local full = render(snapshot, {}, {}, snapshot.prefix, snapshot.suffix)
  if #full <= limit then
    return snapshot.prefix, snapshot.suffix, full
  end

  local prefix_marker = #snapshot.prefix > 0 and "[truncated]" or ""
  local suffix_marker = #snapshot.suffix > 0 and "[truncated]" or ""
  local fixed = render(snapshot, {}, {}, prefix_marker, suffix_marker)
  local available = limit - #fixed
  if available < 0 then
    return nil, nil, nil
  end

  local prefix_budget = math.floor(available / 2)
  local suffix_budget = available - prefix_budget
  local prefix = take_suffix(snapshot.prefix, prefix_budget)
  local suffix = take_prefix(snapshot.suffix, suffix_budget)
  local unused = available - #prefix - #suffix
  if unused > 0 and #prefix < #snapshot.prefix then
    local extended = take_suffix(snapshot.prefix, prefix_budget + unused)
    if #extended + #suffix <= available then
      prefix = extended
    end
    unused = available - #prefix - #suffix
  end
  if unused > 0 and #suffix < #snapshot.suffix then
    local extended = take_prefix(snapshot.suffix, suffix_budget + unused)
    if #prefix + #extended <= available then
      suffix = extended
    end
  end

  if #prefix < #snapshot.prefix then
    prefix = "[truncated]" .. prefix
  end
  if #suffix < #snapshot.suffix then
    suffix = suffix .. "[truncated]"
  end
  local prompt = render(snapshot, {}, {}, prefix, suffix)
  if #prompt > limit then
    return nil, nil, nil
  end
  return prefix, suffix, prompt
end

local function absolute_path(path)
  local normalized = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  return vim.uv.fs_realpath(normalized) or normalized
end

function M.capture(bufnr, winid, options)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    error("agents.nvim: inline suggestions require a loaded file buffer", 0)
  end
  if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
    error("agents.nvim: inline suggestions require a named file buffer", 0)
  end
  if not vim.bo[bufnr].modifiable then
    error("agents.nvim: inline suggestions require a modifiable buffer", 0)
  end
  if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
    error("agents.nvim: inline suggestions require the current buffer window", 0)
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row = cursor[1] - 1
  local col = cursor[2]
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor_line = all_lines[row + 1] or ""
  if col > #cursor_line then
    error("agents.nvim: cursor is outside the current line", 0)
  end

  local cwd = options.cwd or vim.fn.getcwd(-1, -1)
  local snapshot = {
    bufnr = bufnr,
    winid = winid,
    row = row,
    col = col,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    path = absolute_path(vim.api.nvim_buf_get_name(bufnr)),
    cwd = absolute_path(cwd),
    filetype = vim.bo[bufnr].filetype,
    prefix = cursor_line:sub(1, col),
    suffix = cursor_line:sub(col + 1),
  }

  local prefix, suffix, prompt = fit_cursor(snapshot, options.max_context_bytes)
  if not prompt then
    error("agents.nvim: inline suggestion prompt metadata exceeds max_context_bytes", 0)
  end

  local before = {}
  local after = {}
  for distance = 1, options.context_lines do
    local before_index = row + 1 - distance
    if before_index >= 1 then
      table.insert(before, 1, all_lines[before_index])
      local candidate = render(snapshot, before, after, prefix, suffix)
      if #candidate <= options.max_context_bytes then
        prompt = candidate
      else
        table.remove(before, 1)
      end
    end

    local after_index = row + 1 + distance
    if after_index <= #all_lines then
      table.insert(after, all_lines[after_index])
      local candidate = render(snapshot, before, after, prefix, suffix)
      if #candidate <= options.max_context_bytes then
        prompt = candidate
      else
        table.remove(after)
      end
    end
  end

  snapshot.prompt = prompt
  snapshot.prefix = nil
  snapshot.suffix = nil
  return snapshot
end

M._render = render
M._valid_utf8 = valid_utf8

return M

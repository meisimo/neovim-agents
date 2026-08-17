local M = {}

local augroup_name = "AgentsNvimRefresh"

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function eligible(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return false
  end
  if vim.bo[bufnr].modified then
    return false
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or vim.fn.isdirectory(name) == 1 then
    return false
  end

  local stat = vim.uv.fs_stat(name)
  return stat == nil or stat.type == "file"
end

function M.refresh_buffer(bufnr)
  if not eligible(bufnr) then
    return false
  end

  -- :checktime delegates reload and conflict handling to Neovim. In particular,
  -- it does not replace buffer text directly or clear the modified flag.
  local checked = pcall(vim.cmd, ("silent checktime %d"):format(bufnr))
  return checked
end

function M.refresh_path(path)
  local target = normalize_path(path)
  if not target then
    return 0
  end

  local refreshed = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if eligible(bufnr) and normalize_path(vim.api.nvim_buf_get_name(bufnr)) == target then
      if M.refresh_buffer(bufnr) then
        refreshed = refreshed + 1
      end
    end
  end
  return refreshed
end

function M.refresh_all()
  local refreshed = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if M.refresh_buffer(bufnr) then
      refreshed = refreshed + 1
    end
  end
  return refreshed
end

local function schedule(callback)
  vim.schedule(function()
    pcall(callback)
  end)
end

function M.setup(options)
  local group = vim.api.nvim_create_augroup(augroup_name, { clear = true })
  if not options.enabled then
    return
  end

  local buffer_events = {}
  local focus_gained = false
  for _, event in ipairs(options.events) do
    if event == "FocusGained" then
      focus_gained = true
    elseif not vim.tbl_contains(buffer_events, event) then
      table.insert(buffer_events, event)
    end
  end

  if #buffer_events > 0 then
    vim.api.nvim_create_autocmd(buffer_events, {
      group = group,
      desc = "Refresh externally changed file buffer",
      callback = function(args)
        schedule(function()
          M.refresh_buffer(args.buf)
        end)
      end,
    })
  end

  if focus_gained then
    vim.api.nvim_create_autocmd("FocusGained", {
      group = group,
      desc = "Refresh all externally changed file buffers",
      callback = function()
        schedule(M.refresh_all)
      end,
    })
  end
end

return M

local M = {}

local Backend = {}
Backend.__index = Backend

local function valid_buffer(buffer)
  return buffer and vim.api.nvim_buf_is_valid(buffer)
end

local function assert_option(options, name, expected)
  if type(options[name]) ~= expected then
    error(("agents.nvim: terminal backend option %q must be a %s"):format(name, expected))
  end
end

local function schedule(callback, ...)
  if not callback then
    return
  end
  local arguments = { ... }
  vim.schedule(function()
    callback(unpack(arguments))
  end)
end

function M.new(options)
  options = options or {}
  assert_option(options, "id", "number")
  assert_option(options, "provider", "string")
  assert_option(options, "command", "table")
  assert_option(options, "cwd", "string")

  return setmetatable({
    id = options.id,
    provider = options.provider,
    command = vim.deepcopy(options.command),
    cwd = options.cwd,
    mappings = options.mappings or {},
    on_toggle = options.on_toggle,
    on_exit = options.on_exit,
    on_destroy = options.on_destroy,
    bufnr = nil,
    job = nil,
    destroying = false,
    exit_emitted = false,
  }, Backend)
end

function Backend:_set_mappings()
  if self.mappings.toggle then
    vim.keymap.set("t", self.mappings.toggle, function()
      if self.on_toggle then
        self.on_toggle()
      end
    end, {
      buffer = self.bufnr,
      desc = "Toggle agent terminal",
      silent = true,
    })
  end

  if self.mappings.escape then
    vim.keymap.set("t", self.mappings.escape, [[<C-\><C-n>]], {
      buffer = self.bufnr,
      desc = "Enter Terminal-Normal mode",
      silent = true,
    })
  end
end

function Backend:start()
  if valid_buffer(self.bufnr) or self.job then
    error("agents.nvim: terminal backend is already started")
  end

  local buffer = vim.api.nvim_create_buf(false, true)
  self.bufnr = buffer
  vim.api.nvim_buf_set_name(buffer, ("agents://%d/%s"):format(self.id, self.provider))
  vim.bo[buffer].bufhidden = "hide"
  self:_set_mappings()

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      self.bufnr = nil
      if not self.destroying then
        schedule(self.on_destroy, self)
      end
    end,
  })

  local job
  vim.api.nvim_buf_call(buffer, function()
    job = vim.fn.termopen(self.command, {
      cwd = self.cwd,
      on_exit = function(job_id, exit_code)
        if self.job == job_id then
          self.job = nil
        end
        if self.exit_emitted then
          return
        end
        self.exit_emitted = true
        schedule(self.on_exit, self, exit_code)
      end,
    })
  end)

  if job <= 0 then
    self.destroying = true
    if valid_buffer(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
    self.bufnr = nil
    error(("agents.nvim: failed to start terminal job (%d)"):format(job))
  end

  self.job = job
  return self
end

function Backend:is_running()
  return self.job ~= nil
end

function Backend:send(text)
  if type(text) ~= "string" or text == "" then
    error("agents.nvim: terminal backend can only send non-empty text")
  end
  if not self.job then
    error("agents.nvim: terminal backend is not running")
  end
  vim.api.nvim_chan_send(self.job, text)
  return true
end

function Backend:stop()
  if not self.job then
    return false
  end
  vim.fn.jobstop(self.job)
  return true
end

function Backend:destroy()
  self.destroying = true
  if self.job then
    vim.fn.jobstop(self.job)
    self.job = nil
  end
  if valid_buffer(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
  self.bufnr = nil
end

return M

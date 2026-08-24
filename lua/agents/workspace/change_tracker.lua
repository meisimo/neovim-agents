local M = {}

local function trim_line(value)
  return (value or ""):gsub("[\r\n]+$", "")
end

local function run(root, arguments, environment, allow_failure)
  local command = { "git", "-c", "core.quotepath=false" }
  vim.list_extend(command, arguments)
  local result = vim.system(command, {
    cwd = root,
    env = environment,
    text = false,
  }):wait()

  if result.code ~= 0 and not allow_failure then
    local detail = trim_line(result.stderr)
    if detail == "" then
      detail = ("git exited with status %d"):format(result.code)
    end
    error(("agents.nvim: cannot capture workspace changes: %s"):format(detail), 0)
  end
  return result
end

local function repository_root(cwd)
  local result = run(cwd, { "rev-parse", "--show-toplevel" })
  local root = trim_line(result.stdout)
  if root == "" then
    error("agents.nvim: cannot capture workspace changes: Git worktree root was empty", 0)
  end
  return vim.fs.normalize(root)
end

local function remove_temp_index(path)
  pcall(vim.fn.delete, path)
  pcall(vim.fn.delete, path .. ".lock")
end

local function write_workspace_tree(root)
  local index = vim.fn.tempname()
  local environment = {
    GIT_INDEX_FILE = index,
    GIT_OPTIONAL_LOCKS = "0",
  }

  local ok, tree_or_error = pcall(function()
    local head = run(root, { "rev-parse", "--verify", "HEAD" }, nil, true)
    if head.code == 0 then
      run(root, { "read-tree", "HEAD" }, environment)
    else
      run(root, { "read-tree", "--empty" }, environment)
    end
    run(root, { "add", "-A", "--", "." }, environment)
    return trim_line(run(root, { "write-tree" }, environment).stdout)
  end)

  remove_temp_index(index)
  if not ok then
    error(tree_or_error, 0)
  end
  if tree_or_error == "" then
    error("agents.nvim: cannot capture workspace changes: Git returned an empty tree ID", 0)
  end
  return tree_or_error
end

local function snapshot(root)
  return {
    root = root,
    tree = write_workspace_tree(root),
  }
end

function M.capture(cwd)
  return snapshot(repository_root(cwd))
end

local function parse_changes(output)
  local fields = vim.split(output, "\0", { plain = true, trimempty = true })
  local changes = {}
  local index = 1
  while index <= #fields do
    local raw_status = fields[index]
    local status = raw_status:sub(1, 1)
    index = index + 1

    if status == "R" or status == "C" then
      local old_path = fields[index]
      local path = fields[index + 1]
      if not old_path or not path then
        error("agents.nvim: Git returned an incomplete rename record", 0)
      end
      table.insert(changes, {
        status = status,
        score = tonumber(raw_status:sub(2)),
        old_path = old_path,
        path = path,
      })
      index = index + 2
    else
      local path = fields[index]
      if not path then
        error("agents.nvim: Git returned an incomplete change record", 0)
      end
      table.insert(changes, {
        status = status == "T" and "M" or status,
        path = path,
        type_changed = status == "T" or nil,
      })
      index = index + 1
    end
  end

  table.sort(changes, function(left, right)
    return left.path < right.path
  end)
  return changes
end

function M.changes(baseline)
  if type(baseline) ~= "table" or not baseline.root or not baseline.tree then
    error("agents.nvim: no change baseline is available for this session", 0)
  end

  local current = snapshot(baseline.root)
  local result = run(baseline.root, {
    "diff",
    "--name-status",
    "-z",
    "--find-renames",
    baseline.tree,
    current.tree,
    "--",
  })
  return parse_changes(result.stdout), current
end

function M.read(snapshot_value, path)
  if type(snapshot_value) ~= "table" or not snapshot_value.root or not snapshot_value.tree then
    error("agents.nvim: invalid workspace snapshot", 0)
  end
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local entry = run(snapshot_value.root, {
    "ls-tree",
    "-z",
    snapshot_value.tree,
    "--",
    path,
  }).stdout
  local object = entry:match("^[^ ]+ blob ([0-9a-f]+)\t")
  if not object then
    return nil
  end
  return run(snapshot_value.root, { "cat-file", "blob", object }).stdout
end

return M

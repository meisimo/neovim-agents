local function assert_equal(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
  end
end

local claude = require("agents.providers.claude")

assert_equal({ "claude" }, claude.build_command("open", {}, { command = "claude" }))
assert_equal(
  { "claude", "--resume" },
  claude.build_command("resume", {}, { command = "claude" })
)
assert_equal(
  { "claude", "--resume", "session-123" },
  claude.build_command("resume", { session_id = "session-123" }, { command = "claude" })
)
assert_equal(
  { "custom-claude", "--verbose", "--continue" },
  claude.build_command("continue", {}, { command = "custom-claude", args = { "--verbose" } })
)

local agents = require("agents")
agents.setup()
assert_equal(2, vim.fn.exists(":Agents"))
agents.setup({ window = { position = "bottom" } })
assert_equal("bottom", require("agents.config").options.window.position)
assert_equal(2, vim.fn.exists(":Agents"))
assert_equal("function", type(agents.open))
assert_equal("function", type(agents.resume))
assert_equal("function", type(agents.continue))

print("agents.nvim tests passed")
vim.cmd("quitall!")

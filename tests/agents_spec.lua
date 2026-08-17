local function assert_equal(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
  end
end

local claude = require("agents.providers.claude")
local codex = require("agents.providers.codex")
local providers = require("agents.providers")
local adapter = require("agents.providers.adapter")

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
assert_equal(true, claude.supports("resume"))
assert_equal(false, claude.supports("fork"))

assert_equal({ "codex" }, codex.build_command("open", {}, { command = "codex" }))
assert_equal({ "codex", "resume" }, codex.build_command("resume", {}, { command = "codex" }))
assert_equal(
  { "codex", "resume", "session-456" },
  codex.build_command("resume", { session_id = "session-456" }, { command = "codex" })
)
assert_equal(
  { "custom-codex", "--no-alt-screen", "resume", "--last" },
  codex.build_command(
    "continue",
    {},
    { command = "custom-codex", args = { "--no-alt-screen" } }
  )
)
assert_equal({ "claude", "codex" }, providers.names())

local example = adapter.new({
  name = "example",
  command = "example-agent",
  actions = {
    open = function()
      return { "chat" }
    end,
  },
})
providers.register("example", example)
assert_equal(
  { "example-agent", "--color", "chat" },
  providers.get("example").build_command("open", {}, { args = { "--color" } })
)
assert_equal({ "claude", "codex", "example" }, providers.names())

local agents = require("agents")
agents.setup()
assert_equal(2, vim.fn.exists(":Agents"))
assert_equal("<C-f><C-f>", require("agents.config").options.mappings.toggle)
assert_equal("<C-f>f", require("agents.config").options.mappings.escape)
assert_equal("Toggle agent terminal", vim.fn.maparg("<C-f><C-f>", "n", false, true).desc)
agents.setup({ window = { position = "bottom" } })
assert_equal("bottom", require("agents.config").options.window.position)
assert_equal(2, vim.fn.exists(":Agents"))
assert_equal("function", type(agents.open))
assert_equal("function", type(agents.resume))
assert_equal("function", type(agents.continue))

local commands = require("agents.commands")
assert_equal(
  { action = "open", provider = "codex" },
  commands.parse({ "open", "codex" })
)
assert_equal(
  { action = "resume", provider = "codex", session_id = "session-456" },
  commands.parse({ "resume", "codex", "session-456" })
)
assert_equal(
  { action = "resume", provider = "claude", session_id = "session-123" },
  commands.parse({ "resume", "session-123" })
)
assert_equal(
  { action = "continue", provider = "codex" },
  commands.parse({ "continue", "codex" })
)

local terminal = require("agents.terminal")
terminal.open({ vim.o.shell }, {
  cwd = vim.fn.getcwd(),
  provider = "test",
  window = { position = "bottom", size = 5 },
  mappings = require("agents.config").defaults.mappings,
})
local close_mapping = vim.fn.maparg("<C-f><C-f>", "t", false, true)
local escape_mapping = vim.fn.maparg("<C-f>f", "t", false, true)
assert_equal("Toggle agent terminal", close_mapping.desc)
assert_equal("Enter Terminal-Normal mode", escape_mapping.desc)
assert_equal(1, close_mapping.buffer)
assert_equal(1, escape_mapping.buffer)
assert_equal(1, #vim.fn.win_findbuf(terminal.state().buffer))
assert_equal(true, terminal.toggle({ position = "bottom", size = 5 }))
assert_equal(0, #vim.fn.win_findbuf(terminal.state().buffer))
assert_equal(true, terminal.toggle({ position = "bottom", size = 5 }))
assert_equal(1, #vim.fn.win_findbuf(terminal.state().buffer))
terminal.stop()

print("agents.nvim tests passed")
vim.cmd("quitall!")

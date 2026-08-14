local M = {}

function M.setup(options)
  require("agents.config").setup(options)
  require("agents.commands").register()
end

function M.open(provider)
  require("agents.commands").execute({ "open", provider })
end

function M.resume(session_id)
  require("agents.commands").execute({ "resume", session_id })
end

function M.continue()
  require("agents.commands").execute({ "continue" })
end

function M.toggle()
  require("agents.commands").execute({ "toggle" })
end

function M.stop()
  require("agents.commands").execute({ "stop" })
end

return M

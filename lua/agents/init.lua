local M = {}

function M.setup(options)
  local config = require("agents.config").setup(options)
  require("agents.commands").register()
  require("agents.workspace.refresh").setup(config.refresh)
end

function M.open(provider)
  require("agents.commands").execute({ "open", provider })
end

function M.resume(session_id, provider)
  if provider then
    require("agents.commands").execute({ "resume", provider, session_id })
  else
    require("agents.commands").execute({ "resume", session_id })
  end
end

function M.continue(provider)
  require("agents.commands").execute({ "continue", provider })
end

function M.toggle()
  require("agents.commands").execute({ "toggle" })
end

function M.stop(session_id)
  require("agents.commands").execute({ "stop", session_id })
end

function M.close(session_id)
  require("agents.commands").execute({ "close", session_id })
end

function M.next()
  require("agents.commands").execute({ "next" })
end

function M.previous()
  require("agents.commands").execute({ "prev" })
end

function M.select(session_id)
  require("agents.commands").execute({ "select", session_id })
end

return M

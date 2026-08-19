local adapter = require("agents.providers.adapter")

return adapter.new({
  name = "claude",
  command = "claude",
  context_prefix = "@",
  actions = {
    open = function()
      return {}
    end,
    resume = function(options)
      local arguments = { "--resume" }
      if options.session_id and options.session_id ~= "" then
        table.insert(arguments, options.session_id)
      end
      return arguments
    end,
    continue = function()
      return { "--continue" }
    end,
  },
})

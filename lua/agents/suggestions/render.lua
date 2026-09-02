local M = {}

M.namespace = vim.api.nvim_create_namespace("agents_suggestions")

function M.setup()
  vim.api.nvim_set_hl(0, "AgentsSuggestion", { link = "Comment", default = true })
end

function M.show(bufnr, row, col, text)
  local segments = vim.split(text, "\n", { plain = true, trimempty = false })
  local virtual_lines = {}
  for index = 2, #segments do
    table.insert(virtual_lines, { { segments[index], "AgentsSuggestion" } })
  end
  return vim.api.nvim_buf_set_extmark(bufnr, M.namespace, row, col, {
    virt_text = { { segments[1], "AgentsSuggestion" } },
    virt_text_pos = "inline",
    virt_lines = virtual_lines,
    priority = 50,
  })
end

function M.clear(bufnr, extmark)
  if bufnr and extmark and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.namespace, extmark)
  end
end

return M

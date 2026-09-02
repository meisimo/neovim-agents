local M = {}

local function continuation(byte)
  return byte and byte >= 0x80 and byte <= 0xBF
end

function M.valid(text)
  local index = 1
  while index <= #text do
    local first = text:byte(index)
    if first <= 0x7F then
      index = index + 1
    elseif first >= 0xC2 and first <= 0xDF then
      if not continuation(text:byte(index + 1)) then
        return false
      end
      index = index + 2
    elseif first >= 0xE0 and first <= 0xEF then
      local second = text:byte(index + 1)
      local third = text:byte(index + 2)
      if not continuation(second) or not continuation(third) then
        return false
      end
      if (first == 0xE0 and second < 0xA0) or (first == 0xED and second > 0x9F) then
        return false
      end
      index = index + 3
    elseif first >= 0xF0 and first <= 0xF4 then
      local second = text:byte(index + 1)
      local third = text:byte(index + 2)
      local fourth = text:byte(index + 3)
      if not continuation(second) or not continuation(third) or not continuation(fourth) then
        return false
      end
      if (first == 0xF0 and second < 0x90) or (first == 0xF4 and second > 0x8F) then
        return false
      end
      index = index + 4
    else
      return false
    end
  end
  return true
end

return M

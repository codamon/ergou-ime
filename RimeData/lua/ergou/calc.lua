-- ergou-ime — "=" calculator: =12*3.5+8 → 50
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A small recursive-descent parser: + - * / % ^ and parentheses, decimals.
-- No load()/eval: input never becomes code. The segment is tagged "calc" by
-- the recognizer pattern in the schema (input starting with "=").

local T = {}

local function parse(s)
  local pos = 1
  local function peek() return s:sub(pos, pos) end
  local function skip() while peek() == " " do pos = pos + 1 end end
  local expr, power
  local function number()
    skip()
    local num = s:match("^%d+%.?%d*", pos) or s:match("^%.%d+", pos)
    if not num then return nil end
    pos = pos + #num
    return tonumber(num) + 0.0   -- floats: Lua 5.4 integers wrap silently
  end
  local function atom()
    skip()
    local c = peek()
    if c == "(" then
      pos = pos + 1
      local v = expr()
      skip()
      if peek() ~= ")" or v == nil then return nil end
      pos = pos + 1
      return v
    elseif c == "-" then
      pos = pos + 1
      local v = power()          -- -2^2 = -(2^2)
      return v and -v
    end
    return number()
  end
  power = function()
    local base = atom()
    skip()
    if base and peek() == "^" then
      pos = pos + 1
      local e = power()
      return e and base ^ e
    end
    return base
  end
  local function term()
    local v = power()
    while v do
      skip()
      local op = peek()
      if op ~= "*" and op ~= "/" and op ~= "%" then break end
      pos = pos + 1
      local r = power()
      if not r then return nil end
      if op == "*" then v = v * r
      elseif op == "/" then if r == 0 then return nil end v = v / r
      else if r == 0 then return nil end v = v % r end
    end
    return v
  end
  expr = function()
    local v = term()
    while v do
      skip()
      local op = peek()
      if op ~= "+" and op ~= "-" then break end
      pos = pos + 1
      local r = term()
      if not r then return nil end
      v = op == "+" and v + r or v - r
    end
    return v
  end
  local v = expr()
  skip()
  if pos <= #s then return nil end
  return v
end

local function format(v)
  if v ~= v or v == math.huge or v == -math.huge then return nil end
  if math.abs(v - math.floor(v + 0.5)) < 1e-9 and math.abs(v) < 1e15 then
    return string.format("%d", math.floor(v + 0.5))
  end
  local s = string.format("%.10f", v):gsub("0+$", ""):gsub("%.$", "")
  return s
end

T.parse = parse
T.format = format

function T.func(input, segment, env)
  if not segment:has_tag("calc") then return end
  local expr = input:sub(2)
  if expr == "" then
    yield(Candidate("calc", segment.start, segment._end, "=", "计算：输入算式"))
    return
  end
  local v = parse(expr)
  local result = v and format(v)
  if result then
    yield(Candidate("calc", segment.start, segment._end, result, "= 结果"))
    yield(Candidate("calc", segment.start, segment._end, expr .. "=" .. result, "算式"))
  end
  yield(Candidate("calc", segment.start, segment._end, input, "原样"))
end

return T

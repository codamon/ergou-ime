-- ergou-ime — show the wubi code next to pinyin candidates.
-- SPDX-License-Identifier: GPL-3.0-only
--
--   我  q · trnt        (简码 · 全码)
--   中国  khlg
--
-- Codes come from the compiled reverse lookup of wubi86_jidian (built when
-- ergou_wubi is deployed). Wubi and correction candidates are passed through
-- unchanged. The candidate type is kept, so lua/ergou/auto_commit.lua can
-- still tell wubi from pinyin.
--
-- STATUS: never run. Check ReverseLookup / ShadowCandidate on a Mac (M1.5).

local NO_HINT = { table = true, user_table = true, completion = true, correction = true }

local F = {}

function F.init(env)
  env.reverse = ReverseLookup("wubi86_jidian")
end

local function hint(reverse, text)
  local codes = reverse:lookup(text)
  if not codes or codes == "" then return nil end
  local short, long
  for c in codes:gmatch("%S+") do
    if not short or #c < #short then short = c end
    if not long or #c > #long then long = c end
  end
  if not short then return nil end
  if short == long then return long end
  return short .. " · " .. long
end

function F.func(input, env)
  for cand in input:iter() do
    local h = not NO_HINT[cand.type] and hint(env.reverse, cand.text)
    if h then
      local comment = cand.comment ~= "" and (cand.comment .. "  " .. h) or h
      yield(ShadowCandidate(cand, cand.type, cand.text, comment))
    else
      yield(cand)
    end
  end
end

return F

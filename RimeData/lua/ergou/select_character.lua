-- ergou-ime — 以词定字: [ types the first character of the highlighted
-- candidate, ] the last one.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- For a character that is hard to reach on its own: type a word that has
-- it (chenmo → 沉默) and press ] to get 默. What was already chosen in the
-- same sentence is typed with it, and the keys after the candidate stay
-- to be typed on, as in rime-ice's select_character.lua (which this
-- follows; original: github.com/BlindingDark/rime-lua-select-character).
--
-- Only for candidates that begin and end with a Chinese character: on an
-- English word, an emoji or a symbol the two keys do what they did before
-- (punctuation). Off with ergou/select_character: false (Settings).
--
-- Typed with engine:commit_text, so the single character is not recorded
-- by 自动调频 as if the whole word had been chosen.

local kAccepted, kNoop = 1, 2

local P = {}

function P.init(env)
  env.enabled = env.engine.schema.config:get_bool("ergou/select_character") ~= false
end

local function is_han(cp)
  return cp ~= nil and ((cp >= 0x3400 and cp <= 0x9FFF) or (cp >= 0xF900 and cp <= 0xFAFF)
    or (cp >= 0x20000 and cp <= 0x3134F))
end

-- The first and the last character of `text`, or nil unless both are Chinese.
function P.ends(text)
  if text == nil or text == "" or not utf8.len(text) then return nil end
  local last_at = utf8.offset(text, -1)
  local first, last = utf8.codepoint(text, 1), utf8.codepoint(text, last_at)
  if not (is_han(first) and is_han(last)) then return nil end
  return utf8.char(first), text:sub(last_at)
end

-- Where `text` last occurs in `s` (plain, not a pattern).
local function find_last(s, text)
  local from, to
  local at = 1
  while true do
    local a, b = s:find(text, at, true)
    if not a then break end
    from, to = a, b
    at = a + 1
  end
  return from, to
end

function P.func(key, env)
  if not env.enabled then return kNoop end
  if key:release() or key:ctrl() or key:alt() or key:super() then return kNoop end
  local code = key.keycode
  if code ~= 0x5b and code ~= 0x5d then return kNoop end   -- [ ]

  local context = env.engine.context
  if not context:has_menu() then return kNoop end
  local cand = context:get_selected_candidate()
  local first, last = P.ends(cand and cand.text)
  if not first then return kNoop end
  local char = code == 0x5b and first or last

  -- The sentence as it would be typed now: what was chosen before, this
  -- candidate, then the keys not turned into text yet.
  local whole = context:get_commit_text() or ""
  local input, caret = context.input, context.caret_pos
  local from, to = find_last(whole, cand.text)
  local before, rest = "", ""
  if from then
    before, rest = whole:sub(1, from - 1), whole:sub(to + 1)
  end
  if caret < #input then rest = rest .. input:sub(caret + 1) end
  env.engine:commit_text(before .. char)
  context:clear()
  if rest ~= "" then context:push_input(rest) end
  return kAccepted
end

return P

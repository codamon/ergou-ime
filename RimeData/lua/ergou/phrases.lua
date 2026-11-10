-- ergou-ime — 常用语 by short code (e.g. dz → your address).
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Reads ergou_phrases.txt in the Rime user directory. The input method
-- writes that file from validated settings (RimeUserConfig); lines are
-- "code<TAB>text" with \n and \\ escaped. Reloaded when the file changes:
-- the first line is a checksum of the rest ("# 1a2b…"), so while typing only
-- that line is read (at most once a second), not the whole file.

local T = {}

local function unescape(s)
  return (s:gsub("\\(.)", function(c) return c == "n" and "\n" or c end))
end

local function load(path)
  local map = {}
  local f = io.open(path, "r")
  if not f then return map end
  for line in f:lines() do
    local code, text = line:match("^([a-z]+)\t(.+)$")
    if code then
      map[code] = map[code] or {}
      table.insert(map[code], unescape(text))
    end
  end
  f:close()
  return map
end

-- First line of the file, nil if there is none.
local function stamp(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local line = f:read("*l")
  f:close()
  return line
end

function T.init(env)
  env.path = rime_api.get_user_data_dir() .. "/ergou_phrases.txt"
  env.stamp = stamp(env.path)
  env.map = load(env.path)
  env.checked = os.time()
end

function T.func(input, segment, env)
  if not segment:has_tag("abc") then return end
  -- Pick up edits from Settings without a restart (checked once a second).
  if os.time() ~= env.checked then
    env.checked = os.time()
    local now = stamp(env.path)
    if now ~= env.stamp then
      env.stamp = now
      env.map = load(env.path)
    end
  end
  local list = env.map[input]
  if not list then return end
  for _, text in ipairs(list) do
    local cand = Candidate("phrase_custom", segment.start, segment._end, text, "常用语")
    cand.preedit = input
    cand.quality = 1.05
    yield(cand)
  end
end

T.unescape = unescape
T.load = load
T.stamp = stamp
return T

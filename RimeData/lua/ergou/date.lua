-- ergou-ime — date and time: rq / riqi, sj / shijian, xq / xingqi.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Offered next to the normal candidates (ranked with pinyin, after exact
-- wubi matches), so wubi codes like "rq" keep their characters first.
--
-- With 双拼 (ergou/shuangpin, written by the input method) the short keys
-- are real syllables (小鹤 sj = san, xq = xiu), so only date / time / week
-- trigger there.

local T = {}

local WEEK = { "日", "一", "二", "三", "四", "五", "六" }
local KEYS = {
  rq = "date", riqi = "date", date = "date",
  sj = "time", shijian = "time", time = "time",
  xq = "week", xingqi = "week", week = "week",
}
local SHUANGPIN_KEYS = { date = "date", time = "time", week = "week" }

local function candidates(kind, now)
  local t = os.date("*t", now)
  if kind == "date" then
    return {
      os.date("%Y-%m-%d", now),
      string.format("%d年%d月%d日", t.year, t.month, t.day),
      string.format("%d月%d日 星期%s", t.month, t.day, WEEK[t.wday]),
      os.date("%Y/%m/%d", now),
    }
  elseif kind == "time" then
    return { os.date("%H:%M", now), os.date("%H:%M:%S", now), os.date("%Y-%m-%d %H:%M", now) }
  else
    return { "星期" .. WEEK[t.wday], "周" .. WEEK[t.wday] }
  end
end

T.candidates = candidates

function T.keys(shuangpin)
  return shuangpin and SHUANGPIN_KEYS or KEYS
end

function T.init(env)
  env.keys = T.keys(env.engine.schema.config:get_bool("ergou/shuangpin") == true)
end

function T.func(input, segment, env)
  local kind = (env.keys or KEYS)[input]
  if not kind or not segment:has_tag("abc") then return end
  for _, text in ipairs(candidates(kind, os.time())) do
    local cand = Candidate("date", segment.start, segment._end, text, "")
    -- High enough to come early; ergou.date_after_first (pinyin mode) then
    -- puts them right after the first word (日期, then the dates). In mixed
    -- mode rank.lua places them with the pinyin group, after exact wubi.
    cand.quality = 1.1
    yield(cand)
  end
end

return T

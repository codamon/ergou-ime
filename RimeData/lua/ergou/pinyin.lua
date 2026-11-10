-- ergou-ime — pinyin spelling rules shared by the Lua components.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Answers two questions about a string of a–z keys:
--   is_prefix(s)   can s still turn into pinyin?   ("shan" → yes, "trnt" → no)
--   is_complete(s) is s already whole syllables?    ("shang" → yes)
--
-- The spellings must mirror ergou_pinyin's speller/algebra (base rules, the
-- fuzzy pairs that are on, the typo rules). The input method writes both
-- from the same Settings values (ErgouIME/Engine/RimeUserConfig.swift), so
-- they stay in sync. This mirror is approximate: it is only used to decide
-- whether to wait one key before auto-committing and whether to offer wubi
-- corrections, never to produce candidates.
--
-- STATUS: never run. Verify in M1.5 on a Mac.

local M = {}

-- Syllables of pinyin_simp.dict.yaml (rime-wubi86-jidian@4d08110), without
-- the interjections m, n, ng, hm: with those, almost any key run starting
-- with m/n would count as pinyin.
local BASE = [[
  a ai an ang ao ba bai ban bang bao bei ben
  beng bi bian biao bie bin bing bo bu ca cai can
  cang cao ce cen ceng cha chai chan chang chao che chen
  cheng chi chong chou chu chua chuai chuan chuang chui chun chuo
  ci cong cou cu cuan cui cun cuo da dai dan dang
  dao de dei den deng di dia dian diao die ding diu
  dong dou du duan dui dun duo e ei en eng er
  fa fan fang fei fen feng fiao fo fou fu ga gai
  gan gang gao ge gei gen geng gong gou gu gua guai
  guan guang gui gun guo ha hai han hang hao he hei
  hen heng hong hou hu hua huai huan huang hui hun huo
  ji jia jian jiang jiao jie jin jing jiong jiu ju juan
  jue jun ka kai kan kang kao ke kei ken keng kong
  kou ku kua kuai kuan kuang kui kun kuo la lai lan
  lang lao le lei leng li lia lian liang liao lie lin
  ling liu lo long lou lu luan lue lun luo lv ma
  mai man mang mao me mei men meng mi mian miao mie
  min ming miu mo mou mu na nai nan nang nao ne
  nei nen neng ni nian niang niao nie nin ning niu nong
  nou nu nuan nue nuo nv o ou pa pai pan pang
  pao pei pen peng pi pian piao pie pin ping po pou
  pu qi qia qian qiang qiao qie qin qing qiong qiu qu
  quan que qun ran rang rao re ren reng ri rong rou
  ru ruan rui run ruo sa sai san sang sao se sen
  seng sha shai shan shang shao she shei shen sheng shi shou
  shu shua shuai shuan shuang shui shun shuo si song sou su
  suan sui sun suo ta tai tan tang tao te tei teng
  ti tian tiao tie ting tong tou tu tuan tui tun tuo
  wa wai wan wang wei wen weng wo wu xi xia xian
  xiang xiao xie xin xing xiong xiu xu xuan xue xun ya
  yan yang yao ye yi yin ying yo yong you yu yuan
  yue yun za zai zan zang zao ze zei zen zeng zha
  zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu
  zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan
  zui zun zuo
]]

local function each_word(s)
  return s:gmatch("%S+")
end

-- Rules mirror Rime "derive" rules: each rule maps one spelling to zero or
-- more extra spellings; the original stays.
local function sub(pattern, repl)
  return function(s)
    local out, n = s:gsub(pattern, repl)
    if n > 0 and out ~= s then return out end
  end
end

local BASE_RULES = {
  sub("^([nl])ue$", "%1ve"),
  sub("^([jqxy])u", "%1v"),
  sub("un$", "uen"),
  sub("ui$", "uei"),
  sub("iu$", "iou"),
}

-- Ids are the values of SharedSettings.fuzzyPinyin / ergou/fuzzy.
M.FUZZY = {
  zh_z   = { sub("^zh", "z"), sub("^z([^h])", "zh%1") },
  ch_c   = { sub("^ch", "c"), sub("^c([^h])", "ch%1") },
  sh_s   = { sub("^sh", "s"), sub("^s([^h])", "sh%1") },
  n_l    = { sub("^n", "l"),  sub("^l", "n") },
  en_eng = { sub("en$", "eng"), sub("eng$", "en") },
  in_ing = { sub("in$", "ing"), sub("ing$", "in") },
  an_ang = { sub("an$", "ang"), sub("ang$", "an") },
  f_h    = { sub("^f", "h"),  sub("^h", "f") },
  r_l    = { sub("^r", "l"),  sub("^l", "r") },
}
M.FUZZY_ORDER = { "zh_z", "ch_c", "sh_s", "n_l", "en_eng", "in_ing", "an_ang", "f_h", "r_l" }

local TYPO_RULES = {
  sub("([aeiou])ng$", "%1gn"),          -- shagn → shang
  sub("ong$", "on"),                    -- zhon → zhong
  sub("ao$", "oa"),                     -- hoa → hao
  sub("([iu])a(ng?)$", "a%1%2"),        -- xaing → xiang, gaun → guan
  sub("([iu])ao$", "a%1o"),             -- xaio → xiao
}

local function apply(set, rules)
  for _, rule in ipairs(rules) do
    local add = {}
    for s in pairs(set) do
      local d = rule(s)
      if d then add[#add + 1] = d end
    end
    for _, d in ipairs(add) do set[d] = true end
  end
end

-- fuzzy_ids: list of ids from M.FUZZY that are on; typos: boolean.
-- Returns an opaque table for is_prefix / is_complete.
function M.build(fuzzy_ids, typos)
  local spellings = {}
  for w in each_word(BASE) do spellings[w] = true end
  apply(spellings, BASE_RULES)
  for _, id in ipairs(fuzzy_ids or {}) do
    if M.FUZZY[id] then apply(spellings, M.FUZZY[id]) end
  end
  if typos then apply(spellings, TYPO_RULES) end

  local prefixes, maxlen = {}, 0
  for s in pairs(spellings) do
    if #s > maxlen then maxlen = #s end
    for i = 1, #s do prefixes[s:sub(1, i)] = true end
  end
  return { spellings = spellings, prefixes = prefixes, maxlen = maxlen }
end

-- Reads ergou/fuzzy and ergou/pinyin_correction from the schema config.
function M.from_config(config)
  local ids = {}
  local list = config:get_list("ergou/fuzzy")
  if list then
    for i = 0, list.size - 1 do
      local v = list:get_value_at(i)
      if v then ids[#ids + 1] = v.value end
    end
  end
  local typos = config:get_bool("ergou/pinyin_correction")
  if typos == nil then typos = true end
  return M.build(ids, typos)
end

-- whole = true: s must be whole syllables; false: the last one may be partial.
local function split(t, s, whole)
  s = s:gsub("'", "")
  if s == "" then return false end
  local memo = {}
  local function ok(i)
    if i > #s then return true end
    if memo[i] ~= nil then return memo[i] end
    local result = false
    if not whole and t.prefixes[s:sub(i)] then
      result = true
    else
      for len = math.min(t.maxlen, #s - i + 1), 1, -1 do
        if t.spellings[s:sub(i, i + len - 1)] and ok(i + len) then
          result = true
          break
        end
      end
    end
    memo[i] = result
    return result
  end
  return ok(1)
end

function M.is_prefix(s, t) return split(t, s, false) end
function M.is_complete(s, t) return split(t, s, true) end

return M

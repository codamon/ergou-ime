// ergou-ime — common words that are never learned as "heard" (语音纠正学习).
// SPDX-License-Identifier: GPL-3.0-only
//
// A rule learned from one edit (EditCorrection.outcome) silently replaces
// text in every later voice result, so the heard side must look like a
// name, not an everyday word: otherwise changing "a" to "the" once would
// rewrite every "a" from then on. This list holds the most frequent English
// words (articles, pronouns, auxiliaries, prepositions, conjunctions,
// common verbs, nouns and adjectives) and Chinese function and common
// words. Matching ignores case. Ordinary nouns such as "Orca" are not here
// on purpose: those are the words the recogniser gets wrong.

enum CommonWords {
    static func contains(_ s: String) -> Bool { words.contains(s.lowercased()) }

    private static let words: Set<String> = Set((english + " " + chinese).split(separator: " ").map(String.init))

    private static let english = """
        a an the this that these those there here \
        i me my mine myself you your yours yourself we us our ours ourselves \
        he him his himself she her hers herself it its itself they them their theirs themselves \
        who whom whose which what when where why how whatever whoever \
        am is are was were be been being do does did done doing have has had having \
        will would shall should can could may might must ought \
        isn't aren't wasn't weren't don't doesn't didn't haven't hasn't hadn't \
        won't wouldn't can't cannot couldn't shouldn't mustn't \
        i'm you're we're they're he's she's it's that's there's what's let's \
        i've you've we've they've i'll you'll we'll they'll i'd you'd we'd they'd \
        of in on at to for from by with about against between into through during \
        before after above below up down out off over under again further \
        onto upon within without along across around behind beyond near since until till \
        toward towards via per than like unlike among \
        and or but nor so yet if then else because as while although though unless \
        whether either neither both each every all any some no not none only own same \
        such too very just also even still already much many more most less least few \
        other another enough quite rather really maybe perhaps please yes yeah ok okay \
        oh hi hello hey thanks thank sorry well now never always often sometimes \
        get got gets getting go goes went gone going come comes came coming \
        make makes made making take takes took taken taking give gives gave given \
        see sees saw seen look looks looked looking know knows knew known \
        think thinks thought want wants wanted say says said tell tells told \
        use uses used using find finds found work works worked working \
        call calls called try tries tried ask asks asked need needs needed \
        feel feels felt seem seems seemed leave put keep kept let \
        begin began start started show shows showed help helps helped \
        talk talked turn turned run runs ran move moved live lived \
        bring brought write wrote written read sit stand lose lost pay paid \
        meet met include set change changed open opened close closed \
        play played send sent fix fixed test tests tested check checked \
        add added remove removed buy bought sell sold build built wait \
        time times year years day days week weeks month months hour hours minute minutes \
        today tomorrow yesterday morning night evening \
        way ways thing things people person man men woman women child children \
        world life hand hands part place case point problem problems fact \
        group company number numbers home house room area money job word words \
        name names question questions answer idea file files code data app apps \
        page pages text line lines list email phone \
        one two three four five six seven eight nine ten first second third last next \
        new old good bad great little big small large long short high low \
        right wrong left best better worse worst sure true false real \
        able free full easy hard fine nice early late important different \
        lot lots bit kind sort end back top side
        """

    private static let chinese = """
        的 了 是 在 和 有 我 你 他 她 它 们 这 那 就 也 都 不 没 很 还 又 要 会 能 \
        吗 呢 吧 啊 呀 哦 嗯 着 过 把 被 给 对 从 向 让 跟 与 及 或 而 但 地 得 \
        这个 那个 这些 那些 这里 那里 这儿 那儿 这样 那样 这么 那么 \
        我们 你们 他们 她们 它们 咱们 大家 自己 别人 人家 \
        一个 一些 一下 一点 一样 一起 一直 一定 一般 \
        什么 怎么 怎样 为什么 哪个 哪里 哪儿 多少 几个 \
        可以 可能 应该 需要 不要 不是 不会 不能 不用 \
        没有 就是 但是 因为 所以 然后 现在 已经 还是 如果 \
        或者 而且 并且 虽然 不过 只是 只有 而是 于是 要是 \
        可是 然而 其实 当然 比如 例如 另外 还有 也是 都是 \
        时候 今天 明天 昨天 刚才 马上 以后 以前 之后 之前 最后 后来 \
        知道 觉得 认为 喜欢 希望 看看 好的 好吧 好像 有点 有些 \
        东西 事情 问题 地方 方面 时间 工作 意思 情况 部分 \
        非常 特别 比较 真的 确实 总是 经常 正在 \
        出来 起来 下去 过来 回来 进去 上去 下来 \
        说 看 做 去 来 想 用 叫 找 走 写 读 听 吃 买 \
        说话 看到 听到 做到 想要 开始 继续 完成 发现 \
        大 小 多 少 好 坏 新 老 高 低 长 短 快 慢 \
        一 二 三 四 五 六 七 八 九 十 两 几 个 次 些 点
        """
}

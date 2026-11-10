// ergou-ime — 双拼 and 联想 settings for the pinyin-only mode and prediction.
// SPDX-License-Identifier: GPL-3.0-only
//
// Spelling rules and preedit formats from rime/rime-double-pinyin (GPL-3.0):
// double_pinyin_flypy (小鹤), double_pinyin (自然码), double_pinyin_mspy
// (微软). The algebra turns the dictionary's full-pinyin spellings into
// two-key codes; fuzzy-pinyin rules run first (on full pinyin). Full-pinyin typo rules and initials are not
// used with 双拼.

import Foundation

enum Shuangpin: String, CaseIterable, Identifiable {
    case none, xiaohe, ziranma, microsoft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "全拼"
        case .xiaohe: return "小鹤双拼"
        case .ziranma: return "自然码双拼"
        case .microsoft: return "微软双拼"
        }
    }

    /// Microsoft 双拼 types "ing" with the semicolon key.
    var usesSemicolon: Bool { self == .microsoft }

    var algebra: [String] {
        switch self {
        case .none: return []
        case .xiaohe: return [
            "erase/^xx$/", "derive/^([jqxy])u$/$1v/", "derive/^([aoe])([ioun])$/$1$1$2/",
            "xform/^([aoe])(ng)?$/$1$1$2/", "xform/iu$/Q/", "xform/(.)ei$/$1W/", "xform/uan$/R/",
            "xform/[uv]e$/T/", "xform/un$/Y/", "xform/^sh/U/", "xform/^ch/I/", "xform/^zh/V/",
            "xform/uo$/O/", "xform/ie$/P/", "xform/i?ong$/S/", "xform/ing$|uai$/K/",
            "xform/(.)ai$/$1D/", "xform/(.)en$/$1F/", "xform/(.)eng$/$1G/", "xform/[iu]ang$/L/",
            "xform/(.)ang$/$1H/", "xform/ian$/M/", "xform/(.)an$/$1J/", "xform/(.)ou$/$1Z/",
            "xform/[iu]a$/X/", "xform/iao$/N/", "xform/(.)ao$/$1C/", "xform/ui$/V/", "xform/in$/B/",
            "xlit/QWRTYUIOPSDFGHJKLZXCVBNM/qwrtyuiopsdfghjklzxcvbnm/",
        ]
        case .ziranma: return [
            "erase/^xx$/", "derive/^([jqxy])u$/$1v/", "derive/^([aoe])([ioun])$/$1$1$2/",
            "xform/^([aoe])(ng)?$/$1$1$2/", "xform/iu$/Q/", "xform/[iu]a$/W/", "xform/[uv]an$/R/",
            "xform/[uv]e$/T/", "xform/ing$|uai$/Y/", "xform/^sh/U/", "xform/^ch/I/", "xform/^zh/V/",
            "xform/uo$/O/", "xform/[uv]n$/P/", "xform/i?ong$/S/", "xform/[iu]ang$/D/",
            "xform/(.)en$/$1F/", "xform/(.)eng$/$1G/", "xform/(.)ang$/$1H/", "xform/ian$/M/",
            "xform/(.)an$/$1J/", "xform/iao$/C/", "xform/(.)ao$/$1K/", "xform/(.)ai$/$1L/",
            "xform/(.)ei$/$1Z/", "xform/ie$/X/", "xform/ui$/V/", "xform/(.)ou$/$1B/", "xform/in$/N/",
            "xlit/QWRTYUIOPSDFGHMJCKLZXVBN/qwrtyuiopsdfghmjcklzxvbn/",
        ]
        case .microsoft: return [
            "erase/^xx$/", "derive/^([jqxy])u$/$1v/", "derive/^([aoe].*)$/o$1/",
            "xform/^([ae])(.*)$/$1$1$2/", "xform/iu$/Q/", "xform/[iu]a$/W/", "xform/er$|[uv]an$/R/",
            "xform/[uv]e$/T/", "xform/v$|uai$/Y/", "xform/^sh/U/", "xform/^ch/I/", "xform/^zh/V/",
            "xform/uo$/O/", "xform/[uv]n$/P/", "xform/i?ong$/S/", "xform/[iu]ang$/D/",
            "xform/(.)en$/$1F/", "xform/(.)eng$/$1G/", "xform/(.)ang$/$1H/", "xform/ian$/M/",
            "xform/(.)an$/$1J/", "xform/iao$/C/", "xform/(.)ao$/$1K/", "xform/(.)ai$/$1L/",
            "xform/(.)ei$/$1Z/", "xform/ie$/X/", "xform/ui$/V/", "derive/T$/V/", "xform/(.)ou$/$1B/",
            "xform/in$/N/", "xform/ing$/;/",
            "xlit/QWRTYUIOPSDFGHMJCKLZXVBN/qwrtyuiopsdfghmjcklzxvbn/",
        ]
        }
    }

    /// translator/preedit_format from the same upstream schemas: shows the
    /// two-key codes as full pinyin in the marked text ("vs" → "zhong").
    /// Empty for full pinyin (the schema's own rules apply).
    var preeditFormat: [String] {
        switch self {
        case .none: return []
        case .xiaohe: return [
            "xform/([bpmfdtnljqx])n/$1iao/", "xform/(\\w)g/$1eng/", "xform/(\\w)q/$1iu/",
            "xform/(\\w)w/$1ei/", "xform/([dtnlgkhjqxyvuirzcs])r/$1uan/", "xform/(\\w)t/$1ve/",
            "xform/(\\w)y/$1un/", "xform/([dtnlgkhvuirzcs])o/$1uo/", "xform/(\\w)p/$1ie/",
            "xform/([jqx])s/$1iong/", "xform/(\\w)s/$1ong/", "xform/(\\w)d/$1ai/", "xform/(\\w)f/$1en/",
            "xform/(\\w)h/$1ang/", "xform/(\\w)j/$1an/", "xform/([gkhvuirzcs])k/$1uai/",
            "xform/(\\w)k/$1ing/", "xform/([jqxnl])l/$1iang/", "xform/(\\w)l/$1uang/", "xform/(\\w)z/$1ou/",
            "xform/([gkhvuirzcs])x/$1ua/", "xform/(\\w)x/$1ia/", "xform/(\\w)c/$1ao/",
            "xform/([dtgkhvuirzcs])v/$1ui/", "xform/(\\w)b/$1in/", "xform/(\\w)m/$1ian/",
            "xform/([aoe])\\1(\\w)/$1$2/", "xform/(^|[ '])v/$1zh/", "xform/(^|[ '])i/$1ch/",
            "xform/(^|[ '])u/$1sh/", "xform/([jqxy])v/$1u/", "xform/([nl])v/$1ü/",
        ]
        case .ziranma: return [
            "xform/([bpmnljqxy])n/$1in/", "xform/(\\w)g/$1eng/", "xform/(\\w)q/$1iu/",
            "xform/([gkhvuirzcs])w/$1ua/", "xform/(\\w)w/$1ia/", "xform/([dtnlgkhjqxyvuirzcs])r/$1uan/",
            "xform/(\\w)t/$1ve/", "xform/([gkhvuirzcs])y/$1uai/", "xform/(\\w)y/$1ing/",
            "xform/([dtnlgkhvuirzcs])o/$1uo/", "xform/(\\w)p/$1un/", "xform/([jqx])s/$1iong/",
            "xform/(\\w)s/$1ong/", "xform/([jqxnl])d/$1iang/", "xform/(\\w)d/$1uang/", "xform/(\\w)f/$1en/",
            "xform/(\\w)h/$1ang/", "xform/(\\w)j/$1an/", "xform/(\\w)k/$1ao/", "xform/(\\w)l/$1ai/",
            "xform/(\\w)z/$1ei/", "xform/(\\w)x/$1ie/", "xform/(\\w)c/$1iao/",
            "xform/([dtgkhvuirzcs])v/$1ui/", "xform/(\\w)b/$1ou/", "xform/(\\w)m/$1ian/",
            "xform/([aoe])\\1(\\w)/$1$2/", "xform/(^|[ '])v/$1zh/", "xform/(^|[ '])i/$1ch/",
            "xform/(^|[ '])u/$1sh/", "xform/([jqxy])v/$1u/", "xform/([nl])v/$1ü/",
        ]
        case .microsoft: return [
            "xform/([aoe])(\\w)/0$2/", "xform/([bpmnljqxy])n/$1in/", "xform/(\\w)g/$1eng/",
            "xform/(\\w)q/$1iu/", "xform/([gkhvuirzcs])w/$1ua/", "xform/(\\w)w/$1ia/",
            "xform/([dtnlgkhjqxyvuirzcs])r/$1uan/", "xform/0r/er/", "xform/([dtgkhvuirzcs])v/$1ui/",
            "xform/(\\w)v/$1ve/", "xform/(\\w)t/$1ve/", "xform/([gkhvuirzcs])y/$1uai/", "xform/(\\w)y/$1v/",
            "xform/([dtnlgkhvuirzcs])o/$1uo/", "xform/(\\w)p/$1un/", "xform/([jqx])s/$1iong/",
            "xform/(\\w)s/$1ong/", "xform/([jqxnl])d/$1iang/", "xform/(\\w)d/$1uang/", "xform/(\\w)f/$1en/",
            "xform/(\\w)h/$1ang/", "xform/(\\w)j/$1an/", "xform/(\\w)k/$1ao/", "xform/(\\w)l/$1ai/",
            "xform/(\\w)z/$1ei/", "xform/(\\w)x/$1ie/", "xform/(\\w)c/$1iao/", "xform/(\\w)b/$1ou/",
            "xform/(\\w)m/$1ian/", "xform/(\\w);/$1ing/", "xform/0(\\w)/$1/", "xform/(^|[ '])v/$1zh/",
            "xform/(^|[ '])i/$1ch/", "xform/(^|[ '])u/$1sh/", "xform/([jqxy])v/$1u/", "xform/([nl])v/$1ü/",
        ]
        }
    }
}

extension SettingKey {
    /// String raw value of Shuangpin, default .none (全拼).
    static let shuangpin = "shuangpin"
}

extension SharedSettings {
    static var shuangpin: Shuangpin {
        Shuangpin(rawValue: Paths.sharedDefaults.string(forKey: SettingKey.shuangpin) ?? "") ?? .none
    }
}

// 联想 (ErgouIME/Engine/Predictor.swift).
extension SettingKey {
    /// Bool, 联想 after typing, default true.
    static let prediction = "prediction"
}

extension SharedSettings {
    static var prediction: Bool {
        Paths.sharedDefaults.object(forKey: SettingKey.prediction) as? Bool ?? true
    }
}

// 候选个数 (librime menu/page_size). User request 2026-11-11: 9 per page.
extension SettingKey {
    /// Int, candidates per page, CandidateCount.range, default CandidateCount.default.
    static let candidateCount = "candidateCount"
}

enum CandidateCount {
    static let range = 3...9
    static let `default` = 5
}

extension SharedSettings {
    /// Anything that is not an Int in range falls back to the default.
    static var candidateCount: Int {
        guard let n = Paths.sharedDefaults.object(forKey: SettingKey.candidateCount) as? Int,
              CandidateCount.range.contains(n) else { return CandidateCount.default }
        return n
    }
}

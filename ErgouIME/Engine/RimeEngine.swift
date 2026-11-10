// ergou-ime — librime engine (ergou_wubi: Wubi 86 jidian + pinyin, M1/M1.5).
// SPDX-License-Identifier: GPL-3.0-only
//
// Compiled only when scripts/configure.sh found librime under vendor/librime
// and added ERGOU_WITH_RIME to Config/Local.xcconfig. This is the integration
// seam for M1 (T1.1) in docs/PLAN-v1.md; it has not been run yet and will need work
// on a Mac (notification handler, schema switching, options, error paths).
//
// Privacy: librime runs fully offline. Its user dictionary and logs stay in
// Paths.rimeUserData (this process's private container). Only this process
// opens librime and writes that directory: ErgouIME Settings stores values in
// the shared defaults and asks us to redeploy; RimeUserConfig turns the
// validated values into *.custom.yaml. We set min_log_level to ERROR so INFO
// logs (which can mention input) are not written.
//
// Plugins: librime loads every dylib in <dir of librime.1.dylib>/rime-plugins
// (librime 1.17.0 plugins/plugins_module.cc), i.e.
// ErgouIME.app/Contents/Frameworks/rime-plugins/. We ship only librime-lua
// (scripts/embed-vendor.sh). Lua scripts are bundled in rime-data/lua/ergou;
// RimeUserConfig quarantines any lua/ or rime.lua in the user directory,
// which librime-lua would otherwise load first.

#if ERGOU_WITH_RIME
import Foundation

/// Process-wide librime setup. librime must be initialised once per process.
final class RimeRuntime {
    static let shared = RimeRuntime()

    private(set) var api: UnsafeMutablePointer<RimeApi>?
    /// Set after deployment (building schema/dictionary caches) finished.
    private(set) var isReady = false
    /// Bumped after every deployment, so open sessions switch to the schema
    /// chosen in Settings (an existing session keeps its old schema
    /// otherwise: Wubi stopped working after switching back from 只用拼音,
    /// D 2026-11-09).
    private(set) var generation = 0

    private let queue = DispatchQueue(label: "com.codamon.inputmethod.Ergou.rime")

    private init() {}

    func start() {
        guard let api = rime_get_api() else {
            Log.engine.error("rime_get_api returned nil")
            return
        }
        self.api = api

        guard let shared = Paths.rimeSharedData else {
            Log.engine.error("Rime shared data not bundled (run scripts/fetch-rime-data.sh)")
            return
        }
        let user = Paths.rimeUserData
        // Before anything is written: an existing install keeps 五笔.
        SharedSettings.migrateDefaultScheme(rimeUserData: user)
        try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        RimeUserConfig.prepare(user)

        var traits = RimeTraits()
        traits.data_size = Int32(MemoryLayout<RimeTraits>.size - MemoryLayout<Int32>.size)
        // librime keeps these pointers; they must live for the whole process.
        traits.shared_data_dir = Self.persistentCString(shared.path)
        traits.user_data_dir = Self.persistentCString(user.path)
        traits.distribution_name = Self.persistentCString("ErgouIME")
        traits.distribution_code_name = Self.persistentCString("ErgouIME")
        traits.distribution_version = Self.persistentCString(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        traits.app_name = Self.persistentCString("rime.ergou")
        traits.min_log_level = 2 // ERROR
        traits.log_dir = Self.persistentCString(user.appendingPathComponent("log").path)

        api.pointee.setup?(&traits)
        api.pointee.initialize?(&traits)

        deploy(fullCheck: false)
    }

    /// Deployments queued or running. Main thread only. isReady turns true
    /// when the last one finishes: with several queued (Settings toggles in
    /// a row), the first one's completion must not reopen sessions while
    /// the next is already rebuilding the schemas.
    private var pendingDeploys = 0

    /// Builds schema/dictionary caches. Can take seconds the first time, so it
    /// runs off the main thread; keys pass through until it finishes.
    func deploy(fullCheck: Bool) {
        guard let api else { return }
        isReady = false
        pendingDeploys += 1
        queue.async { [weak self] in
            if api.pointee.start_maintenance?(fullCheck ? 1 : 0) != 0 {
                api.pointee.join_maintenance_thread?()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingDeploys -= 1
                guard self.pendingDeploys == 0 else { return }
                self.generation += 1
                self.isReady = true
                Log.engine.info("librime ready")
            }
        }
    }

    /// Menu "重新部署" and the Settings request (after it changed a setting).
    /// Regenerates the user files from the (validated) shared settings first.
    func redeploy() {
        RimeUserConfig.prepare(Paths.rimeUserData)
        deploy(fullCheck: true)
    }

    /// Settings "清空用户词库".
    /// TODO(M1 T1.5): finalize librime, delete Paths.rimeUserData/*.userdb
    /// (wubi86_jidian.userdb and pinyin_simp.userdb — 五笔拼音混输's pinyin
    /// keeps that name via pinyin/user_dict: 调频 records only;
    /// ergou_pinyin_ime.userdb: 只用拼音's 调频 and learnt words; manual
    /// phrases are in wubi86_jidian_user.dict.yaml and survive), then
    /// initialize + redeploy. librime has no "clear userdb" API.
    func clearUserDictionary() {
        Log.engine.info("clear user dictionary requested (not implemented yet)")
    }

    private static func persistentCString(_ s: String) -> UnsafePointer<CChar>? {
        UnsafePointer(strdup(s))
    }
}

/// One librime session per client (IMKInputController).
final class RimeEngine: InputEngine {
    private var session: RimeSessionId = 0
    private var api: UnsafeMutablePointer<RimeApi>? { RimeRuntime.shared.api }

    init?() {
        guard RimeRuntime.shared.api != nil else { return nil }
    }

    deinit {
        if session != 0 { _ = api?.pointee.destroy_session?(session) }
    }

    /// Sessions are created lazily so that a controller created while librime
    /// is still deploying starts working as soon as deployment finishes.
    private var sessionGeneration = -1
    private var optionsVersion = -1

    private func ensureSession() -> Bool {
        guard RimeRuntime.shared.isReady, let api else { return false }
        if session == 0 || api.pointee.find_session?(session) == 0 {
            session = api.pointee.create_session?() ?? 0
            sessionGeneration = -1
        }
        guard session != 0 else { return false }
        if sessionGeneration != RimeRuntime.shared.generation {
            // select_schema resets ascii_mode (reset: 0): keep this field's
            // 中/英 across a redeploy. A new session gets it from the
            // controller (restoreAsciiMode).
            let ascii = sessionGeneration >= 0 ? api.pointee.get_option?(session, "ascii_mode") : nil
            // Use the schema chosen in Settings, whatever librime remembers.
            _ = api.pointee.select_schema?(session, SharedSettings.inputScheme.schemaID)
            if let ascii { api.pointee.set_option?(session, "ascii_mode", ascii) }
            sessionGeneration = RimeRuntime.shared.generation
            optionsVersion = -1
        }
        if optionsVersion != MenuOptions.version {
            for (name, on) in MenuOptions.saved {
                api.pointee.set_option?(session, name, on ? 1 : 0)
            }
            optionsVersion = MenuOptions.version
        }
        return true
    }

    var asciiMode: Bool {
        get {
            guard ensureSession(), let api else { return true }
            return api.pointee.get_option?(session, "ascii_mode") != 0
        }
        set {
            guard ensureSession(), let api else { return }
            api.pointee.set_option?(session, "ascii_mode", newValue ? 1 : 0)
        }
    }

    func handle(_ key: KeyInput) -> EngineState? {
        // Until librime is ready, let keys through (English typing still works).
        guard ensureSession(), let api, let keysym = KeyMapping.keysym(for: key) else { return nil }
        let handled = api.pointee.process_key?(session, keysym, KeyMapping.mask(for: key)) ?? 0
        var state = readState()
        state.consumedKey = handled != 0
        if !state.consumedKey && state.commitText == nil { return nil }
        return state
    }

    func selectCandidate(at index: Int) -> EngineState? {
        guard ensureSession(), let api else { return nil }
        guard api.pointee.select_candidate_on_current_page?(session, index) != 0 else { return nil }
        return readState()
    }

    func reset() {
        guard session != 0, let api else { return }
        api.pointee.clear_composition?(session)
    }

    func option(_ name: String) -> Bool {
        guard ensureSession(), let api else { return false }
        return api.pointee.get_option?(session, name) != 0
    }

    func setOption(_ name: String, _ on: Bool) {
        guard ensureSession(), let api else { return }
        api.pointee.set_option?(session, name, on ? 1 : 0)
    }

    func candidates(from index: Int, max: Int) -> [Candidate] {
        guard session != 0, let api else { return [] }
        var it = RimeCandidateListIterator()
        guard api.pointee.candidate_list_from_index?(session, &it, Int32(index)) != 0 else { return [] }
        defer { api.pointee.candidate_list_end?(&it) }
        var out: [Candidate] = []
        while out.count < max, api.pointee.candidate_list_next?(&it) != 0 {
            out.append(Candidate(text: it.candidate.text.map { String(cString: $0) } ?? "",
                                 comment: it.candidate.comment.map { String(cString: $0) },
                                 label: nil))
        }
        return out
    }

    func selectAbsolute(_ index: Int) -> EngineState? {
        guard ensureSession(), let api,
              api.pointee.select_candidate?(session, index) != 0 else { return nil }
        return readState()
    }

    func takeRawInput() -> String? {
        guard session != 0, let api, let raw = api.pointee.get_input?(session) else { return nil }
        let text = String(cString: raw)
        api.pointee.clear_composition?(session)
        return text.isEmpty ? nil : text
    }

    private func readState() -> EngineState {
        var state = EngineState()
        guard let api else { return state }

        var commit = RimeCommit()
        commit.data_size = Int32(MemoryLayout<RimeCommit>.size - MemoryLayout<Int32>.size)
        if api.pointee.get_commit?(session, &commit) != 0 {
            if let text = commit.text { state.commitText = String(cString: text) }
            _ = api.pointee.free_commit?(&commit)
        }

        var context = RimeContext()
        context.data_size = Int32(MemoryLayout<RimeContext>.size - MemoryLayout<Int32>.size)
        if api.pointee.get_context?(session, &context) != 0 {
            if let preedit = context.composition.preedit {
                state.preedit = String(cString: preedit)
                let utf8 = Array(state.preedit.utf8)
                // librime reports the caret as a UTF-8 byte offset.
                let caret = max(0, min(Int(context.composition.cursor_pos), utf8.count))
                state.preeditCursor = String(decoding: utf8[..<caret], as: UTF8.self).utf16.count
            }
            let menu = context.menu
            if menu.num_candidates > 0, let list = menu.candidates {
                for i in 0..<Int(menu.num_candidates) {
                    let c = list[i]
                    state.candidates.append(Candidate(
                        text: c.text.map { String(cString: $0) } ?? "",
                        comment: c.comment.map { String(cString: $0) },
                        label: "\(i + 1)"))
                }
            }
            state.highlightedIndex = Int(menu.highlighted_candidate_index)
            state.isLastPage = menu.is_last_page != 0
            state.pageNo = Int(menu.page_no)
            state.pageSize = max(1, Int(menu.page_size))
            _ = api.pointee.free_context?(&context)
        }
        state.asciiMode = api.pointee.get_option?(session, "ascii_mode") != 0
        return state
    }
}
#endif

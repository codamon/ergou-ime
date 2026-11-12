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
// ErgouIME.app/Contents/Frameworks/rime-plugins/. We ship librime-lua and
// librime-octagram (整句模型; GrammarModel.swift) (scripts/embed-vendor.sh). Lua scripts are bundled in rime-data/lua/ergou;
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
    /// Kept for re-initialising librime on every redeploy (see deploy).
    private var traits = RimeTraits()

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
        self.traits = traits

        // Asked for while the input method was not running (Settings writes
        // the request to the shared defaults; SharedRequest).
        requestDeploy(clearUserDictionaries: SharedRequest.clearUserDictionary.consume())
    }

    // Deployment state. Main thread only.
    private var deployRunning = false
    private var deployAgain = false
    private var forceRequested = false
    private var clearRequested = false
    private var initialized = false
    private var deployedSinceReady = false

    /// (Re)builds everything and reopens the engine: Settings changes, menu
    /// "重新部署", the first start, 清空调频记录.
    ///
    /// One run, on the serial queue: regenerate the user files from the
    /// validated shared settings; if anything changed (or the run is
    /// forced): finalize librime → (delete the user dictionaries) →
    /// initialize → build schema/dictionary caches. Keys pass through
    /// (isReady == false) from just before finalize until the run is done.
    ///
    /// Why finalize + initialize: librime keeps every schema config it
    /// loaded in memory, so a redeploy without it rebuilt the files on disk
    /// but sessions — even new ones — kept the old values until the input
    /// method restarted: 候选个数 9 still showed 5, and fuzzy pinyin, typo
    /// tolerance, 整句模型 etc. changed nothing (user report 2026-11-11;
    /// reproduced with librime 1.17.0 in one process). Squirrel redeploys
    /// the same way. Safe because every RimeEngine call checks isReady,
    /// which is cleared on the main thread before finalize.
    ///
    /// Requests are coalesced, and a request that changes no generated file
    /// does not restart the engine at all (audit 0.4.1 M1: the redeploy
    /// notification can be posted by any process; a flood of them used to
    /// queue a full restart each and keep the input method in pass-through).
    /// The file work (hashing and copying dictionaries and a grammar model
    /// of up to 418 MB) runs on the queue, not on the main thread, and never
    /// while librime is compiling those files (audit L1).
    private func requestDeploy(force: Bool = false, clearUserDictionaries: Bool = false) {
        guard api != nil else { return }
        forceRequested = forceRequested || force
        clearRequested = clearRequested || clearUserDictionaries
        if deployRunning { deployAgain = true; return }
        deployRunning = true
        runDeploy()
    }

    private func runDeploy() {
        guard let api else { return }
        let clear = clearRequested, first = !initialized
        let force = forceRequested || clear || first
        clearRequested = false
        forceRequested = false
        deployAgain = false
        let traits = self.traits
        let user = Paths.rimeUserData
        queue.async { [weak self] in
            let changed = RimeUserConfig.prepare(user)
            if changed || force {
                if !first {
                    DispatchQueue.main.sync { self?.isReady = false }
                    api.pointee.finalize?()            // also ends every session
                }
                if clear { Self.deleteUserDictionaries(in: user) }
                var t = traits
                api.pointee.initialize?(&t)
                if api.pointee.start_maintenance?(first ? 0 : 1) != 0 {
                    api.pointee.join_maintenance_thread?()
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if changed || force {
                    self.initialized = true
                    self.deployedSinceReady = true
                }
                // Ready again BEFORE starting a queued run: otherwise a stream
                // of requests keeps isReady false for as long as it lasts. A
                // run that restarts librime clears isReady itself (above).
                if self.deployedSinceReady {
                    self.deployedSinceReady = false
                    self.generation += 1
                    Log.engine.info("librime ready")
                }
                self.isReady = self.initialized
                if self.deployAgain || self.clearRequested || self.forceRequested { self.runDeploy(); return }
                self.deployRunning = false
            }
        }
    }

    /// The Settings request (after it changed a setting): restarts the
    /// engine only if a generated file changed.
    func redeploy() {
        requestDeploy()
    }

    /// Menu "重新部署": always.
    func forceRedeploy() {
        requestDeploy(force: true)
    }

    /// Settings "清空调频记录": deletes librime's user dictionaries —
    /// wubi86_jidian.userdb and pinyin_simp.userdb (调频 records of
    /// 五笔拼音混输) and ergou_pinyin_ime.userdb (拼音's 调频 and the words it
    /// learnt from committed sentences) — plus their text snapshots. Manual
    /// phrases (wubi86_jidian_user.dict.yaml) and 个人词库 are generated
    /// from Settings and survive. librime has no "clear userdb" API, so
    /// this happens between finalize and initialize of a deploy run.
    func clearUserDictionary() {
        Log.engine.info("clearing user dictionaries")
        requestDeploy(clearUserDictionaries: true)
    }

    /// Deploy queue only, librime finalized.
    private static func deleteUserDictionaries(in user: URL) {
        let fm = FileManager.default
        var removed = 0
        func sweep(_ dir: URL) {
            for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                let name = item.lastPathComponent
                if name.hasSuffix(".userdb") || name.hasSuffix(".userdb.txt") || name.hasSuffix(".userdb.kct") {
                    if (try? fm.removeItem(at: item)) != nil { removed += 1 }
                }
            }
        }
        sweep(user)
        // Snapshots: sync/<installation id>/<name>.userdb.txt
        let sync = user.appendingPathComponent("sync", isDirectory: true)
        sweep(sync)
        for sub in (try? fm.contentsOfDirectory(at: sync, includingPropertiesForKeys: nil)) ?? [] { sweep(sub) }
        Log.engine.info("removed \(removed, privacy: .public) user dictionary items")
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
        // Only a session of the current librime instance: finalize ended the
        // older ones, and their ids may now belong to another controller.
        if session != 0, RimeRuntime.shared.isReady, sessionGeneration == RimeRuntime.shared.generation {
            _ = api?.pointee.destroy_session?(session)
        }
    }

    /// Sessions are created lazily so that a controller created while librime
    /// is still deploying starts working as soon as deployment finishes.
    private var sessionGeneration = -1
    private var optionsVersion = -1
    /// This field's 中/英 as last seen or asked for. Every redeploy ends all
    /// sessions (finalize), and a new session starts in 中文 (ascii_mode
    /// reset: 0), so it is applied again when the session is recreated —
    /// also when it was set while librime was not ready (audit 0.4.1 M4:
    /// English mode in Terminal turned into Chinese after any redeploy).
    private var knownAscii: Bool?

    /// A session of the current librime instance, without creating one.
    private var hasLiveSession: Bool {
        session != 0 && RimeRuntime.shared.isReady && sessionGeneration == RimeRuntime.shared.generation
    }

    private func ensureSession() -> Bool {
        guard RimeRuntime.shared.isReady, let api else { return false }
        if sessionGeneration != RimeRuntime.shared.generation {
            // The old id is dead; librime derives ids from addresses, so
            // find_session(old id) could even find someone else's session.
            session = api.pointee.create_session?() ?? 0
            guard session != 0 else { return false }
            // Use the schema chosen in Settings, whatever librime remembers.
            _ = api.pointee.select_schema?(session, SharedSettings.inputScheme.schemaID)
            // The candidate row is horizontal: tell librime's selector, so
            // Left/Right move the highlight (and turn the page at its ends)
            // and Up goes back a page, as in Squirrel. Without it librime
            // assumes a vertical list and Left/Right did nothing (D,
            // 2026-11-12). Down never gets here: it opens the grid
            // (ErgouInputController.handleGridKey).
            api.pointee.set_option?(session, "_horizontal", 1)
            if let knownAscii { api.pointee.set_option?(session, "ascii_mode", knownAscii ? 1 : 0) }
            sessionGeneration = RimeRuntime.shared.generation
            optionsVersion = -1
        }
        guard session != 0 else { return false }
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
            guard ensureSession(), let api else { return knownAscii ?? true }
            let on = api.pointee.get_option?(session, "ascii_mode") != 0
            knownAscii = on
            return on
        }
        set {
            knownAscii = newValue        // applied when the session exists
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

    func changePage(backward: Bool) -> EngineState? {
        guard hasLiveSession, let api,
              api.pointee.change_page?(session, backward ? 1 : 0) != 0 else { return nil }
        return readState()
    }

    func reset() {
        guard hasLiveSession, let api else { return }
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
        guard hasLiveSession, let api else { return [] }
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
        guard hasLiveSession, let api, let raw = api.pointee.get_input?(session) else { return nil }
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
        knownAscii = state.asciiMode
        return state
    }
}
#endif

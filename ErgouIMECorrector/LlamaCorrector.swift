// ErgouIME Corrector — local open model via llama.cpp (greedy, offline).
// SPDX-License-Identifier: GPL-3.0-only

#if ERGOU_WITH_LLAMA
import Foundation

final class LlamaCorrector {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let template: String?
    private let maxNewTokens: Int32 = 400

    init?(modelPath: String) {
        llama_log_set({ _, _, _ in }, nil)   // quiet: never log text
        llama_backend_init()
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 99
        guard let m = llama_model_load_from_file(modelPath, mparams) else { return nil }
        var cparams = llama_context_default_params()
        cparams.n_ctx = 2048
        cparams.n_batch = 2048
        guard let c = llama_init_from_model(m, cparams) else { llama_model_free(m); return nil }
        model = m
        context = c
        vocab = llama_model_get_vocab(m)
        template = llama_model_chat_template(m, nil).map { String(cString: $0) }
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    func correct(_ text: String, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        // Qwen3 thinks unless told not to.
        let user = text + (template?.contains("enable_thinking") == true ? " /no_think" : "")
        guard let prompt = format(system: CorrectionPrompt.system, user: user) else { return nil }

        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let n = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard n > 0 else { return nil }
        tokens.removeLast(tokens.count - Int(n))

        llama_memory_clear(llama_get_memory(context), true)
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        defer { llama_sampler_free(sampler) }

        var out = Data()
        var batch = llama_batch_get_one(&tokens, n)
        var next: llama_token = 0
        for _ in 0..<maxNewTokens {
            guard llama_decode(context, batch) == 0, Date() < deadline else { return nil }
            next = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, next) { break }
            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, next, &buf, Int32(buf.count), 0, false)
            if len > 0 { out.append(contentsOf: buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }) }
            batch = llama_batch_get_one(&next, 1)
        }
        guard let s = String(data: out, encoding: .utf8) else { return nil }
        return CorrectionPrompt.accept(s, for: text)
    }

    private func format(system: String, user: String) -> String? {
        var messages: [llama_chat_message] = []
        let role1 = strdup("system")!, content1 = strdup(system)!
        let role2 = strdup("user")!, content2 = strdup(user)!
        defer { [role1, content1, role2, content2].forEach { free($0) } }
        messages.append(llama_chat_message(role: role1, content: content1))
        messages.append(llama_chat_message(role: role2, content: content2))
        var buf = [CChar](repeating: 0, count: 8192)
        let tmpl = template
        let len = tmpl.withOptionalCString { t in
            llama_chat_apply_template(t, messages, messages.count, true, &buf, Int32(buf.count))
        }
        guard len > 0, len < buf.count else { return nil }
        return String(decoding: buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

private extension Optional where Wrapped == String {
    func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case let .some(s): return s.withCString { body($0) }
        case .none: return body(nil)
        }
    }
}
#endif

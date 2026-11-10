# vendor/

Third-party binaries and data, downloaded on the Mac by `scripts/`. Nothing
here except this file is committed.

| Directory | Script | Contents |
|---|---|---|
| `librime/` | `fetch-librime.sh` | librime 1.17.0 headers + dylib (BSD-3-Clause) |
| `rime-data/` | `fetch-rime-data.sh` | rime-prelude (LGPL-3.0) + rime-wubi86-jidian (MIT) YAML |
| `sherpa-onnx/` | `fetch-sherpa-onnx.sh` | sherpa-onnx 2.0.1 C API + onnxruntime dylibs (Apache-2.0 / MIT) |
| `src/` | `fetch-rime-data.sh` | pinned git checkouts of the Rime data repos |
| `.downloads/` | all | checksum-verified archive cache |

The SenseVoice model is not stored here; see `scripts/fetch-sensevoice-model.sh`.

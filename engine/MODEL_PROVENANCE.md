# PaceBack ONNX model-pack provenance

The optional production model pack contains frozen third-party upstream artifacts. PaceBack does not fine-tune either model and never updates weights from user data.

| Component | Immutable upstream revision | Distributed artifact | SHA-256 | Bytes | Declared license |
|---|---|---|---|---:|---|
| `BAAI/bge-small-en-v1.5` | `5c38ec7c405ec4b44b94cc5a9bb96e735b38267a` | `onnx/model.onnx` | `828e1496d7fabb79cfa4dcd84fa38625c0d3d21da474a00f08db0f559940cf35` | 133,093,490 | MIT |
| BGE tokenizer | same revision | `tokenizer.json` | `d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66` | 711,396 | MIT |
| `cross-encoder/ms-marco-MiniLM-L-6-v2` | `233902d25c440f23af6f7d6e94d2946bac0bee0a` | `onnx/model_qint8_arm64.onnx` (stored as `reranker/model.onnx`) | `3573b6b9593cb2f75987a31815d409ca3dd8808629118fd20451bb1a5d90cec7` | 23,200,716 | Apache-2.0 |
| MiniLM tokenizer | same revision | `tokenizer.json` | `d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66` | 711,396 | Apache-2.0 |

Upstream source pages:

- <https://huggingface.co/BAAI/bge-small-en-v1.5/tree/5c38ec7c405ec4b44b94cc5a9bb96e735b38267a>
- <https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-6-v2/tree/233902d25c440f23af6f7d6e94d2946bac0bee0a>

The 157,716,998 artifact bytes are downloaded only by `scripts/download_model_pack.py`. The script checks these pinned values before creating and signing `manifest.json`. Runtime activation separately verifies the Ed25519 signature, all SHA-256 values, all byte lengths, the exact model IDs and revisions, the 384-dimensional BGE output, and both ONNX I/O contracts.

The locally built pack used for the prototype has:

- Manifest SHA-256: `9d432e366d410fe049313341e58b9d39e30f13b13f5310b2fe5fe9d0ad83c61d`
- Decoded Ed25519 signature SHA-256: `ba40c0afa8f562dfa7549dc431cf3de17e6f64861d76f4ea187f97ce8583ad8e`
- Raw public trust-key SHA-256: `c01cf69ba17c30035d076eda0da2fdd1e2d51de4756cbd3a711f4e50255720b4`

These final three hashes identify this particular signed build and will change if the pack is rebuilt with a different timestamp or signing key, even when upstream model bytes remain identical.

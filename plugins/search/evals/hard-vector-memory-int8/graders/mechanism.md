---
type: llm
focus: last_message
---

Ground truth (Elasticsearch dense_vector docs + "Tune approximate kNN search"): since 8.14, a new float dense_vector field with no index_options defaults to `int8_hnsw`. For quantized indexes the raw float vectors stay on disk and do not count toward required off-heap RAM; the RAM needed is the quantized copy (int8: num_dimensions + 16 bytes per vector) plus the HNSW graph (num_vectors * 4 * m, default m = 16). Every shard copy (primary and replica) needs its own share. This memory is OS page cache (off-heap), not JVM heap.
Correct numbers: 20M * (768 + 16) = ~15.7 GB, graph 20M * 4 * 16 = ~1.28 GB, ~17 GB per copy, ~34 GB total with 1 replica (≈31.6 GiB; anything roughly 30–38 GB/GiB is acceptable). A float-based estimate would be 20M * 768 * 4 = ~61 GB per copy.

PASS only if ALL of the following hold:
1. It recognizes that on 8.15 the unset index_options means int8_hnsw quantization and sizes the RAM on the quantized int8 vectors (~1 byte per dimension, ~768–784 bytes per vector), NOT on full float32 (dims*4) as the required in-memory working set. Mentioning the float size as the on-disk/raw size is fine.
2. It includes the HNSW graph term (~num_vectors*4*m, ~1.28 GB with m=16) — or at least an explicit graph overhead of about that magnitude.
3. It multiplies by the shard copies (primary + 1 replica), landing roughly in 30–38 GB total.
4. It says this memory should be left to the OS filesystem/page cache (off-heap), not given to the JVM heap.
FAIL if it sizes the working set as float32 (~61 GB per copy / ~120 GB total) as the requirement, puts the vectors in heap, or omits the replica factor.

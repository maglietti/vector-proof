# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy>=2", "pyarrow>=17"]
# ///
"""Split the MiniLM file into time-travel load files.

Usage: uv run prep_tt.py <parquet_dir> <out_dir>
Fixed seed 42. 20,000 original memories, 250 held-out queries, and
10 rounds x 20,000 revised vectors (each round gives every memory a new vector).
"""
import glob
import sys

import numpy as np
import pyarrow.parquet as pq

src, out = sys.argv[1:3]
N, Q, ROUNDS = 20_000, 250, 10
t = pq.read_table(sorted(glob.glob(f"{src}/*.parquet"))[0], columns=["emb"])
col = t.column("emb").combine_chunks()
v = col.flatten().to_numpy(zero_copy_only=False).astype("<f4").reshape(-1, len(col[0]))
o = np.random.default_rng(42).permutation(len(v))
with open(f"{out}/tt-rows.tsv", "w") as f:
    for i in range(N):
        f.write(f"{i + 1}\t{v[o[i]].tobytes().hex()}\n")
with open(f"{out}/tt-queries.tsv", "w") as f:
    for i in range(Q):
        f.write(f"{i + 1}\t{v[o[N + i]].tobytes().hex()}\n")
with open(f"{out}/tt-rev.tsv", "w") as f:
    base = N + Q
    for r in range(ROUNDS):
        for i in range(N):
            f.write(f"{r + 1}\t{i + 1}\t{v[o[base + r * N + i]].tobytes().hex()}\n")
print(f"{len(v)} source rows; wrote {N} rows, {Q} queries, {ROUNDS * N} revisions")

# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy>=2", "pyarrow>=17"]
# ///
"""Convert a Parquet embedding dataset into TSV load files for MariaDB.

Usage: uv run prep.py <parquet_dir> <vector_column> <text_column> <out_prefix>

Shuffles rows with a fixed seed, writes 100,000 rows to <out_prefix>-rows.tsv
and the next 250 rows to <out_prefix>-queries.tsv. Vectors are written as hex
float32 little-endian, which is the binary format of a MariaDB VECTOR column.
"""
import glob
import sys

import numpy as np
import pyarrow.parquet as pq

LOAD_ROWS = 100_000
QUERY_ROWS = 250

src, vec_col, text_col, out = sys.argv[1:5]
tables = [pq.read_table(f, columns=[vec_col, text_col]) for f in sorted(glob.glob(f"{src}/*.parquet"))]
vecs, texts = [], []
for t in tables:
    col = t.column(vec_col).combine_chunks()
    dim = len(col[0])
    vecs.append(col.flatten().to_numpy(zero_copy_only=False).astype("<f4").reshape(-1, dim))
    texts.extend(t.column(text_col).to_pylist())
vecs = np.vstack(vecs)
print(f"read {len(vecs)} rows, {vecs.shape[1]} dimensions", flush=True)

order = np.random.default_rng(42).permutation(len(vecs))
need = LOAD_ROWS + QUERY_ROWS
if len(order) < need:
    sys.exit(f"only {len(order)} rows, need {need}")


def clean(s):
    return (s or "").replace("\t", " ").replace("\n", " ").replace("\\", " ")[:200]


with open(f"{out}-rows.tsv", "w") as f:
    for n, i in enumerate(order[:LOAD_ROWS], start=1):
        f.write(f"{n}\tagent-{n % 10}\t{clean(texts[i])}\t{vecs[i].tobytes().hex()}\n")
with open(f"{out}-queries.tsv", "w") as f:
    for n, i in enumerate(order[LOAD_ROWS:need], start=1):
        f.write(f"{n}\t{vecs[i].tobytes().hex()}\n")
norms = np.linalg.norm(vecs[order[:1000]], axis=1)
print(f"wrote {LOAD_ROWS} rows and {QUERY_ROWS} queries; sample norm min {norms.min():.4f} max {norms.max():.4f}")

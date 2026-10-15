# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy>=2", "pyarrow>=17"]
# ///
"""Write the dbpedia rows that prep.py did not use, for the mixed-load writer.

Usage: uv run prep_extra.py <parquet_dir> <out_tsv>
Same seed and order as prep.py, so these rows are disjoint from the loaded
rows and the queries.
"""
import glob
import sys

import numpy as np
import pyarrow.parquet as pq

src, out = sys.argv[1:3]
vecs, texts = [], []
for f in sorted(glob.glob(f"{src}/*.parquet")):
    t = pq.read_table(f, columns=["openai", "title"])
    col = t.column("openai").combine_chunks()
    vecs.append(col.flatten().to_numpy(zero_copy_only=False).astype("<f4").reshape(-1, len(col[0])))
    texts.extend(t.column("title").to_pylist())
vecs = np.vstack(vecs)
order = np.random.default_rng(42).permutation(len(vecs))
with open(out, "w") as f:
    for n, i in enumerate(order[100_250:], start=1):
        title = (texts[i] or "").replace("\t", " ").replace("\n", " ").replace("\\", " ")[:200]
        f.write(f"{n}\t{title}\t{vecs[i].tobytes().hex()}\n")
print(f"wrote {len(order) - 100_250} extra rows")

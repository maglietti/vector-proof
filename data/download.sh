#!/usr/bin/env bash
# Download the public embedding datasets used by stages 03 and 05.
#
# Usage: ./download.sh [wiki|dbpedia|all]   (default: all)
#
# wiki:    maloyan/wikipedia-22-12-en-embeddings-all-MiniLM-L6-v2, first Parquet file,
#          about 613 MB, 242,538 rows, 384 dimensions. No license declared on the dataset;
#          the text is Wikipedia (CC BY-SA). Stages 03 and 05.
# dbpedia: KShivendu/dbpedia-entities-openai-1M, first three Parquet files, about 1.1 GB,
#          115,386 rows, 1,536 dimensions (OpenAI text-embedding-ada-002), MIT. Stage 03.
set -euo pipefail

cd "$(dirname "$0")"
HF=https://huggingface.co/datasets
what=${1:-all}

if [[ $what == wiki || $what == all ]]; then
  if [[ ! -f wiki-minilm-train-00000.parquet ]]; then
    curl -fSL -o wiki-minilm-train-00000.parquet \
      "$HF/maloyan/wikipedia-22-12-en-embeddings-all-MiniLM-L6-v2/resolve/main/data/train-00000-of-00145-437d77a320cee9e2.parquet"
  fi
fi

if [[ $what == dbpedia || $what == all ]]; then
  mkdir -p dbpedia
  for f in train-00000-of-00026-3c7b99d1c7eda36e train-00001-of-00026-2b24035a6390fdcb train-00002-of-00026-b05ce48965853dad; do
    [[ -f dbpedia/$f.parquet ]] || curl -fSL -o "dbpedia/$f.parquet" "$HF/KShivendu/dbpedia-entities-openai-1M/resolve/main/data/$f.parquet"
  done
fi

ls -la . dbpedia 2>/dev/null

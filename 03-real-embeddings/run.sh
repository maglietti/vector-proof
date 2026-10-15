#!/usr/bin/env bash
# Stage 03: real embeddings at 384 and 1,536 dimensions, recall, latency, and mixed load.
#
# Usage (from any directory):
#   ./run.sh prep                  build load/ TSV files from ../data (needs uv; dependencies come from each script's inline metadata)
#   ./run.sh load  <port>          create tables and load 100,000 rows + 250 queries per dataset
#   ./run.sh index <port>          build both vector indexes (M=16, cosine), in parallel
#   ./run.sh bench <port>          recall@10 and p50/p95/p99 at ef_search 20/40/100/200, filtered at 20/100/400
#   ./run.sh mixed <port> [rate] [secs]   1 writer at <rate> inserts/s (default 20) + 4 readers + 1 prober,
#                                  then 4 readers alone, for <secs> seconds each (default 60); 1,536 dims
#
# Results go to results/<step>-<version>-*.txt. The mixed step adds rows to dbpedia1536,
# so run bench before mixed, or reload.
set -euo pipefail

cd "$(dirname "$0")"
SB=../sandbox.sh
step=${1:?usage: run.sh prep|load|index|bench|mixed [port]}
port=${2:-}
mkdir -p results load gen

ver() { $SB sql "$port" -N -B -e "SELECT SUBSTRING_INDEX(VERSION(), '-', 1)"; }

gen() {
  for x in "wiki384 384" "dbpedia1536 1536"; do
    set -- $x
    sed -e "s/TBL/$1/g; s/DIM/$2/g" load.sql.tpl > "gen/load-$1.sql"
    sed -e "s/TBL/$1/g" bench.sql.tpl > "gen/bench-$1.sql"
  done
}

case $step in
  prep)
    run_py() { uv run -q "$@"; }
    run_py prep.py ../data/dbpedia openai title load/dbpedia1536
    mkdir -p load/wiki-src && ln -sf ../../../data/wiki-minilm-train-00000.parquet load/wiki-src/train-00000.parquet
    run_py prep.py load/wiki-src emb title load/wiki384
    run_py prep_extra.py ../data/dbpedia load/dbpedia1536-extra.tsv
    ;;
  load)
    gen; v=$(ver); out=results/build-$v.txt; : > "$out"
    for d in wiki384 dbpedia1536; do
      s=$(date +%s); $SB sql "$port" < "gen/load-$d.sql" >> "$out"; echo "$d load_s=$(( $(date +%s) - s ))" >> "$out"
    done
    cat "$out"
    ;;
  index)
    v=$(ver); out=results/build-$v.txt
    for d in wiki384 dbpedia1536; do
      ( s=$(date +%s); $SB sql "$port" scale -e "ALTER TABLE $d ADD VECTOR INDEX (embedding) M=16 DISTANCE=cosine"
        echo "$d index_s=$(( $(date +%s) - s ))" >> "$out" ) &
    done
    wait; grep _s= "$out"
    ;;
  bench)
    gen; v=$(ver)
    for d in wiki384 dbpedia1536; do
      $SB sql "$port" < "gen/bench-$d.sql" > "results/bench-$v-$d.txt"
      sed -n '1,30p' "results/bench-$v-$d.txt"
    done
    ;;
  mixed)
    rate=${3:-20}; secs=${4:-60}; v=$(ver)
    $SB sql "$port" < mixed-setup.sql
    $SB sql "$port" < mixed-procs.sql
    $SB sql "$port" scale -e "CALL writer($rate, $secs)" &
    for r in 1 2 3 4; do $SB sql "$port" scale -e "CALL reader($r, $secs)" & done
    $SB sql "$port" scale -e "CALL prober($secs)" &
    wait
    $SB sql "$port" < mixed-report.sql | tee "results/mixed-$v-${rate}rps.txt"
    $SB sql "$port" scale -e "TRUNCATE reads_log"
    for r in 1 2 3 4; do $SB sql "$port" scale -e "CALL reader($r, $secs)" & done
    wait
    $SB sql "$port" scale -e "SELECT 'vector read, 4 readers, no writes' op, COUNT(*) reads_done, ROUND(COUNT(*) / $secs, 1) reads_per_s,
      MAX(CASE WHEN r = CEIL(c * 0.50) THEN us END) / 1000 p50_ms, MAX(CASE WHEN r = CEIL(c * 0.95) THEN us END) / 1000 p95_ms,
      MAX(CASE WHEN r = CEIL(c * 0.99) THEN us END) / 1000 p99_ms
      FROM (SELECT us, ROW_NUMBER() OVER (ORDER BY us) r, COUNT(*) OVER () c FROM reads_log) z" | tee "results/mixed-$v-readonly.txt"
    ;;
  *)
    echo "unknown step: $step" >&2
    exit 2
    ;;
esac

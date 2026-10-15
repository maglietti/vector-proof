#!/usr/bin/env bash
# Stage 05: vector search on a system-versioned table as history grows.
#
# Usage:
#   ./tt-run.sh prep            build load/tt-*.tsv from ../data/wiki-minilm-train-00000.parquet (needs uv)
#   ./tt-run.sh run <port>      load 20,000 memories, then 10 rounds that give every memory a new
#                               embedding; measure current and AS OF queries at history 0x, 1x, 5x, 10x
#
# Results go to results/timetravel-<version>.txt. One run takes about 20 minutes on an M4 Pro.
set -euo pipefail

cd "$(dirname "$0")"
SB=../sandbox.sh
step=${1:?usage: tt-run.sh prep|run [port]}
mkdir -p load results

case $step in
  prep)
    mkdir -p load/wiki-src && ln -sf ../../../data/wiki-minilm-train-00000.parquet load/wiki-src/train-00000.parquet
    uv run -q prep_tt.py load/wiki-src load
    ;;
  run)
    port=${2:?port required}
    v=$($SB sql "$port" -N -B -e "SELECT SUBSTRING_INDEX(VERSION(), '-', 1)")
    {
      s=$(date +%s); $SB sql "$port" < tt-setup.sql; echo "setup_s=$(( $(date +%s) - s ))"
      $SB sql "$port" < tt-procs.sql
      $SB sql "$port" tt -e "CALL measure('current, history 0x', NULL)"
      for r in $(seq 1 10); do
        s=$(date +%s); $SB sql "$port" tt -e "CALL revise($r)"; echo "round $r revise_s=$(( $(date +%s) - s ))"
        if [[ $r == 1 || $r == 5 || $r == 10 ]]; then
          $SB sql "$port" tt -e "CALL measure('current, history ${r}x', NULL); CALL measure('as of original, ${r}x', 0)"
        fi
      done
      $SB sql "$port" tt -e "SELECT * FROM results"
      $SB sql "$port" tt -e "SET @v = (SELECT v FROM q WHERE qid = 1); SET @ts = (SELECT ts FROM cp WHERE round = 0);
        EXPLAIN SELECT id FROM mem_v ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
        EXPLAIN SELECT id FROM mem_v FOR SYSTEM_TIME AS OF @ts ORDER BY VEC_DISTANCE(embedding, @v) LIMIT 10;
        SELECT COUNT(*) AS current_rows FROM mem_v; SELECT COUNT(*) AS all_versions FROM mem_v FOR SYSTEM_TIME ALL;"
    } 2>&1 | tee "results/timetravel-$v.txt"
    ;;
  *)
    echo "unknown step: $step" >&2
    exit 2
    ;;
esac

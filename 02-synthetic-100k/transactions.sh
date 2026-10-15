#!/usr/bin/env bash
# Show that the vector index follows transaction isolation, on the stage 01 table.
#
# Usage: ./transactions.sh <port>   (run 01-snippet/snippet.sql on that port first)
#
# Session A inserts a near-duplicate of the query vector and holds the transaction open for
# 4 seconds. Session B searches during that time, then everyone searches after ROLLBACK.
# Last, an autocommit insert is searched for from a new session.
set -euo pipefail

port=${1:?port required}
sql() { "$(dirname "$0")/../sandbox.sh" sql "$port" demo "$@"; }
Q="SELECT GROUP_CONCAT(id ORDER BY id) FROM (SELECT id FROM agent_memory ORDER BY VEC_DISTANCE(embedding, VEC_FromText('[0.95, 0.05, 0]')) LIMIT 3) x"

echo "-- A: BEGIN; INSERT an uncommitted note; hold 4 s; ROLLBACK"
sql -e "BEGIN; INSERT INTO agent_memory (agent_id, note, embedding) VALUES ('billing-agent', 'UNCOMMITTED refund note', VEC_FromText('[0.95, 0.05, 0]')); SELECT 'A sees' AS who, ($Q) AS top3; DO SLEEP(4); ROLLBACK;" &
sleep 2
echo "-- B during A's open transaction:"
sql -e "SELECT 'B sees' AS who, ($Q) AS top3"
wait
echo "-- after ROLLBACK:"
sql -e "SELECT ($Q) AS top3"
echo "-- autocommit insert, then search from a new session:"
sql -e "INSERT INTO agent_memory (agent_id, note, embedding) VALUES ('billing-agent', 'COMMITTED refund note', VEC_FromText('[0.95, 0.05, 0]')); SELECT LAST_INSERT_ID() AS new_id"
sql -e "SELECT id, note FROM agent_memory ORDER BY VEC_DISTANCE(embedding, VEC_FromText('[0.95, 0.05, 0]')) LIMIT 1"

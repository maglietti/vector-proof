CREATE DATABASE IF NOT EXISTS tt; USE tt;
DROP TABLE IF EXISTS mem_v, rev, q, cp, ann, exact_nn, timing, results;
-- Agent memory with full row history kept by the server.
CREATE TABLE mem_v (
  id INT UNSIGNED PRIMARY KEY,
  agent_id VARCHAR(64) NOT NULL,
  note VARCHAR(255) NOT NULL,
  embedding VECTOR(384) NOT NULL
) WITH SYSTEM VERSIONING;
CREATE TABLE rev (round INT, id INT, v VECTOR(384) NOT NULL, PRIMARY KEY (round, id));
CREATE TABLE q (qid INT PRIMARY KEY, v VECTOR(384) NOT NULL);
CREATE TABLE cp (round INT PRIMARY KEY, ts DATETIME(6));
LOAD DATA LOCAL INFILE 'load/tt-rows.tsv' INTO TABLE mem_v FIELDS TERMINATED BY '\t'
  (id, @h) SET agent_id = CONCAT('agent-', id % 10), note = 'original', embedding = UNHEX(@h);
LOAD DATA LOCAL INFILE 'load/tt-queries.tsv' INTO TABLE q FIELDS TERMINATED BY '\t' (qid, @h) SET v = UNHEX(@h);
LOAD DATA LOCAL INFILE 'load/tt-rev.tsv' INTO TABLE rev FIELDS TERMINATED BY '\t' (round, id, @h) SET v = UNHEX(@h);
ALTER TABLE mem_v ADD VECTOR INDEX (embedding) M=16 DISTANCE=cosine;
CREATE TABLE ann (label VARCHAR(30), qid INT, id INT, KEY (label, qid, id));
CREATE TABLE exact_nn (label VARCHAR(30), qid INT, id INT, KEY (label, qid, id));
CREATE TABLE timing (label VARCHAR(30), qid INT, us BIGINT);
CREATE TABLE results (label VARCHAR(30), history_rows INT, recall_at_10 DECIMAL(6,4), rows_returned INT, short_results INT,
  p50_ms DECIMAL(8,2), p95_ms DECIMAL(8,2), p99_ms DECIMAL(8,2), exact_p50_ms DECIMAL(8,2));
DO SLEEP(1);
INSERT INTO cp VALUES (0, NOW(6));
DO SLEEP(1);
SELECT VERSION(), (SELECT COUNT(*) FROM mem_v) current_rows, (SELECT COUNT(*) FROM rev) revisions, (SELECT COUNT(*) FROM q) queries;

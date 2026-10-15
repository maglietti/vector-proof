-- tt-partition.sql: a vector index on a history-partitioned table
-- Usage: ../sandbox.sh sql <port> < tt-partition.sql
-- Recorded on 12.3.3: ERROR 1506 (HY000): Partitioned tables do not support VECTOR
CREATE DATABASE IF NOT EXISTS tt;
USE tt;
DROP TABLE IF EXISTS mem_vp;
CREATE TABLE mem_vp (
  id INT UNSIGNED PRIMARY KEY,
  embedding VECTOR(3) NOT NULL,
  VECTOR INDEX (embedding) DISTANCE=cosine
) WITH SYSTEM VERSIONING
  PARTITION BY SYSTEM_TIME (PARTITION p_hist HISTORY, PARTITION p_cur CURRENT);

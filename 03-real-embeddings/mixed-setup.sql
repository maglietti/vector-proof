USE scale;
DROP TABLE IF EXISTS incoming, wlog, reads_log, probe_log;
CREATE TABLE incoming (n INT PRIMARY KEY, note VARCHAR(255), v VECTOR(1536) NOT NULL);
LOAD DATA LOCAL INFILE 'load/dbpedia1536-extra.tsv' INTO TABLE incoming
  FIELDS TERMINATED BY '\t' (n, note, @h) SET v = UNHEX(@h);
CREATE TABLE wlog (id INT PRIMARY KEY, insert_us BIGINT, committed_at DATETIME(6), probed TINYINT DEFAULT 0);
CREATE TABLE reads_log (reader INT, qid INT, us BIGINT, at DATETIME(6));
CREATE TABLE probe_log (id INT, found_top1 TINYINT, lag_us BIGINT, search_us BIGINT);

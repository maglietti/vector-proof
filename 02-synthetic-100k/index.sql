USE demo;
ALTER TABLE mem ADD VECTOR INDEX (embedding) M=16 DISTANCE=cosine;

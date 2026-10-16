LIST @RAW.DLD.DLD_STAGE;

SELECT SPLIT_PART("name", '/', 2)            AS dataset,
       COUNT(*)                              AS files,
       ROUND(SUM("size") / 1024 / 1024, 1)   AS stored_mb
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP BY 1
ORDER BY 1;

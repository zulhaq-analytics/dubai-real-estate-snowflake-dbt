EXECUTE IMMEDIATE $$
DECLARE
  datasets ARRAY DEFAULT ARRAY_CONSTRUCT('lkp_areas','lkp_market_types','lkp_transaction_groups','lkp_transaction_procedures');
  ds   VARCHAR;
  q    VARCHAR;
  cols VARCHAR;
  msg  VARCHAR DEFAULT '';
BEGIN
  FOR i IN 0 TO ARRAY_SIZE(datasets) - 1 DO
    ds := datasets[i]::VARCHAR;
    q := 'SELECT LISTAGG(''"'' || UPPER(COLUMN_NAME) || ''" VARCHAR'', '', '') WITHIN GROUP (ORDER BY ORDER_ID) ' ||
         'FROM TABLE(INFER_SCHEMA(LOCATION => ''@RAW.DLD.DLD_STAGE/' || ds || '/'', FILE_FORMAT => ''RAW.DLD.FF_CSV_HEADER''))';
    EXECUTE IMMEDIATE :q;
    SELECT $1 INTO :cols FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    q := 'CREATE OR REPLACE TABLE RAW.DLD.' || UPPER(ds) || ' (' || cols || ', _SOURCE_FILE VARCHAR, _LOADED_AT TIMESTAMP_LTZ)';
    EXECUTE IMMEDIATE :q;
    msg := msg || UPPER(ds) || ' created; ';
  END FOR;
  RETURN msg;
END;
$$;

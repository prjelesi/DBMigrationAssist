Select 'TABLE COUNT' As "TABLE COUNT";

Select 'Table Count Info' as "Table Count Info";

DO $$
DECLARE
  table_record RECORD;
  row_count BIGINT;
BEGIN
   RAISE NOTICE 'Schema.TableName	: RowCount';
   RAISE NOTICE '---------------------------------';
  FOR table_record IN (SELECT Schemaname, tablename FROM pg_tables
                       WHERE schemaname not in (
                          'pg_catalog',
                           'information_schema',
                           'aws_postgis',
                           'aws_oracle_ext_keys',
                           'aws_oracle_ext',
                           'aws_oracle_data',
                           'pg_toast')
              ORDER BY 1) LOOP
    EXECUTE format('SELECT COUNT(*) FROM %I.%I', table_record.Schemaname, table_record.tablename ) INTO row_count;
    RAISE NOTICE '%.% 	:  %',table_record.Schemaname, table_record.tablename, row_count;
  END LOOP;
END $$;

Select 'TABLE COUNT END' As "TABLE COUNT";

\q